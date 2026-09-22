$ErrorActionPreference = 'Stop'
$Repo = 'abogdan/cld-dist'
$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\cld' }

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
  'AMD64' { 'amd64' }
  'ARM64' { 'arm64' }
  default { throw "unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}
$asset = "cld-windows-$arch.exe"

$rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
$base = "https://github.com/$Repo/releases/download/$($rel.tag_name)"
$tmp = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid()))
try {
  Write-Host "downloading cld $($rel.tag_name) (windows/$arch)..."
  Invoke-WebRequest "$base/$asset" -OutFile "$tmp\cld.exe"
  Invoke-WebRequest "$base/SHA256SUMS" -OutFile "$tmp\SHA256SUMS"
  $want = (Get-Content "$tmp\SHA256SUMS" | Where-Object { $_ -match " $([regex]::Escape($asset))$" }) -split '\s+' | Select-Object -First 1
  $got = (Get-FileHash "$tmp\cld.exe" -Algorithm SHA256).Hash.ToLower()
  if (-not $want -or $want -ne $got) { throw "checksum mismatch for ${asset}: expected '$want', got $got" }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  $dest = Join-Path $InstallDir 'cld.exe'
  # A running cld.exe (daemon, memory server) cannot be replaced, only renamed;
  # cld removes the old copy once nothing uses it.
  if (Test-Path $dest) { Rename-Item $dest "cld.exe.old-$([DateTime]::UtcNow.Ticks)" }
  Move-Item -Force "$tmp\cld.exe" $dest
} finally {
  Remove-Item -Recurse -Force $tmp
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $InstallDir) {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$InstallDir", 'User')
  Write-Host "added $InstallDir to your user PATH (restart the terminal)"
}
Write-Host "installed cld to $InstallDir\cld.exe"

# MemPalace is cld's default memory (per account, private); CLD_NO_MEMPALACE=1 skips it.
if (-not $env:CLD_NO_MEMPALACE -and -not (Get-Command mempalace-mcp -ErrorAction SilentlyContinue)) {
  Write-Host "installing MemPalace (cld's default memory)..."
  $env:UV_NO_MODIFY_PATH = '1'
  try {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
      powershell -ExecutionPolicy ByPass -NoProfile -Command "irm https://astral.sh/uv/install.ps1 | iex"
      $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $env:Path
    }
    uv tool install mempalace
    if ($LASTEXITCODE -ne 0) { throw "uv tool install mempalace failed" }
  } catch {
    Write-Host "MemPalace could not be installed; cld retries from the dashboard (Memory)"
  }
}
Write-Host 'then run: cld   (it sets up the shell integration for you: Settings -> Shell integration)'
