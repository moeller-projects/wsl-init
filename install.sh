#!/usr/bin/env bash
set -euo pipefail

echo "[WSL] Bootstrap starting"

BOOTSTRAP_FLAG="$HOME/.wsl_bootstrap_done"
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

ensure_wsl_systemd() {
  local file="/etc/wsl.conf"

  if sudo awk '
    BEGIN { found=0 }
    {
      line=$0
      gsub(/[[:space:]]+/, "", line)
      if (tolower(line) == "systemd=true") { found=1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "$file" 2>/dev/null; then
    return
  fi

  if sudo awk '
    BEGIN { found=0 }
    {
      line=$0
      gsub(/[[:space:]]+/, "", line)
      if (tolower(line) == "[boot]") { found=1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "$file" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    sudo awk '
      BEGIN { in_boot=0; added=0 }
      {
        line=$0
        stripped=line
        gsub(/[[:space:]]+/, "", stripped)
      }
      tolower(stripped) == "[boot]" { print; in_boot=1; next }
      tolower(stripped) ~ /^\[[^]]+\]$/ {
        if (in_boot && !added) { print "systemd=true"; added=1 }
        in_boot=0
        print
        next
      }
      { print }
      END { if (in_boot && !added) { print "systemd=true" } }
    ' "$file" > "$tmp"
    sudo mv "$tmp" "$file"
  else
    printf "[boot]\nsystemd=true\n" | sudo tee -a "$file" >/dev/null
  fi
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
  curl wget git ca-certificates \
  unzip zip jq \
  ripgrep fd-find bat fzf \
  htop tmux tree neovim \
  zsh locales

# --------------------------------------------------
# Headless Chrome (Google Chrome Stable)
# --------------------------------------------------
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

# --------------------------------------------------
# Locale
# --------------------------------------------------
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8

# --------------------------------------------------
# Enable systemd in WSL
# --------------------------------------------------
ensure_wsl_systemd

# --------------------------------------------------
# Default shell → zsh
# --------------------------------------------------
if [[ "$SHELL" != "$(command -v zsh)" ]]; then
  sudo usermod -s "$(command -v zsh)" "$USER"
fi

# --------------------------------------------------
# Starship prompt
# --------------------------------------------------
if ! command -v starship >/dev/null; then
  curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

ensure_line 'eval "$(starship init zsh)"' "$HOME/.zshrc"

# --------------------------------------------------
# mise version manager
# --------------------------------------------------
if ! command -v mise >/dev/null; then
    sudo install -dm 755 /etc/apt/keyrings
    curl -fSs https://mise.jdx.dev/gpg-key.pub | sudo tee /etc/apt/keyrings/mise-archive-keyring.asc 1> /dev/null
    echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.asc] https://mise.jdx.dev/deb stable main" | sudo tee /etc/apt/sources.list.d/mise.list
    sudo apt update -y
    sudo apt install -y mise
fi

ensure_line 'eval "$(mise activate zsh)"' "$HOME/.zshrc"

# --------------------------------------------------
# Bun global bin path
# --------------------------------------------------
ensure_line 'export PATH="$HOME/.bun/bin:$PATH"' "$HOME/.zshrc"

# Load mise for current script
eval "$(mise activate bash)"

# --------------------------------------------------
# Toolchains (Node + Bun + .NET)
# --------------------------------------------------
echo "[WSL] Installing toolchains via mise"

NODE_VERSION="20.11.1"
BUN_VERSION="1.1.4"
DOTNET_VERSION="8.0.100"

mise use -g node@"$NODE_VERSION"
mise use -g bun@"$BUN_VERSION"
mise use -g dotnet@"$DOTNET_VERSION"

# --------------------------------------------------
# Bun-based global tooling
# --------------------------------------------------
echo "[WSL] Installing JS tooling via Bun"

if command -v bun >/dev/null; then
  bun add -g \
    typescript \
    eslint \
    prettier \
    pnpm \
    nx \
    @biomejs/biome \
    opencode-ai \
    @openai/codex \
    @fission-ai/openspec
else
  echo "[WSL] Bun not found; skipping global JS tooling install"
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
ensure_line "alias cat=batcat" "$HOME/.zshrc"
ensure_line "alias find=fdfind" "$HOME/.zshrc"

ensure_line_sudo "fs.inotify.max_user_watches=524288" "/etc/sysctl.d/99-wsl.conf"
sudo sysctl --system >/dev/null

# --------------------------------------------------
# Workspace
# --------------------------------------------------
mkdir -p "$HOME/dev"

# --------------------------------------------------
# Self-check (non-fatal)
# --------------------------------------------------
echo "[WSL] Self-check"
set +e
if command -v mise >/dev/null; then
  echo "[WSL] mise: $(mise --version 2>/dev/null)"
else
  echo "[WSL] mise: missing"
fi
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
if command -v git >/dev/null; then
  echo "[WSL] git: $(git --version 2>/dev/null)"
else
  echo "[WSL] git: missing"
fi
if command -v zsh >/dev/null; then
  echo "[WSL] zsh: $(zsh --version 2>/dev/null)"
else
  echo "[WSL] zsh: missing"
fi
if command -v nvim >/dev/null; then
  echo "[WSL] nvim: $(nvim --version 2>/dev/null | head -n 1)"
else
  echo "[WSL] nvim: missing"
fi
if command -v google-chrome >/dev/null; then
  echo "[WSL] chrome: $(google-chrome --version 2>/dev/null)"
else
  echo "[WSL] chrome: missing"
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
