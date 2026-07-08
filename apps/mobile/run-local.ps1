<#
.SYNOPSIS
  Run the Nirman mobile app against the LOCAL Supabase Docker stack (for testing).

.DESCRIPTION
  build-apk.ps1 points at PRODUCTION (../../.env.local). This script does NOT touch
  that — it injects the LOCAL stack's URL + anon key (read live from `supabase status`)
  via --dart-define and `flutter run`s a debug build. Nothing here writes to prod.

  Reaching the local stack depends on the target:
    -Usb        Physical phone over USB (RECOMMENDED). Runs `adb reverse` so the
                phone's localhost:54321 tunnels to your PC over the cable. No Wi-Fi,
                no LAN IP, no firewall. Uses 127.0.0.1.
    (default)   Android emulator — host is reachable at 10.0.2.2.
    -HostIp X   Physical phone on the same Wi-Fi — pass your PC's LAN IP.

.EXAMPLE
  ./run-local.ps1 -Usb                  # physical phone via USB debugging (best)
  ./run-local.ps1                       # Android emulator
  ./run-local.ps1 -HostIp 192.168.1.42  # physical phone on same Wi-Fi
#>
param(
  [switch]$Usb,
  [string]$HostIp = '10.0.2.2',
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

$Flutter   = 'C:\Users\rpxi1\flutter\bin\flutter.bat'
$MobileDir = $PSScriptRoot
$RepoRoot  = Resolve-Path (Join-Path $MobileDir '..\..')

# Pull local stack creds live (always correct, never hardcoded).
Push-Location $RepoRoot
try {
  $statusLines = & supabase status -o env 2>$null
} finally {
  Pop-Location
}

$cfg = @{}
foreach ($line in $statusLines) {
  $t = $line.Trim()
  if ($t -eq '' -or -not $t.Contains('=')) { continue }
  $i = $t.IndexOf('=')
  $cfg[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim().Trim('"')
}

$url = $cfg['API_URL']
$key = $cfg['ANON_KEY']
if ([string]::IsNullOrWhiteSpace($url)) { throw 'API_URL missing -- is `supabase start` running?' }
if ([string]::IsNullOrWhiteSpace($key)) { throw 'ANON_KEY missing -- is `supabase start` running?' }

# Extract the local stack port (default 54321).
$port = 54321
if ($url -match ':(\d+)') { $port = [int]$Matches[1] }

if ($Usb) {
  # Locate adb (PATH first, then default Android SDK).
  $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
  if (-not $adb) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path $candidate) { $adb = $candidate }
  }
  if (-not $adb) { throw 'adb not found. Install Android platform-tools or add adb to PATH.' }

  $devices = (& $adb devices) | Select-String -Pattern '\tdevice$'
  if (-not $devices) {
    throw 'No USB device detected. Enable USB debugging, plug in, and accept the "Allow debugging" prompt on the phone.'
  }

  # Tunnel phone localhost:<port> -> PC localhost:<port> over USB.
  & $adb reverse "tcp:$port" "tcp:$port" | Out-Null
  Write-Host "USB: adb reverse tcp:$port active -- phone localhost tunnels to your PC." -ForegroundColor Green
  $HostIp = '127.0.0.1'
}

# Host rewrite for emulator / Wi-Fi (USB already forced 127.0.0.1).
$url = $url -replace '127\.0\.0\.1', $HostIp -replace 'localhost', $HostIp

Write-Host "Running mobile app against LOCAL stack: $url" -ForegroundColor Cyan
Write-Host "(prod build-apk.ps1 is untouched)" -ForegroundColor DarkGray

$flutterArgs = @(
  'run',
  "--dart-define=SUPABASE_URL=$url",
  "--dart-define=SUPABASE_ANON_KEY=$key"
)
if ($ExtraArgs) { $flutterArgs += $ExtraArgs }

Push-Location $MobileDir
try {
  & $Flutter @flutterArgs
} finally {
  Pop-Location
}
