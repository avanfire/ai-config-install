# ai-config-install

One-line setup for [avanfire/ai-config](https://github.com/avanfire/ai-config) (a private repo). This repo holds only the
starter scripts; it contains no configuration.

**Linux / macOS**
```sh
curl -fsSL https://raw.githubusercontent.com/avanfire/ai-config-install/main/install.sh | sh
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/avanfire/ai-config-install/main/install.ps1 | iex
```

What it does (it asks once before starting, and again before anything that needs admin rights or edits your PATH):
1. Installs chezmoi and the GitHub CLI (stable releases) into `~/.local/bin`, no admin needed.
2. Installs git if it is missing (asks first).
3. Signs you in to GitHub with a browser code, only if you are not signed in yet.
4. Downloads the private repo and starts `ai-config`, which shows each change with its diff and asks before applying.

Run it again any time to update. Your global git settings are not changed.

These files are published from `bootstrap/` in the private repo; do not edit them here.
