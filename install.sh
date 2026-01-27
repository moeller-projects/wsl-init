#!/usr/bin/env bash
set -euo pipefail

echo "[WSL] Bootstrap starting"

BOOTSTRAP_FLAG="$HOME/.wsl_bootstrap_done"
if [[ -f "$BOOTSTRAP_FLAG" ]]; then
  echo "[WSL] Already bootstrapped — exiting"
  exit 0
fi

# --------------------------------------------------
# Distro check (Ubuntu / Debian)
# --------------------------------------------------
. /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
  echo "[WSL] Unsupported distro: $ID"
  exit 1
fi

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
# Locale
# --------------------------------------------------
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8

# --------------------------------------------------
# Enable systemd in WSL
# --------------------------------------------------
sudo tee /etc/wsl.conf >/dev/null <<EOF
[boot]
systemd=true
EOF

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

grep -q 'starship init zsh' "$HOME/.zshrc" 2>/dev/null || \
  echo 'eval "$(starship init zsh)"' >> "$HOME/.zshrc"

# --------------------------------------------------
# mise version manager
# --------------------------------------------------
if ! command -v mise >/dev/null; then
  curl https://mise.jdx.dev/install.sh | sh
fi

grep -q 'mise activate zsh' "$HOME/.zshrc" 2>/dev/null || cat <<'EOF' >> "$HOME/.zshrc"
eval "$(mise activate zsh)"
EOF

# Load mise for current script
eval "$(mise activate bash)"

# --------------------------------------------------
# Toolchains (Node + Bun + .NET)
# --------------------------------------------------
echo "[WSL] Installing toolchains via mise"

NODE_VERSION="20.11.1"
BUN_VERSION="1.1.4"
DOTNET_VERSION="8.0.100"

mise use -g node@"$NODE_VERSION" || true
mise use -g bun@"$BUN_VERSION" || true
mise use -g dotnet@"$DOTNET_VERSION" || true

# --------------------------------------------------
# Bun-based global tooling
# --------------------------------------------------
echo "[WSL] Installing JS tooling via Bun"

bun add -g \
  typescript \
  eslint \
  prettier \
  pnpm \
  nx \
  @biomejs/biome

# --------------------------------------------------
# Git defaults
# --------------------------------------------------
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor nvim

# --------------------------------------------------
# tmux defaults
# --------------------------------------------------
cat <<EOF > "$HOME/.tmux.conf"
set -g mouse on
setw -g mode-keys vi
set -g history-limit 10000
EOF

# --------------------------------------------------
# Quality-of-life tweaks
# --------------------------------------------------
grep -q 'alias cat=batcat' "$HOME/.zshrc" 2>/dev/null || cat <<'EOF' >> "$HOME/.zshrc"
alias cat=batcat
alias find=fdfind
EOF

echo fs.inotify.max_user_watches=524288 | sudo tee /etc/sysctl.d/99-wsl.conf >/dev/null
sudo sysctl --system >/dev/null

# --------------------------------------------------
# Workspace
# --------------------------------------------------
mkdir -p "$HOME/dev"

# --------------------------------------------------
# Mark completion
# --------------------------------------------------
touch "$BOOTSTRAP_FLAG"

echo "[WSL] Bootstrap complete"
echo "[WSL] Run: wsl --shutdown (from Windows) and reopen the distro"
