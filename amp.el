;;; amp.el --- Sourcegraph Amp integration for Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Alvar & Claude

;; Author: Alvar & Claude
;; Version: 0.2.0
;; Package-Requires: ((emacs "28.1") (websocket "1.13"))
;; Keywords: tools, ai, programming
;; URL: https://github.com/yourusername/amp-emacs

;;; Commentary:

;; Deep integration of Sourcegraph Amp with Emacs, inspired by amp.nvim.
;;
;; Features:
;; - Bidirectional communication with `amp --ide`
;; - Automatic buffer, cursor, and selection notifications
;; - Amp can read and edit buffers directly
;; - Project-aware sessions
;; - Integration with projectile/project.el
;;
;; Usage:
;;   M-x amp-start
;;   Then in a terminal: cd /your/project && amp --ide
;;
;; Commands:
;;   M-x amp-start          - Start Amp server
;;   M-x amp-stop           - Stop Amp server
;;   M-x amp-send-message   - Send message to Amp
;;   M-x amp-fix-region     - Ask Amp to fix selected code
;;   M-x amp-explain-region - Ask Amp to explain selected code

;;; Code:

(require 'amp-server)
(require 'amp-client)

(defgroup amp nil
  "Sourcegraph Amp integration for Emacs."
  :group 'tools
  :prefix "amp-")

(defcustom amp-auto-start t
  "Automatically start Amp server when Emacs starts."
  :type 'boolean
  :group 'amp)

(defcustom amp-keybindings-prefix "C-c a"
  "Prefix key for Amp commands."
  :type 'string
  :group 'amp)

;;;; Main Commands

;;;###autoload
(defun amp-start ()
  "Start Amp server and enable client notifications."
  (interactive)
  (condition-case err
      (progn
        (amp-server-start)
        (amp-client-enable)
        (message "Amp started. Run 'amp --ide' in your project terminal."))
    (error
     (message "Failed to start Amp: %s" (error-message-string err)))))

;;;###autoload
(defun amp-stop ()
  "Stop Amp server and disable client notifications."
  (interactive)
  (amp-client-disable)
  (amp-server-stop)
  (message "Amp stopped"))

;;;###autoload
(defun amp-restart ()
  "Restart Amp server."
  (interactive)
  (amp-stop)
  (sit-for 0.5)
  (amp-start))

;;;###autoload
(defun amp-status ()
  "Show Amp status."
  (interactive)
  (amp-server-status))

;;;; User-facing Commands

;;;###autoload
(defun amp-send-message (message)
  "Send MESSAGE to Amp agent."
  (interactive "sMessage to Amp: ")
  (amp-client-send-message message))

;;;###autoload
(defun amp-fix-region (start end)
  "Ask Amp to fix code in region between START and END."
  (interactive "r")
  (if (use-region-p)
      (let ((text (buffer-substring-no-properties start end)))
        (amp-client-send-message (format "Fix this code:\n\n%s" text))
        (message "Asked Amp to fix region"))
    (user-error "No region selected")))

;;;###autoload
(defun amp-improve-region (start end)
  "Ask Amp to improve code in region between START and END."
  (interactive "r")
  (if (use-region-p)
      (let ((text (buffer-substring-no-properties start end)))
        (amp-client-send-message (format "Improve this code:\n\n%s" text))
        (message "Asked Amp to improve region"))
    (user-error "No region selected")))

;;;###autoload
(defun amp-explain-region (start end)
  "Ask Amp to explain code in region between START and END."
  (interactive "r")
  (if (use-region-p)
      (let ((text (buffer-substring-no-properties start end)))
        (amp-client-send-message (format "Explain this code:\n\n%s" text))
        (message "Asked Amp to explain region"))
    (user-error "No region selected")))

;;;###autoload
(defun amp-prompt-for-region (start end prompt)
  "Send region between START and END to Amp with custom PROMPT."
  (interactive "r\nsPrompt: ")
  (if (use-region-p)
      (let ((text (buffer-substring-no-properties start end)))
        (amp-client-send-message (format "%s\n\n%s" prompt text))
        (message "Sent region to Amp with custom prompt"))
    (user-error "No region selected")))

;;;; Keybindings

(defvar amp-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Main commands
    (define-key map (kbd "C-c a s") #'amp-start)
    (define-key map (kbd "C-c a q") #'amp-stop)
    (define-key map (kbd "C-c a r") #'amp-restart)
    (define-key map (kbd "C-c a ?") #'amp-status)
    
    ;; User commands
    (define-key map (kbd "C-c a m") #'amp-send-message)
    (define-key map (kbd "C-c a f") #'amp-fix-region)
    (define-key map (kbd "C-c a i") #'amp-improve-region)
    (define-key map (kbd "C-c a e") #'amp-explain-region)
    (define-key map (kbd "C-c a p") #'amp-prompt-for-region)
    
    map)
  "Keymap for Amp mode.")

;;;; Minor Mode

;;;###autoload
(define-minor-mode amp-mode
  "Minor mode for Amp integration."
  :lighter " Amp"
  :keymap amp-mode-map
  :global t
  (if amp-mode
      (when amp-auto-start
        (amp-start))
    (amp-stop)))

;;;; Setup

;;;###autoload
(defun amp-setup ()
  "Set up Amp integration."
  (interactive)
  (amp-mode 1))

;; Auto-start if configured
(when amp-auto-start
  (add-hook 'after-init-hook #'amp-setup))

(provide 'amp)

;;; amp.el ends here
