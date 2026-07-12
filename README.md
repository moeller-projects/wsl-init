# WSL Bootstrap – Bun Developer Setup

Single-file, one-liner bootstrap script to turn a **fresh WSL distro** into a **reproducible, high-performance Linux dev environment**.

Designed for:
- WSL 2
- Ubuntu / Debian
- Bun-first JavaScript workflow
- Each toolchain installed via its own official, recommended installer
- Idempotent, safe re-execution
- Zero manual post-install steps

—

## Features

- ✅ **One-liner install**
- ✅ **Single `install.sh` file** (no sub-scripts)
- ✅ **Official installer per toolchain** (no version-manager layer)
- ✅ **Bun instead of npm**
- ✅ **Node.js (Active LTS) via NodeSource**
- ✅ **.NET SDK (current LTS) via Microsoft’s dotnet-install script**
- ✅ **Rust via rustup**
- ✅ **Python via uv (Astral)**
- ✅ **Bash (default shell)**
- ✅ **systemd enabled in WSL**
- ✅ **Recommended /etc/wsl.conf tuning**
- ✅ **tmux / neovim / fzf / ripgrep**
- ✅ **Headless Chrome (opt-in via `—with-chrome`)**
- ✅ **Safe to re-run**
- ✅ **WSL-optimized defaults**

—

## Supported Platforms

| Platform | Status |
|———|———|
| WSL 2 | ✅ Supported |
| Ubuntu 22.04 / 24.04 | ✅ Supported |
| Debian 12 | ✅ Supported |
| Arch / Fedora | ❌ Not yet |

—

## Quick Start (One-Liner)

Run this **inside a fresh WSL distro**:

```bash
sudo apt update && sudo apt install -y curl ca-certificates && \
curl -fsSL https://raw.githubusercontent.com/moeller-projects/wsl-init/main/install.sh | bash
```

Add `—with-chrome` at the end if you need headless Chrome installed too.

After completion:

```powershell
wsl —shutdown
```

Then reopen the distro.

—

## What Gets Installed

### Base System

* build-essential
* curl / wget / git
* unzip / zip / jq
* ripgrep / fd / bat / fzf
* htop / tmux / tree
* neovim
* locales

### Shell & UX

* **bash** (default shell)
* sane aliases (`cat`, `find`)
* `ollama-host` alias — resolves the Windows host IP from inside WSL, for reaching a host-side Ollama instance
* Bun global bin in PATH (`~/.bun/bin`)
* increased inotify limits

### Toolchains (each via its own official installer)

| Tool     | Installer                          | Version           |
| ——— | ———————————— | —————— |
| Node.js  | NodeSource setup script             | 24.x (Active LTS)  |
| Bun      | `bun.sh/install`                    | latest (pin via `BUN_VERSION`) |
| .NET SDK | Microsoft `dotnet-install.sh`       | 10.0 channel (LTS) |
| Rust     | `rustup.rs`                         | stable             |
| Python   | `uv` (Astral)                       | 3.13 (pin via `PYTHON_VERSION`) |

No version-manager layer (no `mise`, no `pyenv`, no `nvm`) — each language’s own recommended installer is used directly, and re-runs skip anything already installed at the pinned version.

### Optional: Headless Chrome

Only installed when the script is run with `—with-chrome`. Not installed by default.

### Recommended `/etc/wsl.conf` settings

Applied idempotently on every run:

| Section     | Key                 | Value      | Why                                                            |
| ———— | ——————— | -——— | -————————————————————— |
| `[boot]`    | `systemd`             | `true`     | Lets services (docker/podman, ssh-agent, etc.) run normally      |
| `[interop]` | `appendWindowsPath`   | `false`    | Keeps Linux PATH lookups fast, avoids `.exe` shadowing           |
| `[interop]` | `enabled`             | `true`     | Still allows running Windows binaries from WSL when needed       |
| `[automount]` | `options`           | `metadata` | Correct Linux file permissions on mounted Windows drives         |

—

## JavaScript Workflow (Bun-First)

```bash
bun init
bun install
bun run dev
bun test
```

No npm.
No yarn.
No path hacks.

> Global JS tooling (typescript, eslint, prettier, etc.) is **not** installed by the bootstrap script — install what each project actually needs via `bun add -g <pkg>` or as a dev dependency.

—

## Python Workflow (uv-First)

```bash
uv venv
uv pip install <package>
uv run <script>.py
uv python list
```

## Rust Workflow

```bash
cargo new my-project
cargo build
cargo run
```

—

## Reaching Ollama on the Windows Host

If Ollama runs on Windows (e.g. via Podman Desktop setup) rather than inside WSL:

1. On Windows, set `OLLAMA_HOST=0.0.0.0` so Ollama isn’t bound to localhost-only, then restart it.
2. From WSL, use the `ollama-host` alias (installed by this script) to resolve the Windows host IP:
   ```bash
   curl http://$(ollama-host):11434
   ```
3. Cleaner alternative (Windows 11 22H2+): enable mirrored networking in `%USERPROFILE%\.wslconfig`:
   ```ini
   [wsl2]
   networkingMode=mirrored
   ```
   Then `localhost:11434` works directly from WSL after `wsl —shutdown` + reopen.

—

## Directory Layout

```text
~
├─ dev/              # all projects live here (Linux FS)
├─ .cargo/           # Rust toolchain
├─ .dotnet/           # .NET SDK
├─ .bun/              # Bun runtime + global bin
├─ .local/bin/        # uv + uv-managed tools
├─ .bashrc
├─ .tmux.conf
└─ .wsl_bootstrap_done
```

> Always keep repositories **inside the Linux filesystem**, not `/mnt/c`.

—

## Idempotency

The script creates:

```text
~/.wsl_bootstrap_done
```

If present, the script still runs in update mode and keeps settings/toolchains in sync. Each toolchain step checks whether the pinned version is already installed and skips reinstalling if so.
Config files like `/etc/wsl.conf`, `.bashrc`, and `.tmux.conf` are merged (not overwritten).

This makes it:

* safe to re-run
* safe for CI
* safe for one-liners

—

## Design Principles

* **Rebuild > Repair**
* **Explicit over clever**
* **Pinned versions**
* **Official installer per tool, no extra abstraction layer**
* **Cattle, not pets**

If something breaks:

1. Delete the distro
2. Re-import or reinstall
3. Run the script again

—

## Customization

Edit `install.sh` directly. Version pins live near the top of the file:

```bash
NODE_MAJOR=“24”
DOTNET_CHANNEL=“10.0”
BUN_VERSION=“latest”
PYTHON_VERSION=“3.13”
```

Bump them when you want to move a toolchain forward.

—

## Roadmap (Optional)

* [ ] Arch / Fedora support
* [ ] Dotfiles auto-bootstrap
* [ ] CI validation
* [ ] Team onboarding mode

—

## Philosophy

This repository treats WSL as **infrastructure**, not a snowflake dev box.

Reproducible.
Deterministic.
Disposable.
