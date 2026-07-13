#!/usr/bin/env bash
set -euo pipefail

# ====================================================
# Configuration — every pinned version / tunable lives
# here. Edit this block to bump toolchain versions or
# change defaults; nothing else in the script should
# need touching for routine updates.
# ====================================================

# Toolchain versions
NODE_MAJOR="24"          # Active LTS, installed via NodeSource
DOTNET_CHANNEL="10.0"    # LTS channel, installed via dotnet-install.sh
BUN_VERSION="latest"     # "latest" or e.g. "1.2.4" to pin
RUST_TOOLCHAIN="stable"  # installed via rustup
PYTHON_VERSION="3.13"    # installed & pinned via uv

# Paths
BOOTSTRAP_FLAG="$HOME/.wsl_bootstrap_done"
WORKSPACE_DIR="$HOME/dev"

# System tuning
INOTIFY_MAX_WATCHES="524288"

# Flags (defaults — overridden by CLI args below)
WITH_CHROME=0

# --------------------------------------------------
# Flags
# --------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --with-chrome) WITH_CHROME=1 ;;
    *) echo "[WSL] Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

echo "[WSL] Bootstrap starting"

FIRST_RUN=1
if [[ -f "$BOOTSTRAP_FLAG" ]]; then
  echo "[WSL] Already bootstrapped — continuing update"
  FIRST_RUN=0
fi

ensure_line() {
  local line="$1"
  local file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

ensure_line_sudo() {
  local line="$1"
  local file="$2"
  sudo grep -qxF "$line" "$file" 2>/dev/null || echo "$line" | sudo tee -a "$file" >/dev/null
}

ensure_wsl_conf_setting() {
  local section="$1"   # e.g. boot
  local key="$2"        # e.g. systemd
  local value="$3"      # e.g. true
  local file="/etc/wsl.conf"

  sudo touch "$file"

  if sudo awk -v want="[$section]" -v k="$key" -v v="$value" '
    BEGIN { in_sec=0; found=0 }
    {
      line=$0
      stripped=line
      gsub(/[[:space:]]+/, "", stripped)
      if (stripped ~ /^\[[^]]+\]$/) {
        in_sec = (tolower(stripped) == tolower(want)) ? 1 : 0
        next
      }
      if (in_sec) {
        split(stripped, kv, "=")
        if (tolower(kv[1]) == tolower(k) && tolower(kv[2]) == tolower(v)) { found=1; exit }
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file" 2>/dev/null; then
    return
  fi

  local tmp
  tmp="$(mktemp)"
  sudo awk -v want="[$section]" -v k="$key" -v v="$value" -v newline="$key=$value" '
    BEGIN { in_sec=0; in_target=0; added=0; saw_target=0 }
    {
      line=$0
      stripped=line
      gsub(/[[:space:]]+/, "", stripped)
    }
    stripped ~ /^\[[^]]+\]$/ {
      if (in_target && !added) { print newline; added=1 }
      in_target = (tolower(stripped) == tolower(want)) ? 1 : 0
      if (in_target) saw_target=1
      print
      next
    }
    in_target {
      split(stripped, kv, "=")
      if (tolower(kv[1]) == tolower(k)) { print newline; added=1; next }
      print
      next
    }
    { print }
    END {
      if (in_target && !added) { print newline; added=1 }
      if (!saw_target) { print want; print newline; added=1 }
    }
  ' "$file" > "$tmp"
  sudo mv "$tmp" "$file"
}

# --------------------------------------------------
# Distro check (Ubuntu / Debian)
# --------------------------------------------------
. /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
  echo "[WSL] Unsupported distro: $ID"
  exit 1
fi

# --------------------------------------------------
# Sudo readiness
# --------------------------------------------------
sudo -v

# --------------------------------------------------
# Base packages
# --------------------------------------------------
sudo apt update
sudo apt install -y \
  build-essential \
  curl wget git ca-certificates gnupg \
  unzip zip jq \
  ripgrep fd-find bat fzf \
  htop tmux tree neovim \
  locales \
  libicu-dev libssl-dev  # required by the .NET SDK (globalization + TLS) — dotnet-install.sh doesn't pull these in itself

# --------------------------------------------------
# Headless Chrome (opt-in via --with-chrome)
# --------------------------------------------------
if [[ "$WITH_CHROME" -eq 1 ]]; then
  if ! command -v google-chrome >/dev/null; then
    echo "[WSL] Installing headless Chrome"

    sudo apt install -y \
      xvfb libxi6 fonts-liberation libnss3 libxss1 libatk-bridge2.0-0 \
      libdrm2 libxkbcommon0 libxcomposite1 libxrandr2 libgbm1 \
      libasound2 libgtk-3-0

    sudo rm -f /etc/apt/sources.list.d/google-chrome*
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | \
      sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg

    sudo tee /etc/apt/sources.list.d/google-chrome.sources >/dev/null <<'EOF'
Types: deb
URIs: https://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg
EOF

    sudo apt update
    sudo apt install -y google-chrome-stable
  fi
else
  echo "[WSL] Skipping Chrome (pass --with-chrome to install it)"
fi

# --------------------------------------------------
# Locale
# --------------------------------------------------
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8

# --------------------------------------------------
# Recommended WSL configuration (/etc/wsl.conf)
# --------------------------------------------------
echo "[WSL] Applying recommended /etc/wsl.conf settings"

# Enable systemd so services (docker, ssh-agent, etc.) work normally
ensure_wsl_conf_setting "boot" "systemd" "true"

# Don't append Windows PATH into Linux PATH — keeps `which`/PATH lookups
# fast and avoids Linux tools accidentally resolving to .exe shims
ensure_wsl_conf_setting "interop" "appendWindowsPath" "false"

# Keep Windows interop (running .exe from WSL) available; only the
# PATH injection above is disabled
ensure_wsl_conf_setting "interop" "enabled" "true"

# Use Linux-native file permission metadata on the WSL filesystem
ensure_wsl_conf_setting "automount" "options" "metadata"

# --------------------------------------------------
# Node.js — NodeSource's official setup script (Active LTS)
# --------------------------------------------------
if ! command -v node >/dev/null || [[ "$(node -v)" != v"$NODE_MAJOR".* ]]; then
  echo "[WSL] Installing Node.js $NODE_MAJOR via NodeSource"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
  sudo apt install -y nodejs
else
  echo "[WSL] Node.js $NODE_MAJOR already installed: $(node -v)"
fi

# --------------------------------------------------
# Bun — official install script
# --------------------------------------------------
if ! command -v bun >/dev/null; then
  echo "[WSL] Installing Bun"
  if [[ "$BUN_VERSION" == "latest" ]]; then
    curl -fsSL https://bun.sh/install | bash
  else
    curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
  fi
else
  echo "[WSL] Bun already installed: $(bun --version)"
fi

ensure_line 'export PATH="$HOME/.bun/bin:$PATH"' "$HOME/.bashrc"
export PATH="$HOME/.bun/bin:$PATH"

# --------------------------------------------------
# .NET SDK — Microsoft's official dotnet-install script
# --------------------------------------------------
if ! command -v dotnet >/dev/null || ! dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_CHANNEL}"; then
  echo "[WSL] Installing .NET SDK ($DOTNET_CHANNEL channel)"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh
  /tmp/dotnet-install.sh --channel "$DOTNET_CHANNEL" --install-dir "$HOME/.dotnet"
  rm -f /tmp/dotnet-install.sh
else
  echo "[WSL] .NET SDK $DOTNET_CHANNEL already installed"
fi

ensure_line 'export DOTNET_ROOT="$HOME/.dotnet"' "$HOME/.bashrc"
ensure_line 'export PATH="$HOME/.dotnet:$PATH"' "$HOME/.bashrc"
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$HOME/.dotnet:$PATH"

# --------------------------------------------------
# Rust — rustup, the official installer (rust-lang.org/tools/install)
# --------------------------------------------------
if ! command -v rustc >/dev/null; then
  echo "[WSL] Installing Rust via rustup"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "$RUST_TOOLCHAIN"
else
  echo "[WSL] Rust already installed: $(rustc --version)"
fi

ensure_line '. "$HOME/.cargo/env"' "$HOME/.bashrc"
# shellcheck disable=SC1091
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# --------------------------------------------------
# Python — uv, the official Astral installer, as version manager
# (installs & pins a Python version, replaces pipx for global tools)
# --------------------------------------------------
if ! command -v uv >/dev/null; then
  echo "[WSL] Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  echo "[WSL] uv already installed: $(uv --version)"
fi

ensure_line 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"
export PATH="$HOME/.local/bin:$PATH"

if command -v uv >/dev/null; then
  if ! uv python list --only-installed 2>/dev/null | grep -q "^cpython-${PYTHON_VERSION}"; then
    echo "[WSL] Installing Python $PYTHON_VERSION via uv"
    uv python install "$PYTHON_VERSION"
  else
    echo "[WSL] Python $PYTHON_VERSION already installed via uv"
  fi
  uv python pin "$PYTHON_VERSION" --global 2>/dev/null || true
fi

# --------------------------------------------------
# Git defaults
# --------------------------------------------------
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor nvim

# --------------------------------------------------
# tmux defaults
# --------------------------------------------------
ensure_line "set -g mouse on" "$HOME/.tmux.conf"
ensure_line "setw -g mode-keys vi" "$HOME/.tmux.conf"
ensure_line "set -g history-limit 10000" "$HOME/.tmux.conf"

# --------------------------------------------------
# Quality-of-life tweaks
# --------------------------------------------------
ensure_line "alias cat=batcat" "$HOME/.bashrc"
ensure_line "alias find=fdfind" "$HOME/.bashrc"
ensure_line "alias ccusage-codex='bunx @ccusage/codex@latest'" "$HOME/.bashrc"
ensure_line "alias ollama-host=\"ip route | awk '/default/ {print \\\$3}'\"" "$HOME/.bashrc"

ensure_line_sudo "fs.inotify.max_user_watches=${INOTIFY_MAX_WATCHES}" "/etc/sysctl.d/99-wsl.conf"
sudo sysctl --system >/dev/null

# --------------------------------------------------
# Workspace
# --------------------------------------------------
mkdir -p "$WORKSPACE_DIR"

# --------------------------------------------------
# Self-check (non-fatal)
# --------------------------------------------------
echo "[WSL] Self-check"
set +e
if command -v node >/dev/null; then
  echo "[WSL] node: $(node --version 2>/dev/null)"
else
  echo "[WSL] node: missing"
fi
if command -v bun >/dev/null; then
  echo "[WSL] bun: $(bun --version 2>/dev/null)"
else
  echo "[WSL] bun: missing"
fi
if command -v dotnet >/dev/null; then
  echo "[WSL] dotnet: $(dotnet --version 2>/dev/null)"
else
  echo "[WSL] dotnet: missing"
fi
if command -v rustc >/dev/null; then
  echo "[WSL] rust: $(rustc --version 2>/dev/null)"
else
  echo "[WSL] rust: missing"
fi
if command -v cargo >/dev/null; then
  echo "[WSL] cargo: $(cargo --version 2>/dev/null)"
else
  echo "[WSL] cargo: missing"
fi
if command -v python3 >/dev/null; then
  echo "[WSL] python3: $(python3 --version 2>/dev/null)"
else
  echo "[WSL] python3: missing"
fi
if command -v uv >/dev/null; then
  echo "[WSL] uv: $(uv --version 2>/dev/null)"
else
  echo "[WSL] uv: missing"
fi
if command -v git >/dev/null; then
  echo "[WSL] git: $(git --version 2>/dev/null)"
else
  echo "[WSL] git: missing"
fi
if command -v nvim >/dev/null; then
  echo "[WSL] nvim: $(nvim --version 2>/dev/null | head -n 1)"
else
  echo "[WSL] nvim: missing"
fi
if [[ "$WITH_CHROME" -eq 1 ]]; then
  if command -v google-chrome >/dev/null; then
    echo "[WSL] chrome: $(google-chrome --version 2>/dev/null)"
  else
    echo "[WSL] chrome: missing"
  fi
fi
set -euo pipefail

# --------------------------------------------------
# Mark completion
# --------------------------------------------------
touch "$BOOTSTRAP_FLAG"

echo "[WSL] Bootstrap complete"
if [[ "$FIRST_RUN" -eq 1 ]]; then
  echo "[WSL] Run: wsl --shutdown (from Windows) and reopen the distro"
fi

cat <<'EOF'

--------------------------------------------------
[TIP] Reaching Ollama running on the Windows host
--------------------------------------------------
If Ollama runs on Windows (not inside WSL), from here:

  1. On Windows, make Ollama listen on all interfaces, not just
     localhost. Set the env var (System Properties > Environment
     Variables, or PowerShell as admin) and restart Ollama:

       OLLAMA_HOST=0.0.0.0

  2. From WSL, reach it via the Windows host IP — NOT localhost,
     unless you've enabled mirrored networking (see option 3).
     The host IP is your default gateway inside WSL:

       ip route | awk '/default/ {print $3}'

     e.g.  curl http://$(ip route | awk '/default/ {print $3}'):11434

  3. (Cleaner, Windows 11 22H2+) Enable mirrored networking so
     localhost is shared between Windows and WSL. Add to
     %USERPROFILE%\.wslconfig on the Windows side:

       [wsl2]
       networkingMode=mirrored

     Then `wsl --shutdown` and reopen — after that,
     http://localhost:11434 works directly from WSL, no gateway
     lookup needed.

Optional convenience alias 'ollama-host' has been added to your
.bashrc — run `source ~/.bashrc`, then:

  curl http://$(ollama-host):11434

--------------------------------------------------
EOF
