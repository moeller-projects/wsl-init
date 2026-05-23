# WSL Bootstrap – Slim Bun + Node + .NET Setup

Single-file bootstrap script to turn a **fresh WSL distro** into a **reproducible, minimal-first Linux dev environment** with optional heavier tooling.

Designed for:
- WSL 2
- Ubuntu / Debian
- Bun-first JavaScript workflow
- Direct toolchain installs (no version manager)
- Idempotent, safe re-execution

---

## Features

- ✅ **One-liner install**
- ✅ **Single `install.sh` file**
- ✅ **Direct toolchain installs without a version manager**
- ✅ **Direct installs:** Node.js (NodeSource), Bun (official apt repo), .NET 8 (Microsoft apt feed)
- ✅ **Install profiles:** `minimal` (default), `dev`, `full`
- ✅ **Chrome is opt-in** (`INSTALL_CHROME=1`)
- ✅ **`--no-install-recommends`** for slimmer apt installs
- ✅ **Opt-in dotfiles bootstrap** from `moeller-projects/dotfiles`
- ✅ **Section markers** for faster reruns
- ✅ **WSL systemd + quality-of-life defaults**

---

## Quick Start (One-Liner)

Run this inside a fresh WSL distro:

```bash
sudo apt update && sudo apt install -y curl ca-certificates && \
curl -fsSL https://raw.githubusercontent.com/moeller-projects/wsl-init/main/install.sh | bash
```

After completion:

```powershell
wsl --shutdown
```

Then reopen the distro.

---

## Install Profiles

Profile is controlled by `WSL_PROFILE` or CLI flags.

| Profile | Purpose | Includes |
|---|---|---|
| `minimal` (default) | Fastest bootstrap | core packages + Node + Bun + .NET |
| `dev` | Typical dev workstation | `minimal` + ripgrep/fzf/tmux/neovim/build-essential + Bun global tools |
| `full` | Expanded toolset | `dev` + shellcheck |

Examples:

```bash
curl -fsSL https://raw.githubusercontent.com/moeller-projects/wsl-init/main/install.sh | bash -s -- --dev
```

```bash
WSL_PROFILE=full curl -fsSL https://raw.githubusercontent.com/moeller-projects/wsl-init/main/install.sh | bash
```

---

## Optional Chrome Install

Chrome is no longer installed by default.

```bash
INSTALL_CHROME=1 curl -fsSL https://raw.githubusercontent.com/moeller-projects/wsl-init/main/install.sh | bash
```

---

## Dotfiles Bootstrap (Opt-In)

Dotfiles bootstrap is disabled by default. Enable it with:

```bash
INSTALL_DOTFILES=1 curl -fsSL https://raw.githubusercontent.com/moeller-projects/wsl-init/main/install.sh | bash
```

Then the script bootstraps:

- Repo: `https://github.com/moeller-projects/dotfiles.git`
- Target directory: `~/.dotfiles`

Behavior:
- Clone if missing
- Pull (`--ff-only`) only when `DOTFILES_UPDATE=1`
- Run first available script from: `bootstrap.sh`, `install.sh`, `setup.sh`, `apply.sh`
- Non-fatal on network/script failures (bootstrap continues)
- Cache successful bootstrap to speed reruns

Overrides:

```bash
DOTFILES_REPO=https://github.com/moeller-projects/dotfiles.git \
DOTFILES_DIR=$HOME/.dotfiles \
DOTFILES_UPDATE=1 \
curl -fsSL https://raw.githubusercontent.com/moeller-projects/wsl-init/main/install.sh | bash
```

---

## What Gets Installed

### Core (all profiles)

- ca-certificates, curl, wget, git
- unzip, zip, jq
- locales, gnupg
- Node.js 20.x (NodeSource apt)
- Bun (official apt package)
- .NET SDK 8.0

### Dev extras (`dev`/`full`)

- build-essential
- ripgrep, fd-find, bat, fzf
- htop, tmux, tree, neovim
- Bun global tools:
  - typescript, eslint, prettier, pnpm, nx
  - @biomejs/biome, opencode-ai, @openai/codex, @fission-ai/openspec
  - Set `BUN_GLOBAL_TOOLS_UPDATE=1` (or `--update-bun-tools`) to refresh on reruns

### Full extras (`full`)

- shellcheck

---

## Idempotency and Rerun Speed

The script remains safe to re-run and now includes section markers in:

```text
~/.cache/wsl-init/sections/
```

This avoids repeating unchanged expensive setup steps on every rerun.

Completion flag:

```text
~/.wsl_bootstrap_done
```

---

## Startup Defaults for Agentic Coding

- Lean PATH setup (`~/.local/bin`, `~/.bun/bin`)
- Fast-path mode enabled by default: `WSL_AGENT_FAST_PATH=1`
- Optional lazy heavy shell config:

```bash
~/.bashrc.heavy
```

When `WSL_AGENT_FAST_PATH=1`, `~/.bashrc.heavy` is not sourced.

---

## Supported Platforms

| Platform | Status |
|--------|--------|
| WSL 2 | ✅ Supported |
| Ubuntu 22.04 / 24.04 | ✅ Supported |
| Debian 12 | ✅ Supported |
| Arch / Fedora | ❌ Not yet |

---

## Philosophy

Treat WSL as reproducible infrastructure, not a handcrafted snowflake box:

- Rebuild > Repair
- Explicit over clever
- Minimal by default
- Idempotent and disposable
