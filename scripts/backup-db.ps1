<#
.SYNOPSIS
  Dump the production Supabase database to a timestamped local file.

.DESCRIPTION
  Free-tier Supabase has no PITR — this is the backup story. Dumps roles+schema
  and data separately (supabase db dump --linked) into backups/ (gitignored).
  Keeps the newest 14 dumps, deletes older ones.

  RESTORE (practice this once — see backups/RESTORE.md, created on first run):
    1. supabase start                      # local Docker stack
    2. supabase db reset --local           # clean slate (migrations applied)
    3. psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
         -f backups/<stamp>-data.sql       # data only; schema comes from migrations

.EXAMPLE
  ./scripts/backup-db.ps1
#>
$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path $PSScriptRoot -Parent
$BackupDir = Join-Path $RepoRoot 'backups'
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory $BackupDir | Out-Null }

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$schema = Join-Path $BackupDir "$stamp-schema.sql"
$data   = Join-Path $BackupDir "$stamp-data.sql"

Set-Location $RepoRoot

Write-Host "Dumping schema -> $schema" -ForegroundColor Cyan
supabase db dump --linked -f $schema
if ($LASTEXITCODE -ne 0) { throw "schema dump failed (exit $LASTEXITCODE)" }

Write-Host "Dumping data -> $data" -ForegroundColor Cyan
supabase db dump --linked --data-only -f $data
if ($LASTEXITCODE -ne 0) { throw "data dump failed (exit $LASTEXITCODE)" }

# Retention: newest 14 dump pairs (28 files)
Get-ChildItem $BackupDir -Filter '*.sql' |
  Sort-Object Name -Descending |
  Select-Object -Skip 28 |
  Remove-Item -Force

$restoreDoc = Join-Path $BackupDir 'RESTORE.md'
if (-not (Test-Path $restoreDoc)) {
  @'
# Restore drill

1. `supabase start` (local Docker stack)
2. `supabase db reset --local` — clean DB with all file-based migrations applied
3. `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f backups/<stamp>-data.sql`
4. Sanity: `SELECT count(*) FROM public.leads;` should match prod at dump time.

Schema dump (`<stamp>-schema.sql`) is a belt-and-braces copy; normal restores
use migrations + data dump. Never point a restore at the linked PROD database.
'@ | Out-File $restoreDoc -Encoding utf8
}

Write-Host ''
Write-Host "BACKUP OK:" -ForegroundColor Green
Get-ChildItem $BackupDir -Filter "$stamp*" | ForEach-Object { Write-Host "  $($_.Name)  $([math]::Round($_.Length/1KB)) KB" -ForegroundColor Green }
