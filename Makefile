.PHONY: help dev test clean install check lint

# Default target
help:
	@echo "amp-emacs - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make dev      - Start development environment"
	@echo "  make test     - Run manual tests"
	@echo "  make check    - Check Emacs Lisp syntax"
	@echo "  make lint     - Lint Emacs Lisp code"
	@echo "  make clean    - Clean up generated files"
	@echo "  make install  - Show installation instructions"
	@echo "  make docs     - Generate documentation"

# Start development environment
dev:
	@echo "Starting development environment..."
	emacs -Q -l init-dev.el

# Run manual tests
test:
	@echo "Starting test environment..."
	@echo "Use M-x test-protocol-menu to run tests"
	emacs -Q -l init-dev.el -f test-protocol-menu

# Check syntax
check:
	@echo "Checking Emacs Lisp syntax..."
	@emacs --batch \
		--eval "(setq byte-compile-error-on-warn t)" \
		--eval "(add-to-list 'load-path \".\")" \
		-f batch-byte-compile \
		amp-server.el amp-client.el amp.el test-protocol.el 2>&1 | grep -v "^Wrote"
	@rm -f *.elc
	@echo "✓ Syntax check complete"

# Lint code
lint:
	@echo "Linting Emacs Lisp code..."
	@if command -v package-lint-batch-and-exit >/dev/null 2>&1; then \
		emacs --batch \
			--eval "(add-to-list 'load-path \".\")" \
			-f package-lint-batch-and-exit \
			amp-server.el amp-client.el amp.el; \
	else \
		echo "package-lint not found. Install it with:"; \
		echo "  M-x package-install RET package-lint"; \
	fi

# Clean up
clean:
	@echo "Cleaning up..."
	@rm -f *.elc
	@rm -rf ~/.local/share/amp/ide/emacs-*.lock
	@rm -rf ~/.local/share/amp/ide/emacs-*.sock
	@echo "✓ Cleanup complete"

# Installation instructions
install:
	@echo "Installation Instructions:"
	@echo ""
	@echo "For Doom Emacs:"
	@echo "  1. Copy this directory to ~/.config/doom/local-packages/amp-emacs"
	@echo "  2. Add to packages.el:"
	@echo "     (package! amp :recipe (:local-repo \"local-packages/amp-emacs\"))"
	@echo "  3. Add to config.el (see INSTALL.org)"
	@echo "  4. Run: doom sync"
	@echo ""
	@echo "For use-package:"
	@echo "  1. Copy this directory to ~/.emacs.d/lisp/amp-emacs"
	@echo "  2. Add to init.el:"
	@echo "     (use-package amp"
	@echo "       :load-path \"~/.emacs.d/lisp/amp-emacs\")"
	@echo ""
	@echo "For more details, see INSTALL.org"

# Generate documentation
docs:
	@echo "Generating documentation..."
	@echo "Documentation is available in:"
	@echo "  - README.md      : User documentation"
	@echo "  - INSTALL.org    : Installation guide"
	@echo "  - TODO.org       : Development roadmap"
	@echo "  - SUMMARY.org    : Project summary"

# Package for distribution
package:
	@echo "Creating distribution package..."
	@mkdir -p dist
	@tar czf dist/amp-emacs-$$(date +%Y%m%d).tar.gz \
		--exclude=dist \
		--exclude=.git \
		--exclude='*.elc' \
		--transform 's,^,amp-emacs/,' \
		*
	@echo "✓ Package created: dist/amp-emacs-$$(date +%Y%m%d).tar.gz"

# Watch for changes (requires entr)
watch:
	@if command -v entr >/dev/null 2>&1; then \
		echo "Watching for changes... (Ctrl-C to stop)"; \
		find . -name '*.el' | entr -c make check; \
	else \
		echo "entr not found. Install it with your package manager."; \
		echo "Example: brew install entr"; \
		exit 1; \
	fi

# Quick start
quickstart: clean
	@echo "=== Quick Start ==="
	@echo ""
	@echo "1. Starting Emacs with amp-emacs..."
	@echo "   Command: emacs -Q -l init-dev.el"
	@echo ""
	@echo "2. In Emacs, run: M-x amp-start"
	@echo ""
	@echo "3. In a terminal, run: amp --ide"
	@echo ""
	@echo "Press Enter to start Emacs..."
	@read dummy && make dev

# Show project stats
stats:
	@echo "Project Statistics:"
	@echo ""
	@echo "Lines of code:"
	@wc -l *.el | tail -1
	@echo ""
	@echo "File sizes:"
	@du -h *.el *.org *.md | sort -h
	@echo ""
	@echo "Total size:"
	@du -sh . | cut -f1
