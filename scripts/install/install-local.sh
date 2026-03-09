#!/bin/sh
# install-local.sh — build Codex from source and install under INSTALL_PREFIX.
#
# Installed layout:
#   $INSTALL_PREFIX/bin/codex                      (symlink → ../share/codex/codex.js)
#   $INSTALL_PREFIX/share/codex/codex.js          (Node wrapper)
#   $INSTALL_PREFIX/share/codex/codex             (native binary)
#
# Usage:
#   bash scripts/install/install-local.sh
#
# Environment variables:
#   CODEX_INSTALL_PREFIX   Override installation prefix (default: $HOME/.local)

set -eu

INSTALL_PREFIX="${CODEX_INSTALL_PREFIX:-$HOME/.local}"
INSTALL_BIN="$INSTALL_PREFIX/bin"
INSTALL_SHARED="$INSTALL_PREFIX/share/codex"

# ---------------------------------------------------------------------------
# Determine whether to use sudo
# If INSTALL_PREFIX is owned by root and the current user is not root,
# prepend install commands with sudo.
# ---------------------------------------------------------------------------
SUDO=""
if [ "$(id -u)" != "0" ] && [ -e "$INSTALL_PREFIX" ]; then
  _owner=$(ls -ld "$INSTALL_PREFIX" | awk '{print $3}')
  if [ "$_owner" = "root" ]; then
    SUDO="sudo"
    printf 'info: %s is owned by root; install commands will use sudo.\n' "$INSTALL_PREFIX" >&2
  fi
fi

step() {
  printf '==> %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required but was not found on PATH.\n' "$1" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Resolve REPO_ROOT from the script's location (scripts/install/install-local.sh)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
require_command cargo
require_command node

# ---------------------------------------------------------------------------
# Warn (not fail) if rg is absent — grep_files falls back gracefully
# ---------------------------------------------------------------------------
if ! command -v rg >/dev/null 2>&1; then
  printf 'warning: ripgrep (rg) not found on PATH. The grep_files tool will not work.\n' >&2
  printf '         Install ripgrep: https://github.com/BurntSushi/ripgrep#installation\n' >&2
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
step "Building codex (cargo build --release -p codex-cli)"
(cd "$REPO_ROOT/codex-rs" && cargo build --release -p codex-cli)

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
step "Installing to $INSTALL_PREFIX"
$SUDO mkdir -p "$INSTALL_SHARED" "$INSTALL_BIN"

$SUDO cp "$REPO_ROOT/codex-cli/bin/codex.js" "$INSTALL_SHARED/codex.js"
$SUDO cp "$REPO_ROOT/codex-rs/target/release/codex" "$INSTALL_SHARED/codex"
$SUDO chmod 0755 "$INSTALL_SHARED/codex.js" "$INSTALL_SHARED/codex"

# Relative symlink: bin/codex -> ../share/codex/codex.js
$SUDO ln -sf "../share/codex/codex.js" "$INSTALL_BIN/codex"

# ---------------------------------------------------------------------------
# Write uninstall script
# ---------------------------------------------------------------------------
UNINSTALL_SCRIPT="$INSTALL_BIN/uninstall-codex"
$SUDO tee "$UNINSTALL_SCRIPT" >/dev/null <<UNINSTALL_EOF
#!/bin/sh
# uninstall-codex — remove files installed by install-local.sh
set -eu

INSTALL_BIN="$INSTALL_BIN"
INSTALL_SHARED="$INSTALL_SHARED"

printf 'Removing Codex files...\n'
rm -f "\$INSTALL_BIN/codex"
rm -f "\$INSTALL_BIN/uninstall-codex"
rm -f "\$INSTALL_SHARED/codex.js"
rm -f "\$INSTALL_SHARED/codex"
rmdir "\$INSTALL_SHARED" 2>/dev/null || true

printf 'Codex uninstalled.\n'
UNINSTALL_EOF
$SUDO chmod 0755 "$UNINSTALL_SCRIPT"

printf 'Codex installed successfully from source.\n'
printf '  binary:    %s/codex\n' "$INSTALL_SHARED"
printf '  wrapper:   %s/codex.js\n' "$INSTALL_SHARED"
printf '  bin:       %s/codex -> ../share/codex/codex.js\n' "$INSTALL_BIN"
printf '  uninstall: %s/uninstall-codex\n' "$INSTALL_BIN"

case ":$PATH:" in
*":$INSTALL_BIN:"*) ;;
*)
  printf 'warning: %s is not on PATH.\n' "$INSTALL_BIN" >&2
  printf '         Add it to your shell profile, e.g.:\n' >&2
  printf '           export PATH="%s:$PATH"\n' "$INSTALL_BIN" >&2
  ;;
esac
