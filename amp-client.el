;;; amp-client.el --- Amp IDE client notifications -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Alvar & Claude

;; This module handles sending editor state to Amp:
;; - Current buffer/file
;; - Cursor position
;; - Text selection
;; - Buffer changes

;;; Code:

(require 'amp-server)

(defgroup amp-client nil
  "Amp IDE client notifications."
  :group 'tools
  :prefix "amp-client-")

(defcustom amp-client-throttle-interval 0.1
  "Minimum seconds between cursor move notifications."
  :type 'number
  :group 'amp-client)

(defvar amp-client--last-buffer nil
  "Last buffer that was notified to Amp.")

(defvar amp-client--last-cursor-pos nil
  "Last cursor position that was notified to Amp.")

(defvar amp-client--last-cursor-time 0
  "Time of last cursor notification.")

(defvar amp-client--last-selection-active nil
  "Whether a selection was active in the last notification.")

(defvar amp-client--enabled nil
  "Whether client notifications are enabled.")

;;;; Buffer Notifications

(defun amp-client--get-visible-file-uris ()
  "Get URIs of currently visible files."
  (let ((uris '()))
    (when (buffer-file-name)
      (push (concat "file://" (buffer-file-name)) uris))
    (vconcat uris)))

(defun amp-client--notify-visible-files ()
  "Notify Amp about currently visible files."
  (when (and amp-client--enabled
             (buffer-file-name)
             (not (eq (current-buffer) amp-client--last-buffer)))
    (let ((uris (amp-client--get-visible-file-uris)))
      (when (> (length uris) 0)
        (amp-server--broadcast-notification
         `((visibleFilesDidChange . ((uris . ,uris)))))
        (setq amp-client--last-buffer (current-buffer))
        (amp-server--log 'debug "Visible files updated: %s" (buffer-file-name))))))

;;;; Selection Notifications

(defun amp-client--selection-info ()
  "Get information about the current selection."
  (when (and (region-active-p) (buffer-file-name))
    (let* ((start (region-beginning))
           (end (region-end))
           (text (buffer-substring-no-properties start end))
           (start-line (line-number-at-pos start))
           (start-col (save-excursion (goto-char start) (current-column)))
           (end-line (line-number-at-pos end))
           (end-col (save-excursion (goto-char end) (current-column))))
      `((path . ,(buffer-file-name))
        (content . ,text)
        (range . ((start . ((line . ,(1- start-line))
                            (character . ,start-col)))
                  (end . ((line . ,(1- end-line))
                          (character . ,end-col)))))))))

(defun amp-client--notify-selection-changed ()
  "Notify Amp about selection changes."
  (when amp-client--enabled
    (if (and (region-active-p) (use-region-p) (> (region-end) (region-beginning)))
        (let ((info (amp-client--selection-info)))
          (when info
            (amp-server--broadcast-notification
             `((selection . ,info)))
            (setq amp-client--last-selection-active t)
            (amp-server--log 'debug "Selection changed")))
      ;; Selection cleared (only if there was a previous selection)
      (when amp-client--last-selection-active
        (amp-server--broadcast-notification
         '((selection . :null)))
        (setq amp-client--last-selection-active nil)
        (amp-server--log 'debug "Selection cleared")))))

;;;; Cursor Notifications

(defun amp-client--should-notify-cursor-p ()
  "Return non-nil if we should notify about cursor position."
  (and amp-client--enabled
       (buffer-file-name)
       (or (not amp-client--last-cursor-pos)
           (not (equal (point) amp-client--last-cursor-pos))
           (> (- (float-time) amp-client--last-cursor-time)
              amp-client-throttle-interval))))

(defun amp-client--notify-cursor-moved ()
  "Notify Amp about cursor movement via visible files update."
  ;; In the IDE protocol, cursor position is communicated via visibleFiles
  ;; which includes the current file. The selection notification handles ranges.
  (when (amp-client--should-notify-cursor-p)
    (amp-client--notify-visible-files)
    (setq amp-client--last-cursor-pos (point))
    (setq amp-client--last-cursor-time (float-time))))

;;;; Hooks

(defun amp-client--post-command-hook ()
  "Hook function to run after each command."
  (amp-client--notify-visible-files)
  (amp-client--notify-cursor-moved))

(defun amp-client--activate-mark-hook ()
  "Hook function when mark is activated."
  (amp-client--notify-selection-changed))

(defun amp-client--deactivate-mark-hook ()
  "Hook function when mark is deactivated."
  (when (and amp-client--enabled amp-client--last-selection-active)
    (amp-server--broadcast-notification '((selection . :null)))
    (setq amp-client--last-selection-active nil)
    (amp-server--log 'debug "Selection cleared")))

;;;; User State

(defun amp-client--get-user-state ()
  "Get current editor state for Amp context."
  (let ((state nil))
    ;; Add visible files
    (when (buffer-file-name)
      (push `(visibleFiles . ,(vector (concat "file://" (buffer-file-name)))) state))
    
    ;; Add cursor position
    (when (buffer-file-name)
      (let* ((line (1- (line-number-at-pos)))
             (col (current-column)))
        (push `(cursorPosition . ((file . ,(buffer-file-name))
                                  (line . ,line)
                                  (character . ,col)))
              state)))
    
    ;; Add selection if active
    (when (and (region-active-p) (use-region-p))
      (let ((selection (amp-client--selection-info)))
        (when selection
          (push `(selection . ,selection) state))))
    
    state))

;;;; Public API

(defun amp-client-enable ()
  "Enable Amp client notifications."
  (interactive)
  (unless amp-client--enabled
    (setq amp-client--enabled t)
    
    ;; Add hooks
    (add-hook 'post-command-hook #'amp-client--post-command-hook)
    (add-hook 'activate-mark-hook #'amp-client--activate-mark-hook)
    (add-hook 'deactivate-mark-hook #'amp-client--deactivate-mark-hook)
    
    ;; Send initial state
    (amp-client--notify-visible-files)
    
    (message "Amp client notifications enabled")))

(defun amp-client-disable ()
  "Disable Amp client notifications."
  (interactive)
  (when amp-client--enabled
    (setq amp-client--enabled nil)
    
    ;; Remove hooks
    (remove-hook 'post-command-hook #'amp-client--post-command-hook)
    (remove-hook 'activate-mark-hook #'amp-client--activate-mark-hook)
    (remove-hook 'deactivate-mark-hook #'amp-client--deactivate-mark-hook)
    
    (message "Amp client notifications disabled")))

(defun amp-client-send-message (message)
  "Send a text MESSAGE to the Amp agent."
  (interactive "sMessage to Amp: ")
  (when amp-client--enabled
    (let ((user-state (amp-client--get-user-state)))
      (amp-server--broadcast-notification
       `((userSentMessage . ((message . ,message)
                             (userState . ,user-state))))))
    (message "Sent message to Amp")))

(defun amp-client-send-region (start end)
  "Send the region between START and END to Amp with a prompt."
  (interactive "r")
  (let ((text (buffer-substring-no-properties start end))
        (prompt (read-string "Prompt for Amp: ")))
    (amp-server--broadcast-notification
     `((userSentMessage . ((message . ,(format "%s\n\n%s" prompt text))))))
    (message "Sent region to Amp")))

(provide 'amp-client)

;;; amp-client.el ends here
