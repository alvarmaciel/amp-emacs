# amp-emacs

Deep integration of Sourcegraph Amp with Emacs, inspired by amp.nvim.

## Status: ✅ Working and Tested

**amp-emacs is fully functional!** All core features have been implemented and tested with Amp CLI v0.0.1763121689.

This implementation uses WebSocket communication (matching amp.nvim) and follows the IDE integration protocol spec.

## Features

- ✅ **Bidirectional communication** with `amp --ide` via WebSocket
- ✅ **Port-based connection** with authentication token (auto-finds port 9000-9999)
- ✅ **File tracking** - Amp knows what files you're viewing
- ✅ **Selection notifications** - Amp sees selected code
- ✅ **User messages** - Send messages directly to Amp
- ✅ **File reading** - Amp can read files from your workspace
- ✅ **File editing** - Amp can edit files directly in your Emacs buffers
- ✅ **Region commands** - Fix, explain, and improve code selections
- ⚠️ **Diagnostics** - Basic support (returns empty, needs flycheck/flymake integration)

## Quick Start

### Prerequisites

```bash
# Install Amp CLI
npm install -g @sourcegraph/amp

# Verify
amp --version
```

### Installation

#### Doom Emacs

1. **Add to `~/.config/doom/packages.el`:**

```elisp
(package! websocket)
(package! amp :recipe (:local-repo "local-packages/amp-emacs"))
```

2. **Clone to local-packages:**

```bash
mkdir -p ~/.config/doom/local-packages
cd ~/.config/doom/local-packages
git clone https://github.com/yourusername/amp-emacs.git
```

3. **Configure in `~/.config/doom/config.el`:**

```elisp
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

#### Regular Emacs

1. **Install websocket package:**

```elisp
M-x package-install RET websocket RET
```

2. **Clone and configure:**

```bash
git clone https://github.com/yourusername/amp-emacs.git ~/.emacs.d/lisp/amp-emacs
```

Add to your `init.el`:

```elisp
(add-to-list 'load-path "~/.emacs.d/lisp/amp-emacs")
(require 'websocket)
(require 'amp)
(setq amp-auto-start t)
```

3. **Restart Emacs**

### Quick Test (No Installation)

```bash
cd amp-emacs
emacs -Q --eval "(progn (require 'package) (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\")) (package-initialize) (unless (package-installed-p 'websocket) (package-refresh-contents) (package-install 'websocket)) (add-to-list 'load-path \"$(pwd)\") (load \"amp\") (amp-start))"
```

## Usage

### Basic Workflow

1. **Start Amp server in Emacs:**
   ```
   M-x amp-start
   ```
   
   You'll see: `Amp server started on port 9000. Run 'amp --ide' in your project.`

2. **Connect Amp CLI:**
   ```bash
   cd /your/project
   amp --ide
   ```

3. **Enable notifications (if not auto-enabled):**
   ```
   M-x amp-client-enable
   ```

4. **Start using Amp:**
   - Open files - Amp knows what you're viewing
   - Select code and ask Amp about it
   - Send messages: `M-x amp-send-message`
   - Fix code: Select region, then `C-c a f`

### Commands

| Command | Keybinding | Description |
|---------|------------|-------------|
| `amp-start` | `C-c a s` | Start Amp server |
| `amp-stop` | `C-c a q` | Stop Amp server |
| `amp-status` | `C-c a ?` | Show connection status |
| `amp-send-message` | `C-c a m` | Send message to Amp |
| `amp-fix-region` | `C-c a f` | Fix selected code |
| `amp-improve-region` | `C-c a i` | Improve selected code |
| `amp-explain-region` | `C-c a e` | Explain selected code |
| `amp-prompt-for-region` | `C-c a p` | Send region with custom prompt |
| `amp-client-enable` | - | Enable file/selection tracking |
| `amp-client-disable` | - | Disable notifications |

### Example Workflow

```elisp
;; 1. Start the server
M-x amp-start

;; 2. In terminal: amp --ide

;; 3. Enable notifications
M-x amp-client-enable

;; 4. Send a message
M-x amp-send-message RET hello from emacs! RET

;; 5. Ask Amp about current file
;; In Amp CLI: "what file am I looking at?"

;; 6. Fix some code
;; Select code, then: C-c a f

;; 7. Watch Amp edit the file directly!
```

## Configuration

### Basic Configuration

```elisp
;; Auto-start Amp server when Emacs starts
(setq amp-auto-start t)

;; Log level: 'debug, 'info, 'warn, or 'error
(setq amp-server-log-level 'info)

;; Throttle notifications (seconds)
(setq amp-client-throttle-interval 0.1)

;; Custom data directory (optional)
;; (setq amp-server-data-home "~/.config/amp")
```

### Recommended Configuration (use-package)

```elisp
(use-package websocket :ensure t)

(use-package amp
  :load-path "~/path/to/amp-emacs"
  :after websocket
  :config
  (setq amp-auto-start t)
  (setq amp-server-log-level 'info)
  (setq amp-client-throttle-interval 0.1)
  :bind-keymap
  ("C-c a" . amp-mode-map))
```

### Doom Emacs Configuration

```elisp
;; In config.el
(use-package! amp
  :after websocket
  :config
  (setq amp-auto-start t)
  (setq amp-server-log-level 'info))
```

## Architecture

### Three Main Components

#### 1. amp-server.el (~12KB, ~390 lines)
- **WebSocket server** on TCP localhost
- **Port discovery** - automatically finds available port (9000-9999)
- **Authentication** - generates and validates auth tokens
- **Lockfile management** - creates JSON lockfile with port + token
- **Message protocol** - handles IDE protocol requests/responses
- **Request handlers**:
  - `ping` - health check
  - `authenticate` - token validation
  - `readFile` - read file contents
  - `editFile` - apply edits to buffers
  - `getDiagnostics` - return diagnostics

#### 2. amp-client.el (~6KB, ~185 lines)
- **Notifications** to Amp:
  - `visibleFilesDidChange` - file tracking
  - `selectionDidChange` - text selections
  - `userSentMessage` - direct messages
- **Event hooks** with throttling for performance
- **Client enable/disable** control

#### 3. amp.el (~5KB, ~184 lines)
- **User interface** and commands
- **Minor mode** (amp-mode) for easy enable/disable
- **Keybindings** (C-c a prefix)
- **Integration** with projectile/project.el

### Communication Flow

```
Emacs (amp-emacs)          Amp CLI
─────────────────          ────────
1. Start WebSocket server
2. Create lockfile ──────> Read lockfile
3. Wait for connection <── Connect via WebSocket
4. Authenticate <────────> Send auth token
5. Send notifications ───> Receive file/selection info
6. Receive requests <───── Send readFile/editFile
7. Send responses ──────> Process responses
```

## Protocol

Communication uses **WebSocket** with JSON messages in **IDE protocol format**.

### Lockfile (`~/.local/share/amp/ide/{port}.json`)

```json
{
  "port": 9000,
  "authToken": "abc123...",
  "pid": 12345,
  "workspaceFolders": ["/path/to/project"],
  "ideName": "emacs 29.1"
}
```

### Server Notifications (Emacs → Amp)

```json
{"serverNotification": {"visibleFilesDidChange": {"uris": ["file:///path/to/file"]}}}
{"serverNotification": {"userSentMessage": {"message": "Fix this code"}}}
```

### Client Requests (Amp → Emacs)

```json
{"clientRequest": {"id": "1", "ping": {"message": "hello"}}}
{"clientRequest": {"id": "2", "readFile": {"path": "/path/to/file.py"}}}
{"clientRequest": {"id": "3", "editFile": {"path": "/path/to/file.py", "fullContent": "..."}}}
```

### Server Responses (Emacs → Amp)

```json
{"serverResponse": {"id": "1", "ping": {"message": "hello"}}}
{"serverResponse": {"id": "2", "readFile": {"content": "file contents..."}}}
{"serverResponse": {"id": "3", "editFile": {"success": true, "message": "File updated"}}}
```

## Troubleshooting

### Server won't start

1. **Enable debug logging:**
   ```elisp
   M-: (setq amp-server-log-level 'debug)
   M-x amp-start
   M-x view-echo-area-messages
   ```

2. **Check for websocket package:**
   ```elisp
   M-x package-install RET websocket RET
   ```

### Amp CLI doesn't connect

1. **Check server status:**
   ```
   M-x amp-status
   ```
   Should show: `Amp server running on port XXXX (project: /path, 0 clients)`

2. **Verify lockfile:**
   ```bash
   cat ~/.local/share/amp/ide/*.json
   ```
   Should show port, authToken, and other fields.

3. **Check you're in the right directory:**
   The Amp CLI needs to run in a directory under your project workspace.

4. **Restart both sides:**
   ```elisp
   M-x amp-stop
   M-x amp-start
   ```
   Then restart `amp --ide`

### Messages not appearing in Amp CLI

1. **Check client is enabled:**
   ```elisp
   M-: amp-client--enabled RET
   ```
   Should return `t`. If `nil`:
   ```
   M-x amp-client-enable
   ```

2. **Test with a simple message:**
   ```
   M-x amp-send-message RET test RET
   ```
   Check debug messages:
   ```
   M-x view-echo-area-messages
   ```

3. **Verify connection:**
   ```
   M-x amp-status
   ```
   Should show "1 clients" if Amp CLI is connected.

### Port conflicts

The server automatically finds an available port (9000-9999). If all ports are in use, you'll see an error. Check what's using those ports:

```bash
netstat -tuln | grep '900[0-9]'
```

### Performance issues

Reduce notification frequency:

```elisp
(setq amp-client-throttle-interval 0.5)  ; Default is 0.1
```

## Development

### Project Structure

```
amp-emacs/
├── amp-server.el       # WebSocket server and protocol
├── amp-client.el       # Editor state notifications
├── amp.el              # User interface
├── install-deps.el     # Dependency installer
├── README.md           # This file
├── INSTALL.org         # Detailed installation guide
├── QUICKSTART.md       # Quick start guide
├── TODO.org            # Development roadmap
└── SUMMARY.org         # Project summary
```

### Running Tests

Currently manual testing only. Start development environment:

```bash
cd amp-emacs
emacs -Q --eval "(progn ...install websocket... (load \"amp\") (setq amp-server-log-level 'debug) (amp-start))"
```

### Contributing

Contributions welcome! Areas of interest:

1. **Diagnostics integration** - Connect flycheck/flymake
2. **Tests** - Automated test suite
3. **Performance** - Optimize notification frequency
4. **Documentation** - Improve guides and examples
5. **Features** - Mode line indicator, better UX

See [TODO.org](TODO.org) for full roadmap.

## Comparison with amp.nvim

| Feature | amp.nvim | amp-emacs | Status |
|---------|----------|-----------|--------|
| WebSocket server | ✓ | ✓ | ✅ Complete |
| Port + auth token | ✓ | ✓ | ✅ Complete |
| File tracking | ✓ | ✓ | ✅ Complete |
| Selection tracking | ✓ | ✓ | ✅ Complete |
| User messages | ✓ | ✓ | ✅ Complete |
| Read files | ✓ | ✓ | ✅ Complete |
| Edit files | ✓ | ✓ | ✅ Complete |
| Diagnostics | ✓ | Partial | ⚠️ Returns empty |
| Multi-project | ✓ | Untested | ⚠️ Needs testing |
| Official support | ✓ | ✗ | Community |

## What's Working

✅ **Core functionality:**
- Amp CLI connects to Emacs via WebSocket
- Messages sent from Emacs appear in Amp CLI
- Amp knows what file you're viewing
- Amp can read any file in your workspace
- Amp can edit files directly in your buffers
- All user commands work as expected

✅ **Tested with:**
- Amp CLI v0.0.1763121689 (2025-11-14)
- Emacs 28.1+
- Doom Emacs
- Regular Emacs with use-package

## Known Limitations

- **Selection display**: Amp uses selection notifications silently (doesn't display them in UI)
- **Diagnostics**: Returns empty array (needs flycheck/flymake integration)
- **Multi-project**: Untested with multiple simultaneous projects

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Get started in 5 minutes
- **[INSTALL.org](INSTALL.org)** - Detailed installation guide
- **[EXAMPLE-WORKFLOW.md](EXAMPLE-WORKFLOW.md)** - Real-world usage example with a debugging story
- **[TODO.org](TODO.org)** - Development roadmap
- **[SUMMARY.org](SUMMARY.org)** - Complete project summary

## Resources

- **amp.nvim**: https://github.com/sourcegraph/amp.nvim
- **Amp Manual**: https://ampcode.com/manual
- **Amp CLI**: `npm install -g @sourcegraph/amp`
- **WebSocket Package**: https://github.com/ahyatt/emacs-websocket

## License

MIT License (or GPL-3.0+ to match Emacs conventions)

See [LICENSE](LICENSE) file for details.

## Credits

**Built by:** Alvar ([@yourusername](https://github.com/yourusername)) and Claude (Anthropic)

### Collaboration Disclaimer

This project was developed through a collaborative partnership between Alvar and Claude (an AI assistant by Anthropic). The implementation, architecture decisions, debugging, and documentation were created through an iterative conversation, combining:

- **Alvar's vision**: Deep Emacs integration for Amp, matching the functionality of amp.nvim
- **Alvar's expertise**: Emacs/Doom configuration, workflow requirements, and testing
- **Claude's contribution**: Code implementation, protocol research, debugging assistance, and documentation writing
- **Joint effort**: Architecture design, problem-solving, and iterative refinement

The entire development process, from initial concept to working implementation, happened in a single extended conversation where both participants contributed to the design and implementation decisions.

### Inspiration & Thanks

**Inspired by:** [amp.nvim](https://github.com/sourcegraph/amp.nvim) by Sourcegraph

**Special thanks to:**
- Sourcegraph team for creating Amp
- amp.nvim contributors for the reference implementation  
- Emacs community for excellent tools and libraries
- The WebSocket package maintainers

---

**Status: Production-ready! 🎉**

Questions? Issues? Contributions? Open an issue on GitHub!
