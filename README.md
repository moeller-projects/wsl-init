# WSL Bootstrap – mise + Bun Developer Setup

Single-file, one-liner bootstrap script to turn a **fresh WSL distro** into a **reproducible, high-performance Linux dev environment**.

Designed for:
- WSL 2
- Ubuntu / Debian
- Bun-first JavaScript workflow
- `mise` as the single version manager
- Idempotent, safe re-execution
- Zero manual post-install steps

---

## Features

- ✅ **One-liner install**
- ✅ **Single `install.sh` file** (no sub-scripts)
- ✅ **`mise` for all toolchains**
- ✅ **Bun instead of npm**
- ✅ **Node available for compatibility**
- ✅ **.NET 8 preinstalled**
- ✅ **zsh + Starship**
- ✅ **systemd enabled in WSL**
- ✅ **tmux / neovim / fzf / ripgrep**
- ✅ **Safe to re-run**
- ✅ **WSL-optimized defaults**

---

## Supported Platforms

| Platform | Status |
|--------|--------|
| WSL 2 | ✅ Supported |
| Ubuntu 22.04 / 24.04 | ✅ Supported |
| Debian 12 | ✅ Supported |
| Arch / Fedora | ❌ Not yet |

---

## Quick Start (One-Liner)

Run this **inside a fresh WSL distro**:

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

## What Gets Installed

### Base System

* build-essential
* curl / wget / git
* unzip / zip / jq
* ripgrep / fd / bat / fzf
* htop / tmux / tree
* neovim
* zsh
* locales

### Shell & UX

* **zsh** (default shell)
* **Starship** prompt
* sane aliases (`cat`, `find`)
* increased inotify limits

### Version Management

* **mise** (installed via apt)

### Toolchains (Pinned)

| Tool     | Version   |
| -------- | --------- |
| Node.js  | `20.11.1` |
| Bun      | `1.1.4`   |
| .NET SDK | `8.0.100` |

### Global JS Tooling (via Bun)

* typescript
* eslint
* prettier
* pnpm
* nx
* @biomejs/biome

---

## JavaScript Workflow (Bun-First)

```bash
bun init
bun install
bun run dev
bun test
```

Global tools:

```bash
bunx eslint .
bunx prettier .
bunx biome check .
```

No npm.
No yarn.
No path hacks.

---

## Directory Layout

```text
~
├─ dev/              # all projects live here (Linux FS)
├─ .config/mise/
├─ .zshrc
├─ .tmux.conf
└─ .wsl_bootstrap_done
```

> Always keep repositories **inside the Linux filesystem**, not `/mnt/c`.

---

## Idempotency

The script creates:

```text
~/.wsl_bootstrap_done
```

If present, the script still runs in update mode and keeps settings/toolchains in sync.
Config files like `/etc/wsl.conf` and `~/.tmux.conf` are merged (not overwritten).

This makes it:

* safe to re-run
* safe for CI
* safe for one-liners

---

## Design Principles

* **Rebuild > Repair**
* **Explicit over clever**
* **Pinned versions**
* **One source of truth**
* **Cattle, not pets**

If something breaks:

1. Delete the distro
2. Re-import or reinstall
3. Run the script again

---

## Customization

Edit `install.sh` directly and add sections:

```bash
# Infra tools
mise use -g terraform@1.7.5
```

No structural changes required.

---

## Roadmap (Optional)

* [ ] Flags (`--minimal`, `--node-only`, `--infra`)
* [ ] Arch / Fedora support
* [ ] Dotfiles auto-bootstrap
* [ ] CI validation
* [ ] Team onboarding mode

---

## Philosophy

This repository treats WSL as **infrastructure**, not a snowflake dev box.

Reproducible.
Deterministic.
Disposable.
