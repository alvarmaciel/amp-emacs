;;; amp-server.el --- Amp IDE server communication -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Alvar & Claude

;; Author: Alvar & Claude
;; Version: 0.2.0
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

;;;; Logging

(defun amp-server--log (level message &rest args)
  "Log MESSAGE with LEVEL and optional format ARGS."
  (when (amp-server--should-log-p level)
    (let ((formatted (apply #'format message args))
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

;;;; Authentication Token

(defun amp-server--generate-auth-token ()
  "Generate a random 32-character authentication token."
  (let ((chars "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        (token ""))
    (dotimes (_ 32)
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
         (message (condition-case err
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
              ;; Handle ping
              (cond
               ((alist-get 'ping client-request)
                (let ((ping-msg (alist-get 'message (alist-get 'ping client-request))))
                  (amp-server--send-message
                   ws
                   (amp-server--wrap-response
                    id
                    `((ping . ((message . ,ping-msg))))))))
               
               ;; Handle authenticate
               ((alist-get 'authenticate client-request)
                (amp-server--send-message
                 ws
                 (amp-server--wrap-response
                  id
                  `((authenticate . ((authenticated . t)))))))
               
               ;; Handle diagnostics request
               ((alist-get 'getDiagnostics client-request)
                (amp-server--log 'info "Diagnostics requested")
                (amp-server--send-message
                 ws
                 (amp-server--wrap-response
                  id
                  `((getDiagnostics . ((entries . [])))))))
               
               ;; Handle readFile request
               ((alist-get 'readFile client-request)
                (let ((path (alist-get 'path (alist-get 'readFile client-request))))
                  (if path
                      (condition-case err
                          (let ((content (with-temp-buffer
                                          (insert-file-contents path)
                                          (buffer-string))))
                            (amp-server--send-message
                             ws
                             (amp-server--wrap-response
                              id
                              `((readFile . ((content . ,content)))))))
                        (error
                         (amp-server--send-message
                          ws
                          (amp-server--wrap-error id -32603 (format "Failed to read file: %s" (error-message-string err))))))
                    (amp-server--send-message
                     ws
                     (amp-server--wrap-error id -32602 "readFile requires path parameter")))))
               
               ;; Handle editFile request
               ((alist-get 'editFile client-request)
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
                           (amp-server--send-message
                            ws
                            (amp-server--wrap-error id -32603 (format "Failed to edit file: %s" (error-message-string err))))))
                      (amp-server--send-message
                       ws
                       (amp-server--wrap-error id -32602 "editFile requires path and fullContent parameters"))))))
               
               ;; Unknown request
               (t
                (amp-server--send-message
                 ws
                 (amp-server--wrap-error id -32601 "Method not found")))))))))))

               (defun amp-server--apply-file-edit (path content)
  "Apply edit to file at PATH with new CONTENT."
  (let* ((abs-path (expand-file-name path))
         (buffer (find-buffer-visiting abs-path)))
    (if buffer
        ;; File is open in a buffer - update the buffer
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert content)
            (save-buffer))
          (amp-server--log 'info "Updated buffer: %s" abs-path))
      ;; File not open - write directly to disk
      (with-temp-file abs-path
        (insert content))
      (amp-server--log 'info "Updated file on disk: %s" abs-path))))

(defun amp-server--on-open (ws)
  "Handle new WebSocket connection WS."
  (amp-server--log 'info "Client connected")
  (push ws amp-server--clients)
  
  ;; Client will authenticate after connection
  )

(defun amp-server--on-close (ws)
  "Handle WebSocket connection close for WS."
  (amp-server--log 'info "Client disconnected")
  (setq amp-server--clients (delq ws amp-server--clients)))

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
        (setq amp-server--project-root project-root)
        (setq amp-server--clients nil)
        
        (amp-server--log 'info "Started WebSocket server on port: %d" port)
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
      (message "Amp server running on port %d (project: %s, %d clients)"
               amp-server--port
               amp-server--project-root
               (length amp-server--clients))
    (message "Amp server not running")))

(provide 'amp-server)

;;; amp-server.el ends here

