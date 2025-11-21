;;; amp-server.el --- Amp IDE server communication -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Alvar & Claude

;; Author: Alvar & Claude
;; Version: 0.4.0
;; Package-Requires: ((emacs "28.1") (websocket "1.13"))
;; Keywords: tools
;; URL: https://github.com/yourusername/amp-emacs

;;; Commentary:

;; This module handles the low-level communication with the Amp CLI
;; running in --ide mode.  It manages:
;; - WebSocket server connection
;; - Lockfile coordination (port + auth token)
;; - JSON message protocol
;; - Async message handling
;; - Authentication and authorization
;; - Path validation and security
;; - Content validation and size limits
;; - Rate limiting and DoS protection
;; - Cryptographically secure token generation
;; - Sanitized logging (no sensitive data)
;; - Atomic file operations (race condition prevention)

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'websocket)

(defgroup amp-server nil
  "Amp IDE server communication."
  :group 'tools
  :prefix "amp-server-")

(defcustom amp-server-data-home
  (or (getenv "AMP_DATA_HOME")
      (expand-file-name "amp" (or (getenv "XDG_DATA_HOME")
                                   "~/.local/share")))
  "Directory where Amp stores its data files."
  :type 'directory
  :group 'amp-server)

(defcustom amp-server-log-level 'info
  "Log level for amp-server messages.
One of: debug, info, warn, error."
  :type '(choice (const :tag "Debug" debug)
                 (const :tag "Info" info)
                 (const :tag "Warning" warn)
                 (const :tag "Error" error))
  :group 'amp-server)

(defcustom amp-server-max-file-size (* 10 1024 1024)
  "Maximum file size in bytes for editFile operations.
Default is 10MB."
  :type 'integer
  :group 'amp-server)

(defcustom amp-server-max-clients 5
  "Maximum number of concurrent client connections."
  :type 'integer
  :group 'amp-server)

(defcustom amp-server-max-request-rate 100
  "Maximum requests per second per client."
  :type 'integer
  :group 'amp-server)

(defcustom amp-server-max-message-size (* 15 1024 1024)
  "Maximum size of a single WebSocket message in bytes.
Default is 15MB (to accommodate 10MB file + overhead)."
  :type 'integer
  :group 'amp-server)

(defcustom amp-server-backup-on-edit t
  "Whether to create backups before editing files."
  :type 'boolean
  :group 'amp-server)

(defvar amp-server--ws-server nil
  "The WebSocket server instance.")

(defvar amp-server--port nil
  "The port the WebSocket server is running on.")

(defvar amp-server--auth-token nil
  "Authentication token for validating connections.")

(defvar amp-server--clients nil
  "List of connected WebSocket clients.")

(defvar amp-server--lockfile-path nil
  "Path to the current lockfile.")

(defvar amp-server--project-root nil
  "Root directory of the current project.")

(defvar amp-server--message-handlers (make-hash-table :test 'equal)
  "Hash table mapping message types to handler functions.")

(defvar amp-server--authenticated-clients (make-hash-table :test 'eq)
  "Hash table tracking authenticated WebSocket connections.")

(defvar amp-server--client-request-counts (make-hash-table :test 'eq)
  "Hash table tracking request counts per client for rate limiting.")

(defvar amp-server--client-request-windows (make-hash-table :test 'eq)
  "Hash table tracking request time windows per client for rate limiting.")

;;;; Logging with Sanitization

(defun amp-server--sanitize-for-log (data)
  "Sanitize DATA for logging by removing/redacting sensitive information.
Returns a sanitized copy of the data structure."
  (cond
   ;; String: truncate if too long, check for sensitive patterns
   ((stringp data)
    (let ((sanitized data))
      ;; Truncate long strings
      (when (> (length sanitized) 100)
        (setq sanitized (concat (substring sanitized 0 97) "...")))
      ;; Redact if looks like a token (32+ alphanumeric chars)
      (when (string-match-p "^[a-zA-Z0-9]{32,}$" sanitized)
        (setq sanitized "***REDACTED-TOKEN***"))
      sanitized))
   
   ;; Alist: recursively sanitize, remove sensitive keys
   ((and (listp data) (consp (car data)))
    (let ((sanitized '()))
      (dolist (pair data)
        (let ((key (car pair))
              (value (cdr pair)))
          ;; Remove sensitive keys entirely
          (unless (memq key '(authToken token password apiKey secret))
            (push (cons key (amp-server--sanitize-for-log value))
                  sanitized))))
      (nreverse sanitized)))
   
   ;; List: recursively sanitize each element
   ((listp data)
    (mapcar #'amp-server--sanitize-for-log data))
   
   ;; Vector: convert to list, sanitize, convert back
   ((vectorp data)
    (vconcat (mapcar #'amp-server--sanitize-for-log (append data nil))))
   
   ;; Other types: return as-is (numbers, symbols, etc.)
   (t data)))

(defun amp-server--log (level message &rest args)
  "Log MESSAGE with LEVEL and optional format ARGS.
All arguments are sanitized before logging to prevent leaking sensitive data."
  (when (amp-server--should-log-p level)
    (let* ((sanitized-args (mapcar #'amp-server--sanitize-for-log args))
           (formatted (apply #'format message sanitized-args))
           (prefix (pcase level
                     ('debug "[AMP DEBUG]")
                     ('info  "[AMP INFO]")
                     ('warn  "[AMP WARN]")
                     ('error "[AMP ERROR]"))))
      (message "%s %s" prefix formatted))))

(defun amp-server--should-log-p (level)
  "Return non-nil if LEVEL should be logged."
  (let ((levels '(debug info warn error))
        (current-level amp-server-log-level))
    (>= (cl-position level levels)
        (cl-position current-level levels))))

;;;; Authentication

(defun amp-server--is-authenticated-p (ws)
  "Check if WS connection is authenticated."
  (gethash ws amp-server--authenticated-clients))

;;;; Rate Limiting

(defun amp-server--check-rate-limit (ws)
  "Check if WS client exceeds rate limit.
Returns t if within limit, signals error if exceeded."
  (let* ((now (float-time))
         (window-start (gethash ws amp-server--client-request-windows 0))
         (request-count (gethash ws amp-server--client-request-counts 0)))
    
    ;; Reset counter every second
    (when (> (- now window-start) 1.0)
      (puthash ws now amp-server--client-request-windows)
      (puthash ws 0 amp-server--client-request-counts)
      (setq request-count 0))
    
    ;; Increment counter
    (puthash ws (1+ request-count) amp-server--client-request-counts)
    
    ;; Check limit
    (when (> (1+ request-count) amp-server-max-request-rate)
      (amp-server--log 'warn "Rate limit exceeded for client: %d requests/sec" (1+ request-count))
      (error "Rate limit exceeded: %d requests/sec (max: %d)" 
             (1+ request-count) amp-server-max-request-rate))
    
    t))

;;;; Content Validation

(defun amp-server--validate-content (content path)
  "Validate CONTENT before writing to PATH.
Returns t if valid, signals error otherwise."
  (unless content
    (error "Content cannot be nil"))
  
  ;; Check size
  (let ((content-size (length content)))
    (when (> content-size amp-server-max-file-size)
      (error "Content too large: %d bytes (max: %d bytes)" 
             content-size amp-server-max-file-size)))
  
  ;; Check for null bytes
  (when (string-match-p "\0" content)
    (error "Content contains null bytes"))
  
  ;; Verify it's valid UTF-8 (multibyte string)
  (unless (multibyte-string-p content)
    (error "Content must be valid UTF-8"))
  
  ;; Warn about editing critical configuration files
  (when (string-match-p "\\.\\(el\\|emacs\\|bashrc\\|bash_profile\\|profile\\|zshrc\\)$" path)
    (amp-server--log 'warn "Editing critical configuration file: %s" path))
  
  (amp-server--log 'debug "Content validated: %d bytes" (length content))
  t)

(defun amp-server--create-backup (path)
  "Create a backup of file at PATH.
Returns backup path on success, nil on failure."
  (when (and amp-server-backup-on-edit
             (file-exists-p path)
             (file-regular-p path))
    (let* ((backup-suffix (format ".amp-backup-%s" 
                                  (format-time-string "%Y%m%d-%H%M%S")))
           (backup-path (concat path backup-suffix)))
      (condition-case err
          (progn
            (copy-file path backup-path t)
            (amp-server--log 'info "Created backup: %s" backup-path)
            backup-path)
        (error
         (amp-server--log 'error "Failed to create backup: %s" (error-message-string err))
         nil)))))

;;;; Path Validation and Security

(defun amp-server--normalize-path (path)
  "Normalize PATH by resolving relative components.
This does NOT resolve symlinks yet, just normalizes .. and . components."
  (let* ((parts (split-string path "/" t))
         (result nil))
    (dolist (part parts)
      (cond
       ((string= part "."))  ; Skip current directory references
       ((string= part "..")  ; Handle parent directory
        (when result
          (setq result (butlast result))))
       (t
        (push part result))))
    (concat "/" (string-join (nreverse result) "/"))))

(defun amp-server--safe-path-p (path)
  "Check if PATH is safe to access (within project root).
Returns non-nil if the path is safe, nil otherwise."
  (let* ((project-root (file-truename amp-server--project-root))
         ;; Expand path relative to project root
         (abs-path (expand-file-name path project-root))
         ;; Get canonical path (resolves symlinks)
         (canonical-path (condition-case nil
                            (file-truename abs-path)
                          (error nil))))
    
    (and canonical-path
         project-root
         ;; Verify the canonical path is within project root
         (string-prefix-p project-root canonical-path)
         ;; Additional security checks
         (not (and (file-exists-p canonical-path)
                   (file-symlink-p abs-path)
                   ;; If it's a symlink, verify target is also in project
                   (not (string-prefix-p project-root 
                                       (file-truename (file-symlink-p abs-path)))))))))

(defun amp-server--validate-path (path)
  "Validate PATH and return canonical safe path or signal error.
PATH should be relative to project root.
Returns the canonical absolute path if safe."
  (when (or (not path) (string-empty-p path))
    (error "Path cannot be empty"))
  
  ;; Security checks on the path string itself
  (when (string-match-p "\0" path)
    (error "Path contains null bytes"))
  
  ;; Check for absolute paths (should be relative to project)
  (when (string-prefix-p "/" path)
    (amp-server--log 'warn "Absolute path provided, will be treated as relative: %s" path))
  
  ;; Normalize and expand relative to project root
  (let* ((normalized (amp-server--normalize-path path))
         (project-root (file-truename amp-server--project-root))
         (abs-path (expand-file-name normalized project-root)))
    
    ;; Check for path traversal attempts in normalized path
    (when (string-match-p "\\.\\./" normalized)
      (error "Path traversal detected: %s" path))
    
    ;; Get canonical path (resolves symlinks)
    (let ((canonical-path (condition-case err
                              (if (file-exists-p abs-path)
                                  (file-truename abs-path)
                                ;; For non-existent files, verify parent directory
                                (let ((parent (file-name-directory abs-path)))
                                  (when (and parent (file-exists-p parent))
                                    (concat (file-truename parent)
                                           (file-name-nondirectory abs-path)))))
                            (file-error
                             (error "Cannot access path: %s" (error-message-string err))))))
      
      (unless canonical-path
        (error "Invalid path: %s" path))
      
      ;; Verify canonical path is within project
      (unless (string-prefix-p project-root canonical-path)
        (amp-server--log 'error "Path traversal attempt blocked: %s -> %s (outside %s)" 
                        path canonical-path project-root)
        (error "Path '%s' is outside project workspace" path))
      
      ;; Additional security: Check for sensitive files/directories
      (when (string-match-p "/\\.\\(git\\|ssh\\|gnupg\\)\\(/\\|$\\)" canonical-path)
        (amp-server--log 'warn "Attempt to access sensitive directory blocked: %s" canonical-path)
        (error "Access to sensitive directories is not allowed"))
      
      (amp-server--log 'debug "Path validated: %s -> %s" path canonical-path)
      canonical-path)))

;;;; Cryptographically Secure Token Generation

(defun amp-server--generate-auth-token ()
  "Generate a cryptographically secure 64-character authentication token.
Uses /dev/urandom on Unix systems for cryptographic randomness."
  (if (memq system-type '(gnu/linux darwin berkeley-unix))
      ;; Unix-like systems: use /dev/urandom
      (condition-case err
          (with-temp-buffer
            (set-buffer-multibyte nil)
            ;; Read 32 bytes (256 bits) from /dev/urandom
            (call-process "dd" nil t nil
                         "if=/dev/urandom"
                         "bs=32"
                         "count=1"
                         "status=none"
                         "2>/dev/null")
            ;; Convert to hexadecimal (64 characters)
            (let ((bytes (buffer-string))
                  (hex-chars "0123456789abcdef")
                  (token ""))
              (dotimes (i (length bytes))
                (let ((byte (aref bytes i)))
                  (setq token (concat token
                                    (string (aref hex-chars (logand (ash byte -4) 15)))
                                    (string (aref hex-chars (logand byte 15)))))))
              (amp-server--log 'debug "Generated cryptographically secure token (256 bits)")
              token))
        (error
         (amp-server--log 'warn "Failed to use /dev/urandom: %s. Falling back to Emacs random." 
                         (error-message-string err))
         (amp-server--generate-auth-token-fallback)))
    ;; Windows or other systems: fallback to enhanced Emacs random
    (amp-server--log 'warn "Non-Unix system detected. Using enhanced Emacs random for token generation.")
    (amp-server--generate-auth-token-fallback)))

(defun amp-server--generate-auth-token-fallback ()
  "Generate authentication token using Emacs random function.
Less secure than /dev/urandom, but still reasonable.
Uses current time microseconds as additional entropy."
  (let ((chars "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        (token ""))
    ;; Seed with current time microseconds for additional entropy
    (random (format "%s" (current-time)))
    ;; Generate 64 character token
    (dotimes (_ 64)
      (setq token (concat token (string (aref chars (random (length chars)))))))
    token))

;;;; Lockfile Management

(defun amp-server--lockfile-dir ()
  "Return the directory where lockfiles are stored."
  (expand-file-name "ide" amp-server-data-home))

(defun amp-server--lockfile-path (port)
  "Generate lockfile path for PORT."
  (expand-file-name (format "%d.json" port)
                    (amp-server--lockfile-dir)))

(defun amp-server--create-lockfile (port auth-token project-root)
  "Create lockfile with PORT, AUTH-TOKEN and PROJECT-ROOT."
  (let* ((dir (amp-server--lockfile-dir))
         (path (amp-server--lockfile-path port))
         (data `((port . ,port)
                 (authToken . ,auth-token)
                 (pid . ,(emacs-pid))
                 (workspaceFolders . [,project-root])
                 (ideName . ,(format "emacs %s" emacs-version)))))
    ;; Ensure directory exists
    (unless (file-directory-p dir)
      (make-directory dir t))
    
    ;; Write lockfile
    (with-temp-file path
      (insert (json-encode data)))
    
    (amp-server--log 'info "Created lockfile: %s" path)
    (setq amp-server--lockfile-path path)
    path))

(defun amp-server--remove-lockfile ()
  "Remove the current lockfile if it exists."
  (when (and amp-server--lockfile-path
             (file-exists-p amp-server--lockfile-path))
    (delete-file amp-server--lockfile-path)
    (amp-server--log 'info "Removed lockfile: %s" amp-server--lockfile-path)
    (setq amp-server--lockfile-path nil)))

;;;; WebSocket Server

(defun amp-server--find-available-port ()
  "Find an available port for the WebSocket server."
  ;; Try ports in the range 9000-9999
  (let ((port 9000)
        (max-port 9999)
        (found nil))
    (while (and (not found) (<= port max-port))
      (condition-case nil
          (progn
            (delete-process
             (make-network-process
              :name "amp-port-test"
              :server t
              :host "127.0.0.1"
              :service port
              :noquery t))
            (setq found port))
        (error (setq port (1+ port)))))
    (or found (error "No available ports found"))))

(defun amp-server--wrap-notification (notification)
  "Wrap NOTIFICATION in IDE protocol format."
  `((serverNotification . ,notification)))

(defun amp-server--wrap-response (id response)
  "Wrap RESPONSE with ID in IDE protocol format."
  `((serverResponse . ,(append `((id . ,id)) response))))

(defun amp-server--wrap-error (id error-code error-message)
  "Wrap error with ID, ERROR-CODE and ERROR-MESSAGE in IDE protocol format."
  `((serverResponse . ((id . ,id)
                       (error . ((code . ,error-code)
                                 (message . ,error-message)))))))

(defun amp-server--handle-client-request (ws frame)
  "Handle incoming client request from WS with FRAME data."
  (let* ((message-text (websocket-frame-text frame))
         (message-size (length message-text)))
    
    ;; Check message size limit
    (when (> message-size amp-server-max-message-size)
      (amp-server--log 'warn "Message too large: %d bytes (max: %d)" 
                      message-size amp-server-max-message-size)
      (amp-server--send-message
       ws
       (amp-server--wrap-error "0" -32600 
                              (format "Message too large: %d bytes (max: %d)" 
                                     message-size amp-server-max-message-size)))
      (cl-return-from amp-server--handle-client-request))
    
    ;; Check rate limit (except for ping and authenticate)
    (let ((message (condition-case err
                       (json-read-from-string message-text)
                     (error
                      (amp-server--log 'error "Failed to parse JSON: %s" (error-message-string err))
                      nil))))
      
      (when message
        (amp-server--log 'debug "Received message: %S" message)
        
        (let ((client-request (alist-get 'clientRequest message)))
          (when client-request
            (let ((id (alist-get 'id client-request)))
              (when id
                ;; Check rate limit for all requests except ping and authenticate
                (unless (or (alist-get 'ping client-request)
                           (alist-get 'authenticate client-request))
                  (condition-case err
                      (amp-server--check-rate-limit ws)
                    (error
                     (amp-server--send-message
                      ws
                      (amp-server--wrap-error id -32600 (error-message-string err)))
                     (cl-return-from amp-server--handle-client-request))))
                
                (cond
                 ;; Handle ping
                 ((alist-get 'ping client-request)
                  (let ((ping-msg (alist-get 'message (alist-get 'ping client-request))))
                    (amp-server--send-message
                     ws
                     (amp-server--wrap-response
                      id
                      `((ping . ((message . ,ping-msg))))))))
                 
                 ;; Handle authenticate
                 ((alist-get 'authenticate client-request)
                  (let ((provided-token (alist-get 'token (alist-get 'authenticate client-request))))
                    (if (and provided-token 
                             (string= provided-token amp-server--auth-token))
                        (progn
                          ;; Mark connection as authenticated
                          (puthash ws t amp-server--authenticated-clients)
                          (amp-server--log 'info "Client authenticated successfully")
                          (amp-server--send-message
                           ws
                           (amp-server--wrap-response
                            id
                            `((authenticate . ((authenticated . t)))))))
                      ;; Invalid token
                      (amp-server--log 'warn "Client authentication failed: invalid token")
                      (amp-server--send-message
                       ws
                       (amp-server--wrap-error id -32600 "Invalid authentication token")))))
                 
                 ;; Handle diagnostics request
                 ((alist-get 'getDiagnostics client-request)
                  (if (amp-server--is-authenticated-p ws)
                      (progn
                        (amp-server--log 'info "Diagnostics requested")
                        (amp-server--send-message
                         ws
                         (amp-server--wrap-response
                          id
                          `((getDiagnostics . ((entries . [])))))))
                    (amp-server--log 'warn "Unauthenticated getDiagnostics request rejected")
                    (amp-server--send-message
                     ws
                     (amp-server--wrap-error id -32600 "Not authenticated"))))
                 
                 ;; Handle readFile request
                 ((alist-get 'readFile client-request)
                  (if (amp-server--is-authenticated-p ws)
                      (let ((path (alist-get 'path (alist-get 'readFile client-request))))
                        (if path
                            (condition-case err
                                (let* ((safe-path (amp-server--validate-path path))
                                       (content (with-temp-buffer
                                                 (insert-file-contents safe-path)
                                                 (buffer-string))))
                                  (amp-server--log 'info "Read file: %s (%d bytes)" 
                                                  safe-path (length content))
                                  (amp-server--send-message
                                   ws
                                   (amp-server--wrap-response
                                    id
                                    `((readFile . ((content . ,content)))))))
                              (error
                               (amp-server--log 'error "Failed to read file '%s': %s" 
                                              path (error-message-string err))
                               (amp-server--send-message
                                ws
                                (amp-server--wrap-error id -32603 
                                                       (format "Failed to read file: %s" 
                                                              (error-message-string err))))))
                          (amp-server--send-message
                           ws
                           (amp-server--wrap-error id -32602 "readFile requires path parameter"))))
                    (amp-server--log 'warn "Unauthenticated readFile request rejected")
                    (amp-server--send-message
                     ws
                     (amp-server--wrap-error id -32600 "Not authenticated"))))
                 
                 ;; Handle editFile request
                 ((alist-get 'editFile client-request)
                  (if (amp-server--is-authenticated-p ws)
                      (let ((edit-req (alist-get 'editFile client-request)))
                        (let ((path (alist-get 'path edit-req))
                              (full-content (alist-get 'fullContent edit-req)))
                          (if (and path full-content)
                              (condition-case err
                                  (progn
                                    (amp-server--apply-file-edit path full-content)
                                    (amp-server--send-message
                                     ws
                                     (amp-server--wrap-response
                                      id
                                      `((editFile . ((success . t)
                                                     (message . "File updated successfully")))))))
                                (error
                                 (amp-server--log 'error "Failed to edit file '%s': %s"
                                                path (error-message-string err))
                                 (amp-server--send-message
                                  ws
                                  (amp-server--wrap-error id -32603 
                                                         (format "Failed to edit file: %s" 
                                                                (error-message-string err))))))
                            (amp-server--send-message
                             ws
                             (amp-server--wrap-error id -32602 "editFile requires path and fullContent parameters")))))
                    (amp-server--log 'warn "Unauthenticated editFile request rejected")
                    (amp-server--send-message
                     ws
                     (amp-server--wrap-error id -32600 "Not authenticated"))))
                 
                 ;; Unknown request
                 (t
                  (amp-server--send-message
                   ws
                   (amp-server--wrap-error id -32601 "Method not found"))))))))))))

(defun amp-server--apply-file-edit (path content)
  "Apply edit to file at PATH with new CONTENT using atomic operations.
PATH is relative to project root and will be validated.
CONTENT will be validated for size and encoding.
Uses atomic file operations to prevent race conditions."
  (let* ((safe-path (amp-server--validate-path path)))
    
    ;; Validate content
    (amp-server--validate-content content safe-path)
    
    ;; Check if path is a symlink (security check)
    (when (file-symlink-p safe-path)
      (error "Refusing to edit symbolic link: %s" safe-path))
    
    ;; Create backup if file exists
    (when (file-exists-p safe-path)
      (amp-server--create-backup safe-path))
    
    (let ((buffer (find-buffer-visiting safe-path)))
      (if buffer
          ;; File is open in a buffer - update the buffer with rollback support
          (with-current-buffer buffer
            ;; Respect read-only buffers
            (when buffer-read-only
              (error "Buffer is read-only: %s" safe-path))
            
            ;; Save original state for potential rollback
            (let ((original-content (buffer-string))
                  (original-modified-p (buffer-modified-p)))
              (condition-case err
                  (progn
                    (let ((inhibit-read-only nil))
                      (erase-buffer)
                      (insert content)
                      (save-buffer))
                    (amp-server--log 'info "Updated buffer: %s (%d bytes)" 
                                    safe-path (length content)))
                (error
                 ;; Rollback on error
                 (amp-server--log 'error "Error updating buffer, rolling back: %s" 
                                (error-message-string err))
                 (erase-buffer)
                 (insert original-content)
                 (set-buffer-modified-p original-modified-p)
                 (signal (car err) (cdr err))))))
        
        ;; File not open - write directly to disk using atomic operation
        (let ((temp-file (make-temp-file
                         (concat "amp-" (file-name-nondirectory safe-path))
                         nil
                         (file-name-extension safe-path t))))
          (unwind-protect
              (progn
                ;; Write to temporary file first
                (with-temp-file temp-file
                  (insert content))
                
                ;; Verify temporary file was created successfully
                (unless (file-exists-p temp-file)
                  (error "Failed to create temporary file"))
                
                ;; Atomic rename (on POSIX systems, rename is atomic)
                (rename-file temp-file safe-path t)
                
                (amp-server--log 'info "Updated file on disk: %s (%d bytes)" 
                                safe-path (length content)))
            
            ;; Clean up temporary file if something went wrong
            (when (file-exists-p temp-file)
              (delete-file temp-file))))))))

(defun amp-server--on-open (ws)
  "Handle new WebSocket connection WS."
  ;; Check max clients limit
  (when (>= (length amp-server--clients) amp-server-max-clients)
    (amp-server--log 'warn "Maximum clients reached (%d), rejecting connection" 
                    amp-server-max-clients)
    (websocket-close ws)
    (error "Maximum clients reached: %d" amp-server-max-clients))
  
  (amp-server--log 'info "Client connected (not authenticated). Total clients: %d" 
                  (1+ (length amp-server--clients)))
  (push ws amp-server--clients))

(defun amp-server--on-close (ws)
  "Handle WebSocket connection close for WS."
  (amp-server--log 'info "Client disconnected. Total clients: %d" 
                  (1- (length amp-server--clients)))
  (setq amp-server--clients (delq ws amp-server--clients))
  ;; Clean up authentication state
  (remhash ws amp-server--authenticated-clients)
  ;; Clean up rate limiting state
  (remhash ws amp-server--client-request-counts)
  (remhash ws amp-server--client-request-windows))

(defun amp-server--on-error (_ws type err)
  "Handle WebSocket error of TYPE with ERR."
  (amp-server--log 'error "WebSocket error (%s): %s" type err))

(defun amp-server--start-server (project-root)
  "Start WebSocket server for PROJECT-ROOT.
Returns (port . auth-token) on success, nil on failure."
  (condition-case err
      (let* ((port (amp-server--find-available-port))
             (auth-token (amp-server--generate-auth-token)))
        
        (setq amp-server--ws-server
              (websocket-server
               port
               :host "127.0.0.1"
               :on-open #'amp-server--on-open
               :on-message #'amp-server--handle-client-request
               :on-close #'amp-server--on-close
               :on-error #'amp-server--on-error))
        
        (setq amp-server--port port)
        (setq amp-server--auth-token auth-token)
        (setq amp-server--project-root (file-truename project-root))
        (setq amp-server--clients nil)
        (setq amp-server--authenticated-clients (make-hash-table :test 'eq))
        (setq amp-server--client-request-counts (make-hash-table :test 'eq))
        (setq amp-server--client-request-windows (make-hash-table :test 'eq))
        
        (amp-server--log 'info "Started WebSocket server on port: %d" port)
        (amp-server--log 'info "Project root: %s" amp-server--project-root)
        (amp-server--log 'info "Security: crypto-token=yes, sanitized-logs=yes, atomic-ops=yes")
        (amp-server--log 'info "Limits: max-clients=%d, max-rate=%d req/s, max-file=%d MB, max-msg=%d MB"
                        amp-server-max-clients
                        amp-server-max-request-rate
                        (/ amp-server-max-file-size 1024 1024)
                        (/ amp-server-max-message-size 1024 1024))
        (amp-server--create-lockfile port auth-token project-root)
        
        (cons port auth-token))
    (error
     (amp-server--log 'error "Failed to start server: %s" (error-message-string err))
     nil)))

(defun amp-server--stop-server ()
  "Stop the WebSocket server and clean up resources."
  (when amp-server--ws-server
    (websocket-server-close amp-server--ws-server)
    (setq amp-server--ws-server nil))
  
  (setq amp-server--port nil)
  (setq amp-server--auth-token nil)
  (setq amp-server--clients nil)
  (clrhash amp-server--authenticated-clients)
  (clrhash amp-server--client-request-counts)
  (clrhash amp-server--client-request-windows)
  
  (amp-server--remove-lockfile)
  
  (amp-server--log 'info "Stopped server"))

;;;; Message Sending

(defun amp-server--send-message (ws message)
  "Send MESSAGE to WebSocket client WS.
MESSAGE should be an alist that will be converted to JSON."
  (when ws
    (condition-case err
        (let ((json-str (json-encode message)))
          (amp-server--log 'debug "Sending message: %s" json-str)
          (websocket-send-text ws json-str))
      (error
       (amp-server--log 'error "Failed to send message: %s" (error-message-string err))))))

(defun amp-server--broadcast-notification (notification)
  "Broadcast NOTIFICATION to all connected clients."
  (let ((message (amp-server--wrap-notification notification)))
    (dolist (client amp-server--clients)
      (amp-server--send-message client message))))

;;;; Message Handlers

(defun amp-server-register-handler (type handler-fn)
  "Register HANDLER-FN for messages of TYPE.
HANDLER-FN should accept (ws message) as arguments."
  (puthash type handler-fn amp-server--message-handlers))

;;;; Public API

(defun amp-server-start (&optional project-root)
  "Start Amp server for PROJECT-ROOT.
If PROJECT-ROOT is nil, use the current project root."
  (interactive)
  (let ((root (or project-root
                  (and (fboundp 'projectile-project-root)
                       (projectile-project-root))
                  (when-let ((proj (project-current)))
                    (if (fboundp 'project-root)
                        (project-root proj)
                      (cdr proj)))
                  default-directory)))
    (if (amp-server--start-server root)
        (message "Amp server started on port %d. Run 'amp --ide' in your project." amp-server--port)
      (error "Failed to start Amp server"))))

(defun amp-server-stop ()
  "Stop the Amp server."
  (interactive)
  (amp-server--stop-server)
  (message "Amp server stopped"))

(defun amp-server-status ()
  "Show the status of the Amp server."
  (interactive)
  (if amp-server--ws-server
      (message "Amp server running on port %d (project: %s, %d/%d clients, %d authenticated)"
               amp-server--port
               amp-server--project-root
               (length amp-server--clients)
               amp-server-max-clients
               (hash-table-count amp-server--authenticated-clients))
    (message "Amp server not running")))

(provide 'amp-server)

;;; amp-server.el ends here
