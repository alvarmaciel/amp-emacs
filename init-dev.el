;;; init-dev.el --- Development initialization for amp-emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; Quick setup for development and testing of amp-emacs.
;; Load this file to get started quickly:
;;
;;   emacs -Q -l init-dev.el

;;; Code:

;; Add current directory to load path
(add-to-list 'load-path default-directory)

;; Load amp-emacs
(require 'amp-server)
(require 'amp-client)
(require 'amp)
(require 'test-protocol)

;; Configure for development
(setq amp-server-log-level 'debug)
(setq amp-auto-start nil) ; Don't auto-start in dev mode

;; Useful development bindings
(global-set-key (kbd "C-c d s") #'amp-server-start)
(global-set-key (kbd "C-c d q") #'amp-server-stop)
(global-set-key (kbd "C-c d c") #'amp-client-enable)
(global-set-key (kbd "C-c d t") #'test-protocol-menu)
(global-set-key (kbd "C-c d m") #'view-echo-area-messages)

;; Show welcome message
(with-current-buffer (get-buffer-create "*amp-dev*")
  (erase-buffer)
  (insert "╔══════════════════════════════════════════════════════════════╗\n")
  (insert "║              amp-emacs Development Environment              ║\n")
  (insert "╚══════════════════════════════════════════════════════════════╝\n")
  (insert "\n")
  (insert "Welcome to amp-emacs development mode!\n\n")
  (insert "Quick Start:\n")
  (insert "  1. C-c d s  → Start Amp server\n")
  (insert "  2. In terminal: cd /your/project && amp --ide\n")
  (insert "  3. C-c d c  → Enable client notifications\n")
  (insert "  4. Edit files and watch the magic happen!\n")
  (insert "\n")
  (insert "Development Commands:\n")
  (insert "  C-c d s  → amp-server-start\n")
  (insert "  C-c d q  → amp-server-stop\n")
  (insert "  C-c d c  → amp-client-enable\n")
  (insert "  C-c d t  → test-protocol-menu (testing tools)\n")
  (insert "  C-c d m  → view-echo-area-messages (see logs)\n")
  (insert "\n")
  (insert "Standard Amp Commands:\n")
  (insert "  C-c a s  → amp-start (start everything)\n")
  (insert "  C-c a q  → amp-stop\n")
  (insert "  C-c a m  → amp-send-message\n")
  (insert "  C-c a f  → amp-fix-region\n")
  (insert "  C-c a e  → amp-explain-region\n")
  (insert "\n")
  (insert "Configuration:\n")
  (insert "  - Log level: debug\n")
  (insert "  - Auto-start: disabled (manual control for testing)\n")
  (insert "  - Data home: " amp-server-data-home "\n")
  (insert "\n")
  (insert "Testing:\n")
  (insert "  1. Test without Amp CLI:\n")
  (insert "     - M-x test-protocol-menu\n")
  (insert "     - Choose scenario to run\n")
  (insert "\n")
  (insert "  2. Test with Amp CLI:\n")
  (insert "     - Start server: C-c d s\n")
  (insert "     - In terminal: amp --ide\n")
  (insert "     - Watch messages: C-c d m\n")
  (insert "\n")
  (insert "Files:\n")
  (insert "  - amp-server.el  → Socket server & protocol\n")
  (insert "  - amp-client.el  → Editor notifications\n")
  (insert "  - amp.el         → User interface\n")
  (insert "  - test-protocol.el → Testing utilities\n")
  (insert "\n")
  (insert "Debugging:\n")
  (insert "  - All messages logged to *Messages* buffer\n")
  (insert "  - Use (setq amp-server-log-level 'debug) for verbose logging\n")
  (insert "  - Lockfile: ~/.local/share/amp/ide/emacs-XXXXX.lock\n")
  (insert "  - Socket: ~/.local/share/amp/ide/emacs-XXXXX.sock\n")
  (insert "\n")
  (insert "Next Steps:\n")
  (insert "  1. Read README.md for usage instructions\n")
  (insert "  2. Check TODO.org for development roadmap\n")
  (insert "  3. Test the protocol with amp --ide\n")
  (insert "  4. Report any issues you find\n")
  (insert "\n")
  (insert "════════════════════════════════════════════════════════════════\n")
  (goto-char (point-min)))

(switch-to-buffer "*amp-dev*")

(message "amp-emacs development environment loaded. See *amp-dev* buffer for help.")

(provide 'init-dev)

;;; init-dev.el ends here
