;;; install-deps.el --- Install amp-emacs dependencies -*- lexical-binding: t; -*-

;;; Commentary:
;; Run this file to install required dependencies for amp-emacs

;;; Code:

;; Add MELPA repository
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Refresh package list
(message "Refreshing package archives...")
(package-refresh-contents)

;; Install websocket package
(message "Installing websocket package...")
(unless (package-installed-p 'websocket)
  (package-install 'websocket))

(message "Dependencies installed successfully!")
(message "You can now use: (require 'amp)")

;;; install-deps.el ends here
