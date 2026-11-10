# ai-config bootstrap for Windows (PowerShell 5.1+).
#   irm https://raw.githubusercontent.com/avanfire/ai-config-install/main/install.ps1 | iex
#
# Sets up chezmoi + GitHub CLI (stable releases, in ~\.local\bin, no admin), signs you in to GitHub,
# downloads the private repo avanfire/ai-config and starts `ai-config`. Safe to re-run (it updates).
# Everything is inside Main, called on the last line, so a truncated download runs nothing.

function Main {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
  $Slug = 'avanfire/ai-config'
  $MinChezmoi = [version]'2.74.0'
  $Bin = [IO.Path]::GetFullPath($(if ($env:AICONFIG_BIN_DIR) { $env:AICONFIG_BIN_DIR } else { Join-Path $HOME '.local/bin' })).TrimEnd('\', '/')
  $OrigPath = $env:Path
  $Helper = '!gh auth git-credential'

  function Have($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
  function Die($msg) { Write-Host "ai-config setup: $msg" -ForegroundColor Red; throw "ai-config setup stopped" }
  function Ask-YN($question, $default) {
    $hint = if ($default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    $a = Read-Host "$question $hint"
    if ($a -match '^(y|yes)$') { return $true }
    if ($a -match '^(n|no)$') { return $false }
    return ($a -eq '' -and $default -eq 'y')
  }
  function Refresh-Path {
    if ($env:OS -eq 'Windows_NT') {
      $env:Path = "$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    }
  }
  function Chezmoi-Version {
    if (-not (Have 'chezmoi')) { return $null }
    $t = (chezmoi --version 2>$null | Out-String)
    if ($t -match 'chezmoi version v?(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
  }

  if ([Console]::IsInputRedirected) {
    Write-Host "ai-config setup needs a terminal to ask before installing anything and to sign you in to GitHub." -ForegroundColor Red
    Write-Host "Run it from a PowerShell window, or do the steps by hand:"
    Write-Host "  1. Install chezmoi:  winget install twpayne.chezmoi"
    Write-Host "  2. Install git and the GitHub CLI, then:  gh auth login"
    Write-Host "  3. chezmoi init https://github.com/$Slug.git"
    Write-Host "  4. powershell -ExecutionPolicy Bypass -File `$HOME\.local\share\chezmoi\dot_local\bin\ai-config.ps1"
    throw "ai-config setup stopped (no terminal)"   # not 'exit': under irm | iex that would close the window
  }

  Write-Host "ai-config setup"
  Write-Host "This will install chezmoi and the GitHub CLI into $Bin (stable releases, no admin rights),"
  Write-Host "sign you in to GitHub, and download $Slug."
  if (-not (Ask-YN 'Continue?' 'y')) { Write-Host "Nothing was changed."; return }

  New-Item -ItemType Directory -Force -Path $Bin | Out-Null
  $env:Path = "$Bin$([IO.Path]::PathSeparator)$env:Path"

  # 1. chezmoi (stable, >= MinChezmoi)
  $cur = Chezmoi-Version
  if (-not $cur -or $cur -lt $MinChezmoi) {
    Write-Host "[1/5] Installing chezmoi (latest stable) into $Bin ..."
    & ([scriptblock]::Create((Invoke-RestMethod -UseBasicParsing 'https://get.chezmoi.io/ps1'))) -b $Bin
    $cur = Chezmoi-Version
    if (-not $cur -or $cur -lt $MinChezmoi) { Die "chezmoi $MinChezmoi or newer is required (found: $cur)" }
  } else {
    Write-Host "[1/5] chezmoi $cur found."
  }

  # 2. git (winget; asks first, may show an admin prompt)
  if (Have 'git') {
    Write-Host "[2/5] git found."
  } else {
    Write-Host "[2/5] git is not installed (needed to download the private repo)."
    if (-not (Have 'winget')) { Die "install git from https://git-scm.com/download/win, then run this command again." }
    if (-not (Ask-YN "Install git with 'winget install --id Git.Git -e' (may ask for admin rights)?" 'y')) { Die "git is required" }
    winget install --id Git.Git -e --source winget
    Refresh-Path
    if (-not (Have 'git')) { Die "git was installed but is not on PATH yet. Open a new PowerShell window and run this command again." }
  }

  # 3. GitHub CLI (release zip into Bin, no admin)
  if (Have 'gh') {
    Write-Host "[3/5] GitHub CLI found."
  } else {
    Write-Host "[3/5] Installing the GitHub CLI (latest stable) into $Bin ..."
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $tag = (Invoke-RestMethod -UseBasicParsing 'https://api.github.com/repos/cli/cli/releases/latest').tag_name.TrimStart('v')
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("aicfg-gh-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'gh.zip'
    Invoke-WebRequest -UseBasicParsing "https://github.com/cli/cli/releases/download/v$tag/gh_${tag}_windows_$arch.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $exe = Get-ChildItem -Path $tmp -Recurse -Filter 'gh.exe' | Select-Object -First 1
    if (-not $exe) { Die "could not find gh.exe in the download" }
    Copy-Item $exe.FullName (Join-Path $Bin 'gh.exe') -Force
    Remove-Item -Recurse -Force $tmp
  }

  # 4. GitHub sign-in (only if needed). Used for the ai-config repo only; git's global config is not changed.
  gh auth status --hostname github.com *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[4/5] Signed in to GitHub."
  } else {
    Write-Host "[4/5] You are not signed in to GitHub."
    Write-Host "      If GitHub CLI asks 'Authenticate Git with your GitHub credentials?', answer n (this setup uses its own access)."
    # GIT_CONFIG_GLOBAL points at a throwaway file, so your real global git config is never modified.
    $env:GIT_CONFIG_GLOBAL = [IO.Path]::GetTempFileName()
    try { gh auth login --hostname github.com --git-protocol https --web } finally { Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue }
    if ($LASTEXITCODE -ne 0) { Die "GitHub sign-in failed" }
  }

  # 5. Repo
  $src = (chezmoi source-path 2>$null | Out-String).Trim()
  if (-not $src) { $src = Join-Path $HOME '.local/share/chezmoi' }
  if (Test-Path $src) {
    $url = (git -C $src remote get-url origin 2>$null | Out-String).Trim()
    if (-not $url) { Die "$src exists but is not a git repo with an 'origin'. Move it aside and run this again." }
    if ($url -notmatch "^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)$([regex]::Escape($Slug))(\.git)?$") { Die "$src is a chezmoi folder for a different repo ($url). ai-config will not touch it." }
    Write-Host "[5/5] Updating $Slug ..."
    $env:GIT_TERMINAL_PROMPT = '0'
    git -C $src -c credential.helper= -c "credential.helper=$Helper" pull --ff-only
    if ($LASTEXITCODE -ne 0) { Write-Host "      (could not update; continuing with the version already downloaded)" }
  } else {
    Write-Host "[5/5] Downloading $Slug ..."
    $env:GIT_TERMINAL_PROMPT = '0'
    git -c credential.helper= -c "credential.helper=$Helper" clone "https://github.com/$Slug.git" $src
    if ($LASTEXITCODE -ne 0) { Die "download failed (are you signed in to the right GitHub account?)" }
  }
  Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
  # Scoped to this repo only (later `ai-config update` works without prompts).
  git -C $src config --local --replace-all credential.https://github.com.helper ""
  git -C $src config --local --add credential.https://github.com.helper $Helper
  $cfgDir = Join-Path $HOME '.config/chezmoi'
  if (-not (Get-ChildItem -Path $cfgDir -Filter 'chezmoi.*' -ErrorAction SilentlyContinue)) {
    chezmoi init
    if ($LASTEXITCODE -ne 0) { Die "chezmoi init failed" }
  }
  $wrapper = Join-Path $src 'dot_local/bin/ai-config.ps1'
  if (-not (Test-Path $wrapper)) { Die "the downloaded repo has no ai-config command" }

  # PATH (asks; only when the folder is not already on PATH). Compared entry by entry, not as a wildcard string.
  $sep = [IO.Path]::PathSeparator
  $entries = @($OrigPath -split [regex]::Escape([string]$sep) | ForEach-Object { $_.TrimEnd('\', '/') })
  if ($entries -notcontains $Bin) {
    if (Ask-YN "Add $Bin to your PATH (so 'ai-config' and 'chezmoi' work in new terminals)?" 'y') {
      if ($env:OS -eq 'Windows_NT') {
        # Edit the registry value directly so %VARIABLES% already in the user's PATH stay unexpanded.
        $key = Get-Item 'HKCU:\Environment'
        $cur = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if (@($cur -split ';' | ForEach-Object { $_.TrimEnd('\', '/') }) -notcontains $Bin) {
          Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value "$Bin;$cur" -Type ExpandString
        }
        Write-Host "Added. Open a new terminal to use it."
      }
    }
  }

  Write-Host ""
  Write-Host "Starting ai-config ..."
  # Run in a child PowerShell with the execution policy bypassed for this one script (the default policy blocks .ps1 files).
  $psExe = if (Have 'powershell') { 'powershell' } else { 'pwsh' }
  & $psExe -NoProfile -ExecutionPolicy Bypass -File $wrapper
}

Main
