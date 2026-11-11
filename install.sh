#!/bin/sh
# ai-config bootstrap for Linux and macOS.
#   curl -fsSL https://raw.githubusercontent.com/avanfire/ai-config-install/main/install.sh | sh
#
# Sets up chezmoi + GitHub CLI (stable releases, in ~/.local/bin, no admin), signs you in to GitHub,
# downloads the private repo avanfire/ai-config and starts `ai-config`. Safe to re-run (it updates).
# Everything is inside main(), called on the last line, so a truncated download runs nothing.

main() {
  SLUG="avanfire/ai-config"
  MIN_CHEZMOI="2.74.0"
  BIN="${AICONFIG_BIN_DIR:-$HOME/.local/bin}"
  ORIG_PATH="$PATH"
  HELPER='!gh auth git-credential'

  have() { command -v "$1" >/dev/null 2>&1; }
  say() { printf '%s\n' "$*"; }
  die() { printf 'ai-config setup: %s\n' "$*" >&2; exit 1; }
  tty_ok() { ( : </dev/tty ) 2>/dev/null; }
  # ask_yn QUESTION DEFAULT(y|n): reads from the terminal, never from the piped script.
  ask_yn() {
    if [ "$2" = y ]; then _hint='[Y/n]'; else _hint='[y/N]'; fi
    printf '%s %s ' "$1" "$_hint" > /dev/tty
    read -r _a < /dev/tty || return 1
    case "$_a" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      "") [ "$2" = y ] ;;
      *) return 1 ;;
    esac
  }
  ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }
  chezmoi_ver() { chezmoi --version 2>/dev/null | sed -n 's/^chezmoi version v\{0,1\}\([0-9][0-9.]*\).*/\1/p'; }

  if ! tty_ok; then
    cat >&2 <<EOF
ai-config setup needs a terminal to ask before installing anything and to sign you in to GitHub.
Run it from a terminal, or do the steps by hand:
  1. Install chezmoi:      https://www.chezmoi.io/install/
  2. Install git and the GitHub CLI (gh), then:  gh auth login
  3. chezmoi init https://github.com/$SLUG.git
  4. sh ~/.local/share/chezmoi/dot_local/bin/executable_ai-config
EOF
    exit 1
  fi

  say "ai-config setup"
  say "This will install chezmoi and the GitHub CLI into $BIN (stable releases, no admin rights),"
  say "sign you in to GitHub, and download $SLUG."
  ask_yn "Continue?" y || { say "Nothing was changed."; exit 0; }

  mkdir -p "$BIN" || die "cannot create $BIN"
  PATH="$BIN:$PATH"; export PATH

  # 1. chezmoi (stable, >= MIN_CHEZMOI)
  cur=$(chezmoi_ver)
  if [ -z "$cur" ] || ! ver_ge "$cur" "$MIN_CHEZMOI"; then
    say "[1/5] Installing chezmoi (latest stable) into $BIN ..."
    have curl || die "curl is required"
    curl -fsSL https://get.chezmoi.io | sh -s -- -b "$BIN" || die "chezmoi install failed"
    cur=$(chezmoi_ver)
    { [ -n "$cur" ] && ver_ge "$cur" "$MIN_CHEZMOI"; } || die "chezmoi $MIN_CHEZMOI or newer is required (found: ${cur:-none})"
  else
    say "[1/5] chezmoi $cur found."
  fi

  # 2. git (needs admin on Linux; asks first)
  if have git; then
    say "[2/5] git found."
  else
    say "[2/5] git is not installed (needed to download the private repo)."
    case "$(uname -s)" in
      Darwin)
        ask_yn "Install the Apple command line tools (includes git)?" y || die "git is required"
        xcode-select --install </dev/tty
        die "Finish the Apple tools installation, then run this command again." ;;
      *)
        if have dnf; then cmd="sudo dnf install -y git"
        elif have apt-get; then cmd="sudo apt-get install -y git"
        elif have pacman; then cmd="sudo pacman -S --noconfirm git"
        elif have zypper; then cmd="sudo zypper install -y git"
        else die "install git with your package manager, then run this command again."; fi
        ask_yn "Install git with '$cmd' (needs admin rights)?" y || die "git is required"
        $cmd </dev/tty || die "git install failed"
        have git || die "git still not found after install" ;;
    esac
  fi

  # 3. GitHub CLI (release archive into BIN, no admin)
  if have gh; then
    say "[3/5] GitHub CLI found."
  else
    say "[3/5] Installing the GitHub CLI (latest stable) into $BIN ..."
    have curl || die "curl is required"
    case "$(uname -m)" in
      x86_64|amd64) arch=amd64 ;;
      aarch64|arm64) arch=arm64 ;;
      armv6l|armv7l) arch=armv6 ;;
      i?86) arch=386 ;;
      *) die "unsupported CPU: $(uname -m)" ;;
    esac
    case "$(uname -s)" in
      Linux) os=linux; ext=tar.gz ;;
      Darwin) os=macOS; ext=zip ;;
      *) die "unsupported system: $(uname -s)" ;;
    esac
    tag=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n1)
    [ -n "$tag" ] || die "could not find the latest GitHub CLI release"
    tmp=$(mktemp -d) || die "mktemp failed"
    curl -fsSL -o "$tmp/gh.$ext" "https://github.com/cli/cli/releases/download/v$tag/gh_${tag}_${os}_${arch}.$ext" || die "GitHub CLI download failed"
    if [ "$ext" = zip ]; then unzip -q "$tmp/gh.zip" -d "$tmp" || die "unzip failed"; else tar -xzf "$tmp/gh.tar.gz" -C "$tmp" || die "tar failed"; fi
    cp "$tmp"/gh_*/bin/gh "$BIN/gh" && chmod +x "$BIN/gh" || die "could not install gh"
    rm -rf "$tmp"
  fi

  # 4. GitHub sign-in (only if needed). The sign-in is used for the ai-config repo only; git's global config is not changed.
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    say "[4/5] Signed in to GitHub."
  else
    say "[4/5] You are not signed in to GitHub."
    # GIT_CONFIG_GLOBAL points at a throwaway file, so even if gh offers (and you accept) to set up git
    # credentials, your real global git config is not modified.
    GIT_CONFIG_GLOBAL=$(mktemp) gh auth login --hostname github.com --git-protocol https --web </dev/tty || die "GitHub sign-in failed"
  fi

  # 5. Repo
  SRC=$(chezmoi source-path 2>/dev/null)
  [ -n "$SRC" ] || SRC="$HOME/.local/share/chezmoi"
  if [ -d "$SRC" ]; then
    url=$(git -C "$SRC" remote get-url origin 2>/dev/null) || die "$SRC exists but is not a git repo with an 'origin'. Move it aside and run this again."
    case "$url" in
      https://github.com/"$SLUG"|https://github.com/"$SLUG".git|git@github.com:"$SLUG"|git@github.com:"$SLUG".git|ssh://git@github.com/"$SLUG"|ssh://git@github.com/"$SLUG".git) ;;
      *) die "$SRC is a chezmoi folder for a different repo ($url). ai-config will not touch it." ;;
    esac
    say "[5/5] Updating $SLUG ..."
    GIT_TERMINAL_PROMPT=0 git -C "$SRC" -c credential.helper= -c "credential.helper=$HELPER" pull --ff-only </dev/null || say "      (could not update; continuing with the version already downloaded)"
  else
    say "[5/5] Downloading $SLUG ..."
    GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c "credential.helper=$HELPER" clone "https://github.com/$SLUG.git" "$SRC" </dev/null || die "download failed (are you signed in to the right GitHub account?)"
  fi
  # Scoped to this repo only (later `ai-config update` / `chezmoi git -- pull` work without prompts).
  git -C "$SRC" config --local --replace-all credential.https://github.com.helper "" 2>/dev/null
  git -C "$SRC" config --local --add credential.https://github.com.helper "$HELPER" 2>/dev/null
  if ! ls "$HOME"/.config/chezmoi/chezmoi.* >/dev/null 2>&1; then
    chezmoi init </dev/null || die "chezmoi init failed"
  fi
  [ -f "$SRC/dot_local/bin/executable_ai-config" ] || die "the downloaded repo has no ai-config command"

  # PATH (asks; only when the folder is not already on PATH)
  case ":$ORIG_PATH:" in
    *":$BIN:"*) ;;
    *)
      case "${SHELL:-}" in
        */zsh) profile="$HOME/.zshrc" ;;
        */bash) if [ "$(uname -s)" = Darwin ]; then profile="$HOME/.bash_profile"; else profile="$HOME/.bashrc"; fi ;;
        *) profile="$HOME/.profile" ;;
      esac
      if ask_yn "Add $BIN to your PATH in $profile (so 'ai-config' and 'chezmoi' work in new terminals)?" y; then
        if grep -qF "added by ai-config setup" "$profile" 2>/dev/null; then
          say "$profile already has the ai-config PATH line."
        else
          printf '\n# added by ai-config setup\nexport PATH="%s:$PATH"\n' "$BIN" >> "$profile"
          say "Added. Open a new terminal to use it."
        fi
      fi ;;
  esac

  say ""
  say "Starting ai-config ..."
  sh "$SRC/dot_local/bin/executable_ai-config" </dev/tty
}

main "$@"
