#=============================================================================
# backup_mfc_ini.ps1 - snapshot the FULL MonsterFightClub.ini before ANY test
# or server run that might modify it (ucc server rewrites the ini on exit!).
#
# Usage:  powershell -ExecutionPolicy Bypass -File backup_mfc_ini.ps1
#
# Creates:
#   MonsterFightClub.ini.bak_full          <- always the latest known-good ini
#   MonsterFightClub.ini.bak_<timestamp>   <- dated history copy
#=============================================================================
$SystemDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src = Join-Path $SystemDir "MonsterFightClub.ini"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path $Src)) {
    Write-Error "No MonsterFightClub.ini found at $Src"
    exit 1
}

# Always-latest backup (overwrite)
$Latest = Join-Path $SystemDir "MonsterFightClub.ini.bak_full"
Copy-Item $Src $Latest -Force

# Dated history copy (keep)
$Dated = Join-Path $SystemDir "MonsterFightClub.ini.bak_$Stamp"
Copy-Item $Src $Dated -Force

$mt = (Select-String -Path $Src -Pattern '^MonsterTable=' | Measure-Object).Count
$cbn = (Select-String -Path $Src -Pattern '^CustomBotNames' | Measure-Object).Count
Write-Host "Backed up MonsterFightClub.ini -> $Latest"
Write-Host "                       dated  -> $Dated"
Write-Host "Verified: $mt MonsterTable entries, $cbn CustomBotNames"
