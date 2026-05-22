#!/usr/bin/env bash
set -euo pipefail

echo "[WSL] Bootstrap starting"

BOOTSTRAP_FLAG="$HOME/.wsl_bootstrap_done"
SECTION_CACHE_DIR="$HOME/.cache/wsl-init/sections"
APT_UPDATE_STAMP="$SECTION_CACHE_DIR/apt_update.stamp"
APT_UPDATE_MAX_AGE_SECONDS=21600

PROFILE="${WSL_PROFILE:-minimal}"
INSTALL_CHROME="${INSTALL_CHROME:-0}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/moeller-projects/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
NODE_MAJOR="${NODE_MAJOR:-20}"

for arg in "$@"; do
  case "$arg" in
    --profile=*)
      PROFILE="${arg#*=}"
      ;;
    --minimal)
      PROFILE="minimal"
      ;;
    --dev)
      PROFILE="dev"
      ;;
    --full)
      PROFILE="full"
      ;;
    --install-chrome)
      INSTALL_CHROME="1"
      ;;
    *)
      echo "[WSL] Unknown argument: $arg"
      exit 1
      ;;
  esac
done

case "$PROFILE" in
  minimal|dev|full) ;;
  *)
    echo "[WSL] Invalid profile: $PROFILE (use minimal|dev|full)"
    exit 1
    ;;
esac

mkdir -p "$SECTION_CACHE_DIR"

FIRST_RUN=1
if [[ -f "$BOOTSTRAP_FLAG" ]]; then
  echo "[WSL] Already bootstrapped — continuing update"
  FIRST_RUN=0
fi

echo "[WSL] Profile: $PROFILE"
echo "[WSL] Chrome install: $INSTALL_CHROME (set INSTALL_CHROME=1 or --install-chrome)"

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

section_done() {
  local section="$1"
  [[ -f "$SECTION_CACHE_DIR/$section.done" ]]
}

mark_section_done() {
  local section="$1"
  touch "$SECTION_CACHE_DIR/$section.done"
}

apt_update_if_needed() {
  local now last
  now="$(date +%s)"
  last=0

  if [[ -f "$APT_UPDATE_STAMP" ]]; then
    last="$(date -r "$APT_UPDATE_STAMP" +%s 2>/dev/null || echo 0)"
  fi
  # If the stamp is missing or unreadable, "last" stays 0 and we force a fresh update.

  if (( now - last < APT_UPDATE_MAX_AGE_SECONDS )); then
    echo "[WSL] apt update skipped (recently updated)"
    return
  fi

  sudo apt update
  touch "$APT_UPDATE_STAMP"
}

apt_install() {
  sudo apt install -y --no-install-recommends "$@"
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

install_node() {
  local repo_marker="nodesource_${NODE_MAJOR}_repo_v1"

  if ! section_done "$repo_marker"; then
    echo "[WSL] Configuring NodeSource repository (Node ${NODE_MAJOR}.x)"
    sudo install -dm 0755 /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
      sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | \
      sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
    mark_section_done "$repo_marker"
    rm -f "$APT_UPDATE_STAMP"
  fi

  if command -v node >/dev/null && node --version 2>/dev/null | grep -q "^v${NODE_MAJOR}\."; then
    echo "[WSL] Node ${NODE_MAJOR}.x already installed"
    return
  fi

  apt_update_if_needed
  apt_install nodejs
}

install_dotnet() {
  local repo_marker="dotnet_repo_${ID}_${VERSION_ID}_v1"
  local repo_url tmp_deb

  if ! section_done "$repo_marker"; then
    echo "[WSL] Configuring Microsoft package repository"
    case "$ID" in
      ubuntu)
        repo_url="https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"
        ;;
      debian)
        repo_url="https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb"
        ;;
      *)
        echo "[WSL] Unsupported distro for .NET repository: $ID"
        return
        ;;
    esac

    tmp_deb="$(mktemp /tmp/packages-microsoft-prod.XXXXXX.deb)"
    curl -fsSL "$repo_url" -o "$tmp_deb"
    sudo dpkg -i "$tmp_deb"
    rm -f "$tmp_deb"

    mark_section_done "$repo_marker"
    rm -f "$APT_UPDATE_STAMP"
  fi

  if command -v dotnet >/dev/null && dotnet --list-sdks 2>/dev/null | grep -q '^8\.'; then
    echo "[WSL] .NET 8 SDK already installed"
    return
  fi

  apt_update_if_needed
  apt_install dotnet-sdk-8.0
}

install_bun() {
  local repo_marker="bun_repo_v1"

  if ! section_done "$repo_marker"; then
    echo "[WSL] Configuring Bun apt repository"
    sudo install -dm 0755 /etc/apt/keyrings
    curl -fsSL https://bun.sh/keys/bun.asc | \
      sudo gpg --dearmor -o /etc/apt/keyrings/bun.gpg
    echo "deb [signed-by=/etc/apt/keyrings/bun.gpg] https://apt.bun.sh stable main" | \
      sudo tee /etc/apt/sources.list.d/bun.list >/dev/null
    mark_section_done "$repo_marker"
    rm -f "$APT_UPDATE_STAMP"
  fi

  if command -v bun >/dev/null; then
    echo "[WSL] Bun already installed"
    return
  fi

  echo "[WSL] Installing Bun from apt repository"
  apt_update_if_needed
  apt_install bun
}

ensure_agent_fastpath_loader() {
  cat > "$HOME/.wsl-agent-fastpath.sh" <<'EOF'
export WSL_AGENT_FAST_PATH="${WSL_AGENT_FAST_PATH:-1}"
if [[ "${WSL_AGENT_FAST_PATH:-1}" != "1" && -f "$HOME/.bashrc.heavy" ]]; then
  source "$HOME/.bashrc.heavy"
fi
EOF
}

bootstrap_dotfiles() {
  echo "[WSL] Bootstrapping dotfiles from $DOTFILES_REPO"

  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    if ! git -C "$DOTFILES_DIR" pull --ff-only; then
      echo "[WSL] Warning: dotfiles update failed (local changes/conflicts or network issue, continuing)"
      return 0
    fi
  else
    if ! git clone --depth 1 "$DOTFILES_REPO" "$DOTFILES_DIR"; then
      echo "[WSL] Warning: dotfiles clone failed (check network access and DOTFILES_REPO URL, continuing)"
      return 0
    fi
  fi

  local script_path
  for script_path in \
    "$DOTFILES_DIR/bootstrap.sh" \
    "$DOTFILES_DIR/install.sh" \
    "$DOTFILES_DIR/setup.sh" \
    "$DOTFILES_DIR/apply.sh"
  do
    if [[ -f "$script_path" ]]; then
      echo "[WSL] Running dotfiles script: ${script_path#$DOTFILES_DIR/}"
      if ! (cd "$DOTFILES_DIR" && bash "./$(basename "$script_path")"); then
        echo "[WSL] Warning: dotfiles script ${script_path#$DOTFILES_DIR/} failed (continuing)"
      fi
      return 0
    fi
  done

  echo "[WSL] No known dotfiles bootstrap script found (continuing)"
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
# Base packages (minimal-first)
# --------------------------------------------------
apt_update_if_needed

apt_install \
  ca-certificates \
  curl wget git \
  unzip zip jq \
  locales \
  gnupg

if [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
  apt_install \
    build-essential \
    ripgrep fd-find bat fzf \
    htop tmux tree neovim
fi

if [[ "$PROFILE" == "full" ]]; then
  apt_install shellcheck
fi

# --------------------------------------------------
# Locale
# --------------------------------------------------
if ! section_done "locale_en_us_utf8_v1"; then
  sudo locale-gen en_US.UTF-8
  sudo update-locale LANG=en_US.UTF-8
  mark_section_done "locale_en_us_utf8_v1"
fi

# --------------------------------------------------
# Enable systemd in WSL
# --------------------------------------------------
ensure_wsl_systemd

# --------------------------------------------------
# Toolchains (Node + Bun + .NET)
# --------------------------------------------------
echo "[WSL] Installing toolchains directly (no version manager)"
install_node
install_bun
install_dotnet

# --------------------------------------------------
# Bun global bin path
# --------------------------------------------------
ensure_line 'export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"' "$HOME/.bashrc"

# --------------------------------------------------
# Bun-based global tooling (dev/full profiles)
# --------------------------------------------------
if [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
  if ! section_done "bun_global_tools_v1"; then
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
      mark_section_done "bun_global_tools_v1"
    else
      echo "[WSL] Bun not found; skipping global JS tooling install"
    fi
  else
    echo "[WSL] Global JS tooling already installed"
  fi
fi

# --------------------------------------------------
# Headless Chrome (opt-in)
# --------------------------------------------------
if [[ "$INSTALL_CHROME" == "1" ]]; then
  if ! command -v google-chrome >/dev/null; then
    echo "[WSL] Installing headless Chrome"

    apt_install \
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

    rm -f "$APT_UPDATE_STAMP"
    apt_update_if_needed
    apt_install google-chrome-stable
  else
    echo "[WSL] Chrome already installed"
  fi
fi

# --------------------------------------------------
# Dotfiles bootstrap (non-fatal)
# --------------------------------------------------
bootstrap_dotfiles

# --------------------------------------------------
# Git defaults
# --------------------------------------------------
git config --global init.defaultBranch main
git config --global pull.rebase false

if command -v nvim >/dev/null; then
  git config --global core.editor nvim
fi

# --------------------------------------------------
# tmux defaults
# --------------------------------------------------
if command -v tmux >/dev/null; then
  ensure_line "set -g mouse on" "$HOME/.tmux.conf"
  ensure_line "setw -g mode-keys vi" "$HOME/.tmux.conf"
  ensure_line "set -g history-limit 10000" "$HOME/.tmux.conf"
fi

# --------------------------------------------------
# Quality-of-life tweaks (fast startup defaults)
# --------------------------------------------------
ensure_line 'command -v batcat >/dev/null && alias cat=batcat' "$HOME/.bashrc"
ensure_line 'command -v fdfind >/dev/null && alias find=fdfind' "$HOME/.bashrc"
ensure_line 'alias ccusage-codex='\''bunx @ccusage/codex@latest'\''' "$HOME/.bashrc"
ensure_agent_fastpath_loader
ensure_line 'source "$HOME/.wsl-agent-fastpath.sh"' "$HOME/.bashrc"
ensure_line 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' "$HOME/.bashrc"
ensure_line 'export NPM_CONFIG_UPDATE_NOTIFIER=false' "$HOME/.bashrc"
ensure_line 'export NPM_CONFIG_FUND=false' "$HOME/.bashrc"

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
echo "[WSL] profile: $PROFILE"
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
if command -v nvim >/dev/null; then
  echo "[WSL] nvim: $(nvim --version 2>/dev/null | head -n 1)"
else
  echo "[WSL] nvim: missing"
fi
if command -v google-chrome >/dev/null; then
  echo "[WSL] chrome: $(google-chrome --version 2>/dev/null)"
else
  echo "[WSL] chrome: not installed (set INSTALL_CHROME=1)"
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
