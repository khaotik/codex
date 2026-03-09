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

path_action="already"
path_profile=""

step() {
  printf '==> %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required but was not found on PATH.\n' "$1" >&2
    exit 1
  fi
}

add_to_path() {
  path_action="already"
  path_profile=""

  case ":$PATH:" in
  *":$INSTALL_BIN:"*)
    return
    ;;
  esac

  profile="$HOME/.profile"
  case "${SHELL:-}" in
  */zsh)
    profile="$HOME/.zshrc"
    ;;
  */bash)
    profile="$HOME/.bashrc"
    ;;
  esac

  path_profile="$profile"
  path_line="export PATH=\"$INSTALL_BIN:\$PATH\""
  if [ -f "$profile" ] && grep -F "$path_line" "$profile" >/dev/null 2>&1; then
    path_action="configured"
    return
  fi

  {
    printf '\n# Added by Codex local installer\n'
    printf '%s\n' "$path_line"
  } >>"$profile"
  path_action="added"
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
mkdir -p "$INSTALL_SHARED" "$INSTALL_BIN"

cp "$REPO_ROOT/codex-cli/bin/codex.js" "$INSTALL_SHARED/codex.js"
cp "$REPO_ROOT/codex-rs/target/release/codex" "$INSTALL_SHARED/codex"
chmod 0755 "$INSTALL_SHARED/codex.js" "$INSTALL_SHARED/codex"

# Relative symlink: bin/codex -> ../share/codex/codex.js
ln -sf "../share/codex/codex.js" "$INSTALL_BIN/codex"

# ---------------------------------------------------------------------------
# Write uninstall script
# ---------------------------------------------------------------------------
UNINSTALL_SCRIPT="$INSTALL_BIN/uninstall-codex"
cat >"$UNINSTALL_SCRIPT" <<UNINSTALL_EOF
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
printf 'Note: PATH entries added to shell profiles were not removed.\n'
UNINSTALL_EOF
chmod 0755 "$UNINSTALL_SCRIPT"

# ---------------------------------------------------------------------------
# PATH
# ---------------------------------------------------------------------------
add_to_path

case "$path_action" in
added)
  step "PATH updated for future shells in $path_profile"
  step "Run now: export PATH=\"$INSTALL_BIN:\$PATH\" && codex"
  step "Or open a new terminal and run: codex"
  ;;
configured)
  step "PATH is already configured for future shells in $path_profile"
  step "Run now: export PATH=\"$INSTALL_BIN:\$PATH\" && codex"
  step "Or open a new terminal and run: codex"
  ;;
*)
  step "$INSTALL_BIN is already on PATH"
  step "Run: codex"
  ;;
esac

printf 'Codex installed successfully from source.\n'
printf '  binary:    %s/codex\n' "$INSTALL_SHARED"
printf '  wrapper:   %s/codex.js\n' "$INSTALL_SHARED"
printf '  bin:       %s/codex -> ../share/codex/codex.js\n' "$INSTALL_BIN"
printf '  uninstall: %s/uninstall-codex\n' "$INSTALL_BIN"
