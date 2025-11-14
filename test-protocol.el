;;; test-protocol.el --- Manual protocol testing -*- lexical-binding: t; -*-

;;; Commentary:

;; This file provides helpers for manually testing the Amp protocol.
;; Load it to experiment with the server/client without full Amp CLI.

;;; Code:

(require 'amp-server)
(require 'amp-client)

;;;; Mock Amp Client (for testing without actual Amp CLI)

(defvar test-protocol--socket-process nil
  "Mock client socket process.")

(defun test-protocol-connect ()
  "Connect a mock client to the Amp server."
  (interactive)
  (let* ((lockfile-dir (expand-file-name "ide" amp-server-data-home))
         (lockfiles (directory-files lockfile-dir t "emacs-.*\\.lock$")))
    (if (null lockfiles)
        (user-error "No Amp server running. Start with M-x amp-server-start")
      (let* ((lockfile (car lockfiles))
             (lock-data (with-temp-buffer
                          (insert-file-contents lockfile)
                          (goto-char (point-min))
                          (json-parse-buffer :object-type 'alist)))
             (socket-path (alist-get 'socket_path lock-data)))
        (message "Connecting to socket: %s" socket-path)
        
        (setq test-protocol--socket-process
              (make-network-process
               :name "test-amp-client"
               :family 'local
               :remote socket-path
               :coding 'utf-8
               :filter #'test-protocol--client-filter
               :sentinel #'test-protocol--client-sentinel
               :noquery t))
        
        (message "Connected to Amp server")))))

(defun test-protocol--client-filter (proc string)
  "Handle data received from server."
  (message "Received from server: %s" string))

(defun test-protocol--client-sentinel (proc event)
  "Handle client process events."
  (message "Client event: %s" event))

(defun test-protocol-disconnect ()
  "Disconnect the mock client."
  (interactive)
  (when test-protocol--socket-process
    (delete-process test-protocol--socket-process)
    (setq test-protocol--socket-process nil)
    (message "Disconnected from server")))

(defun test-protocol-send (type &optional data)
  "Send a test message of TYPE with optional DATA."
  (interactive
   (list (intern (completing-read "Message type: "
                                   '("ping" "pong" "diagnostics_request")))
         nil))
  (unless test-protocol--socket-process
    (user-error "Not connected. Use M-x test-protocol-connect"))
  
  (let* ((message (if data
                      (append `((type . ,type)) data)
                    `((type . ,type))))
         (json-str (json-encode message))
         (payload (concat json-str "\n")))
    (process-send-string test-protocol--socket-process payload)
    (message "Sent: %s" json-str)))

;;;; Test Scenarios

(defun test-protocol-scenario-1 ()
  "Test basic ping/pong."
  (interactive)
  (amp-server-start default-directory)
  (sit-for 0.5)
  (test-protocol-connect)
  (sit-for 0.5)
  (test-protocol-send 'ping)
  (message "Check *Messages* for 'pong' response"))

(defun test-protocol-scenario-2 ()
  "Test buffer notifications."
  (interactive)
  (amp-server-start default-directory)
  (amp-client-enable)
  (message "Switch buffers and watch *Messages* for notifications")
  (message "Enable debugging: (setq amp-server-log-level 'debug)"))

(defun test-protocol-cleanup ()
  "Clean up all test resources."
  (interactive)
  (test-protocol-disconnect)
  (amp-client-disable)
  (amp-server-stop)
  (message "Cleaned up all test resources"))

;;;; Interactive Test Menu

(defun test-protocol-menu ()
  "Show interactive test menu."
  (interactive)
  (let ((choice (completing-read
                 "Test Protocol Action: "
                 '("1. Start server"
                   "2. Connect mock client"
                   "3. Send ping"
                   "4. Test buffer notifications"
                   "5. Disconnect"
                   "6. Stop server"
                   "7. Full cleanup"
                   "8. Run scenario 1 (ping/pong)"
                   "9. Run scenario 2 (buffer notifications)")
                 nil t)))
    (pcase choice
      ("1. Start server" (amp-server-start default-directory))
      ("2. Connect mock client" (test-protocol-connect))
      ("3. Send ping" (test-protocol-send 'ping))
      ("4. Test buffer notifications" (amp-client-enable))
      ("5. Disconnect" (test-protocol-disconnect))
      ("6. Stop server" (amp-server-stop))
      ("7. Full cleanup" (test-protocol-cleanup))
      ("8. Run scenario 1 (ping/pong)" (test-protocol-scenario-1))
      ("9. Run scenario 2 (buffer notifications)" (test-protocol-scenario-2)))))

(provide 'test-protocol)

;;; test-protocol.el ends here
