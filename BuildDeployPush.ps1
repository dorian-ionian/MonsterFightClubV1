#=============================================================================
# BuildDeployPush.ps1 - the standard MonsterFightClub workflow:
#
#   1. Compile with ucc make
#   2. MOVE the built .u to ..\Mods\System (no duplicate copy left behind)
#   3. Deploy the .u.uz2 to the web redirect
#   4. Sync the modified source to the git repo and push to GitHub
#
# Usage (from System\):
#   powershell -ExecutionPolicy Bypass -File .\BuildDeployPush.ps1
#
# For other projects:
#   powershell -ExecutionPolicy Bypass -File .\BuildDeployPush.ps1 `
#       -Package MyMod -GameRoot "C:\path\to\game" -RepoDir "C:\Projects\MyMod"
#
# Options:
#   -SkipDeploy   compile + move + push only
#   -SkipPush     compile + move + deploy only
#=============================================================================
param(
    [string]$Package = "MonsterFightClub",
    [string]$GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\Unreal Tournament 2004",
    [string]$RepoDir = "",          # default: C:\Projects\<Package>
    [switch]$SkipDeploy,
    [switch]$SkipPush
)

$ErrorActionPreference = "Stop"
$SystemDir = Join-Path $GameRoot "System"
$ModsDir   = Join-Path $GameRoot "Mods\System"
$SourceDir = Join-Path $GameRoot "$Package\Classes"   # .uc source lives here
if($RepoDir -eq "")
{
    $RepoDir = "C:\Projects\$Package"
}

Write-Host "=== MFC workflow: $Package ==="
Write-Host "GameRoot : $GameRoot"
Write-Host "RepoDir  : $RepoDir"

#--- 1. Kill anything holding the package / compiler ---
Write-Host "`n[1/5] Stopping ucc/ut2004 processes..."
Get-Process | Where-Object { $_.Name -match 'ucc|ut2004' } | ForEach-Object {
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

#--- 2. Compile ---
Write-Host "[2/5] Compiling (ucc make)..."
Set-Location $SystemDir
# Remove the built .u everywhere BEFORE compiling - ucc make skips the
# build if it finds an up-to-date .u in any search path (including the
# Mods\System copy from the previous run).
Remove-Item "$SystemDir\$Package.u" -Force -ErrorAction SilentlyContinue
Remove-Item "$ModsDir\$Package.u" -Force -ErrorAction SilentlyContinue
Remove-Item "$ModsDir\$Package.u.uz2" -Force -ErrorAction SilentlyContinue
$out = cmd /c "ucc make 2>&1" | Select-Object -Last 3
$out
if(-not (Test-Path "$SystemDir\$Package.u"))
{
    Write-Error "Compile failed - no $Package.u produced"
    exit 1
}
Write-Host "Compiled OK: $SystemDir\$Package.u"

#--- 3. Move the .u to Mods\System (no duplicate copy) ---
Write-Host "[3/5] Moving $Package.u -> $ModsDir ..."
if(-not (Test-Path $ModsDir))
{
    New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
}
Remove-Item "$ModsDir\$Package.u" -Force -ErrorAction SilentlyContinue
Remove-Item "$ModsDir\$Package.u.uz2" -Force -ErrorAction SilentlyContinue
Move-Item "$SystemDir\$Package.u" "$ModsDir\$Package.u" -Force
# clean stale uz2 from System (deploy will recreate it in Mods\System)
Remove-Item "$SystemDir\$Package.u.uz2" -Force -ErrorAction SilentlyContinue
Write-Host "Moved. System copy: $(-not (Test-Path "$SystemDir\$Package.u"))"

#--- 4. Deploy to redirect ---
if(-not $SkipDeploy)
{
    Write-Host "[4/5] Deploying to redirect..."
    powershell -ExecutionPolicy Bypass -File "$SystemDir\deploy_redirect.ps1" `
        -Package $Package -SourceDir $ModsDir
}
else
{
    Write-Host "[4/5] SKIPPED deploy (-SkipDeploy)"
}

#--- 5. Sync source to repo and push ---
if(-not $SkipPush)
{
    Write-Host "[5/5] Syncing source to repo + pushing..."
    if(-not (Test-Path $RepoDir))
    {
        Write-Warning "Repo dir not found: $RepoDir - skipping push"
        exit 0
    }
    Set-Location $RepoDir

    # sync the source files
    if(Test-Path $SourceDir)
    {
        New-Item -ItemType Directory -Path "$RepoDir\Classes" -Force | Out-Null
        Copy-Item "$SourceDir\*.uc" "$RepoDir\Classes\" -Force
    }
    foreach($f in @("$SystemDir\$Package.ucl", "$SystemDir\$Package.ini"))
    {
        if(Test-Path $f)
        {
            Copy-Item $f $RepoDir -Force
        }
    }
    # redact secrets when syncing the server ini / launcher
    if(Test-Path "$SystemDir\UT2004MFC.ini")
    {
        (Get-Content "$SystemDir\UT2004MFC.ini" -Raw) `
            -replace 'AdminPassword=.*','AdminPassword=CHANGE_ME' `
            -replace 'GamePassword=.*','GamePassword=CHANGE_ME' `
            -replace 'SavedPasswords=.*','SavedPasswords=' `
            | Set-Content "$RepoDir\UT2004MFC.ini" -Encoding ASCII
    }
    if(Test-Path "$SystemDir\RunServerMFC.bat")
    {
        (Get-Content "$SystemDir\RunServerMFC.bat" -Raw) `
            -replace 'GamePassword=[^ ?]*','GamePassword=CHANGE_ME' `
            | Set-Content "$RepoDir\RunServerMFC.bat" -Encoding ASCII
    }

    # git add/commit/push
    git add -A
    $diff = git diff --cached --stat
    if($diff)
    {
        $msg = "Build sync: $Package " + (Get-Date -Format 'yyyy-MM-dd HH:mm')
        git commit -m $msg | Out-Null
        git push 2>&1 | ForEach-Object { $_ }
        Write-Host "Pushed to GitHub."
    }
    else
    {
        Write-Host "No source changes to push (working tree clean)."
    }
}
else
{
    Write-Host "[5/5] SKIPPED push (-SkipPush)"
}

Write-Host "`n=== Workflow complete ==="
