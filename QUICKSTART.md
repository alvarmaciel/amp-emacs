# Quick Start Guide

Get up and running with amp-emacs in 5 minutes!

## Prerequisites

```bash
# Install Amp CLI
npm install -g @sourcegraph/amp

# Verify installation
amp --version
```

## Quick Install

### For Doom Emacs

1. **Add websocket and amp to packages.el:**
```elisp
;; ~/.config/doom/packages.el
(package! websocket)
(package! amp :recipe (:local-repo "local-packages/amp-emacs"))
```

2. **Clone amp-emacs:**
```bash
mkdir -p ~/.config/doom/local-packages
cd ~/.config/doom/local-packages
git clone https://github.com/yourusername/amp-emacs.git
```

3. **Configure in config.el:**
```elisp
;; ~/.config/doom/config.el
(use-package! amp
  :after websocket
  :config
  (setq amp-auto-start t)
  (setq amp-server-log-level 'info))
```

4. **Sync and restart:**
```bash
doom sync
```

### For Regular Emacs

1. **Install websocket:**
```elisp
M-x package-install RET websocket RET
```

2. **Clone and load:**
```bash
git clone https://github.com/yourusername/amp-emacs.git ~/.emacs.d/lisp/amp-emacs
```

Add to init.el:
```elisp
(add-to-list 'load-path "~/.emacs.d/lisp/amp-emacs")
(require 'websocket)
(require 'amp)
(setq amp-auto-start t)
```

### Quick Test (No Installation)

```bash
cd /path/to/amp-emacs
emacs -Q --eval "(progn (require 'package) (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\")) (package-initialize) (unless (package-installed-p 'websocket) (package-refresh-contents) (package-install 'websocket)) (add-to-list 'load-path \"$(pwd)\") (load \"amp\") (amp-start))"
```

## Basic Usage

### 1. Start Amp Server
```
M-x amp-start
```

You'll see: `Amp server started on port 9000. Run 'amp --ide' in your project.`

### 2. Connect Amp CLI
```bash
cd /your/project
amp --ide
```

### 3. Enable Notifications
```
M-x amp-client-enable
```

### 4. Try It Out!

**Send a message:**
```
M-x amp-send-message RET hello from emacs! RET
```

**Ask Amp about your code:**
Open a file and in the Amp CLI type:
```
what file am I looking at?
```

**Fix code:**
1. Select some code
2. Press `C-c a f` (or `M-x amp-fix-region`)

## Useful Commands

| Command | Keybinding | Description |
|---------|------------|-------------|
| `amp-start` | `C-c a s` | Start Amp server |
| `amp-stop` | `C-c a q` | Stop Amp server |
| `amp-status` | `C-c a ?` | Show connection status |
| `amp-send-message` | `C-c a m` | Send message to Amp |
| `amp-fix-region` | `C-c a f` | Fix selected code |
| `amp-explain-region` | `C-c a e` | Explain selected code |
| `amp-improve-region` | `C-c a i` | Improve selected code |
| `amp-client-enable` | - | Enable file/selection tracking |

## Troubleshooting

### Nothing happens?

1. **Check if server is running:**
   ```
   M-x amp-status
   ```
   Should show: `Amp server running on port XXXX`

2. **Check if client is enabled:**
   ```elisp
   M-: amp-client--enabled RET
   ```
   Should show: `t`. If `nil`, run:
   ```
   M-x amp-client-enable
   ```

3. **Enable debug logging:**
   ```elisp
   M-: (setq amp-server-log-level 'debug) RET
   M-x view-echo-area-messages
   ```

### Amp CLI won't connect?

1. **Verify lockfile exists:**
   ```bash
   cat ~/.local/share/amp/ide/*.json
   ```

2. **Check the port matches:**
   The lockfile shows the port. Make sure `amp --ide` is running in the same directory as your Emacs project.

3. **Restart both sides:**
   ```
   M-x amp-stop
   M-x amp-start
   ```
   Then restart `amp --ide`

### websocket package not found?

Install from MELPA:
```elisp
M-x package-install RET websocket RET
```

Or via command line:
```bash
emacs --batch --eval "(progn (require 'package) (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\")) (package-initialize) (package-refresh-contents) (package-install 'websocket))"
```

## What's Working?

✅ **Messages** - Send messages to Amp  
✅ **File tracking** - Amp knows what file you're viewing  
✅ **Selection tracking** - Amp sees what code you select  
✅ **File reading** - Amp can read files from your workspace  
✅ **File editing** - Amp can edit files directly in your buffers  
✅ **Region commands** - Fix, explain, improve code  

## Example Workflow

1. Start Emacs with amp-emacs configured
2. `M-x amp-start`
3. In terminal: `amp --ide`
4. `M-x amp-client-enable`
5. Open a file with a bug
6. Select the buggy code
7. `C-c a f` (fix region)
8. Watch Amp fix it in the CLI
9. Amp edits the file directly in Emacs!

## What's Next?

- Read [README.md](README.md) for full documentation
- Check [INSTALL.org](INSTALL.org) for detailed installation
- See [TODO.org](TODO.org) for development roadmap

## Getting Help

- **Issues:** Create an issue on GitHub
- **Amp docs:** https://ampcode.com/manual
- **Emacs help:** `C-h i m elisp RET`

---

**Built with ❤️ for the Emacs community**
