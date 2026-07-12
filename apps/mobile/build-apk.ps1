<#
.SYNOPSIS
  Build the Nirman mobile APK with Supabase creds injected via --dart-define.

.DESCRIPTION
  A bare `flutter build apk` produces a DEAD-LOGIN apk: SUPABASE_URL /
  SUPABASE_ANON_KEY come from String.fromEnvironment (main.dart), and the
  asserts that guard them are stripped in release builds. This script reads
  those values from ../../.env.local and passes them, so login works.

  Any extra args are forwarded to `flutter build` (e.g. --split-per-abi,
  appbundle instead of apk by editing $Target).

.EXAMPLE
  ./build-apk.ps1
  ./build-apk.ps1 --split-per-abi
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

$ErrorActionPreference = 'Stop'

$Flutter  = 'C:\Users\rpxi1\flutter\bin\flutter.bat'
$MobileDir = $PSScriptRoot
$EnvFile  = Join-Path $MobileDir '..\..\.env.local'

if (-not (Test-Path $EnvFile)) {
  throw "Env file not found: $EnvFile  (expected nirman-crm/.env.local)"
}

# Parse KEY=VALUE lines, ignoring comments / blanks.
$env = @{}
foreach ($line in Get-Content $EnvFile) {
  $t = $line.Trim()
  if ($t -eq '' -or $t.StartsWith('#')) { continue }
  $i = $t.IndexOf('=')
  if ($i -lt 1) { continue }
  $env[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
}

$url = $env['SUPABASE_URL']
$key = $env['SUPABASE_ANON_KEY']

if ([string]::IsNullOrWhiteSpace($url)) { throw 'SUPABASE_URL missing in .env.local' }
if ([string]::IsNullOrWhiteSpace($key)) { throw 'SUPABASE_ANON_KEY missing in .env.local' }

Write-Host "Building release APK with SUPABASE_URL=$url" -ForegroundColor Cyan

$flutterArgs = @(
  'build', 'apk', '--release',
  "--dart-define=SUPABASE_URL=$url",
  "--dart-define=SUPABASE_ANON_KEY=$key"
)

# Operator support number (Story 9.6 paused screen). Optional keys in .env.local:
#   OPERATOR_PHONE_E164=9198XXXXXXXX      (digits only, for wa.me / tel:)
#   OPERATOR_PHONE_DISPLAY=+91 98XXX XXXXX
# Without them the app keeps the placeholder and HIDES the call/WhatsApp buttons.
$opPhone   = $env['OPERATOR_PHONE_E164']
$opDisplay = $env['OPERATOR_PHONE_DISPLAY']
if (-not [string]::IsNullOrWhiteSpace($opPhone)) {
  $flutterArgs += "--dart-define=OPERATOR_PHONE_E164=$opPhone"
  if (-not [string]::IsNullOrWhiteSpace($opDisplay)) {
    $flutterArgs += "--dart-define=OPERATOR_PHONE_DISPLAY=$opDisplay"
  }
} else {
  Write-Host 'WARNING: OPERATOR_PHONE_E164 not set in .env.local — paused screen will hide the recharge call/WhatsApp buttons (placeholder build).' -ForegroundColor Yellow
}
if ($ExtraArgs) { $flutterArgs += $ExtraArgs }

# Flutter writes warnings to stderr; with ErrorActionPreference=Stop PowerShell
# would treat those as terminating. Relax for the native call and judge success
# by exit code only.
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $Flutter @flutterArgs
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($code -ne 0) { throw "flutter build failed (exit $code)" }

$apk = Join-Path $MobileDir 'build\app\outputs\flutter-apk\app-release.apk'
Write-Host ''
Write-Host 'BUILD OK. APK:' -ForegroundColor Green
Write-Host "  $apk" -ForegroundColor Green
