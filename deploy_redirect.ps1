#=============================================================================
# deploy_redirect.ps1 - compress a package with ucc and upload the .uz2 to
# the redirect server (NFOservers redirect).
#
# Usage:  powershell -ExecutionPolicy Bypass -File deploy_redirect.ps1 -Package DestructibleMapsV1
#
# Reads credentials from redirect_creds.txt (same folder, one per line):
#   Line 1: FTP host            (e.g. ftp.tur.site.nfoservers.com)
#   Line 2: FTP username
#   Line 3: FTP password
#   Line 4: remote folder       (e.g. redirect2 - leave empty for root)
# If the file is missing, the script prompts for the values (or use
# -Host/-User/-Pass/-Remote as parameters).
#
# The .uz2 is uploaded to http://<host>/<remote>/<Package>.u.uz2 (the same
# URL the server's RedirectToURL points at).
#=============================================================================
param(
    [Parameter(Mandatory=$true)][string]$Package,
    [string]$Ext = "u",            # u (script) or uax (sound) package extension
    [string]$SourceDir = "",       # folder containing the package file (default: this script's folder)
    [string]$HostAddr = "",
    [string]$User = "",
    [string]$Pass = "",
    [string]$Remote = "",
    [string]$HttpBase = ""
)

$ErrorActionPreference = "Stop"
$SystemDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if($SourceDir -eq "")
{
    $SourceDir = $SystemDir
}
$SrcFile = Join-Path $SourceDir "$Package.$Ext"
$Uz2File = Join-Path $SourceDir "$Package.$Ext.uz2"

#--- 1. Compress with ucc (skips if the .uz2 is newer than the source) ---
if(Test-Path $SrcFile)
{
    $uTime = (Get-Item $SrcFile).LastWriteTime
    $zTime = if(Test-Path $Uz2File) { (Get-Item $Uz2File).LastWriteTime } else { [datetime]::MinValue }
    if($zTime -lt $uTime)
    {
        Write-Host "Compressing $SrcFile -> $($Package).$Ext.uz2 ..."
        # ucc resolves relative paths from its working dir (System), so pass
        # a path relative to System when the source lives elsewhere.
        $RelSrc = $SrcFile
        if($SourceDir -ne $SystemDir)
        {
            # Manual relative path (Path.GetRelativePath needs .NET Core).
            # Walk up from SystemDir to the common root, then down to the
            # source file. e.g. System\ -> ..\Mods\System\X.u
            $sParts = $SystemDir.TrimEnd('\').Split('\')
            $fParts = $SrcFile.TrimEnd('\').Split('\')
            $common = 0
            while($common -lt $sParts.Length -and $common -lt $fParts.Length -and
                  $sParts[$common] -eq $fParts[$common])
            {
                $common++
            }
            $RelSrc = ("..\" * ($sParts.Length - $common)) +
                      (($fParts[$common..($fParts.Length-1)] -join '\'))
        }
        & cmd /c "ucc.exe compress $RelSrc" | Out-Null
        if(-not (Test-Path $Uz2File))
        {
            Write-Error "ucc compress failed - no $($Package).$Ext.uz2 produced"
            exit 1
        }
    }
    else
    {
        Write-Host "Skipping compress - $($Package).$Ext.uz2 is already up to date"
    }
}
else
{
    Write-Error "Source file not found: $SrcFile"
    exit 1
}

#--- 2. Load credentials ---
$CredsFile = Join-Path $SystemDir "redirect_creds.txt"
if(-not $HostAddr -or -not $User -or -not $Pass)
{
    if(Test-Path $CredsFile)
    {
        $lines = Get-Content $CredsFile | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") }
        if($lines.Count -ge 3)
        {
            if(-not $HostAddr){ $HostAddr = $lines[0].Trim() }
            if(-not $User){ $User = $lines[1].Trim() }
            if(-not $Pass){ $Pass = $lines[2].Trim() }
            if(-not $Remote -and $lines.Count -ge 4){ $Remote = $lines[3].Trim() }
            if(-not $HttpBase -and $lines.Count -ge 5){ $HttpBase = $lines[4].Trim() }
        }
    }
}

if(-not $HostAddr -or -not $User -or -not $Pass)
{
    Write-Host ""
    Write-Host "Missing FTP credentials. Create $CredsFile with:"
    Write-Host "   line 1: FTP host"
    Write-Host "   line 2: FTP username"
    Write-Host "   line 3: FTP password"
    Write-Host "   line 4: remote folder (optional)"
    Write-Host "(or pass -HostAddr/-User/-Pass on the command line)"
    exit 1
}

#--- 3. Upload via FTP ---
$FtpHost = $HostAddr
if(-not $FtpHost.ToLower().StartsWith("ftp://"))
{
    $FtpHost = "ftp://" + $FtpHost
}

$RemotePath = $Remote
if($RemotePath -eq "")
{
    $RemotePath = "/"
}
if(-not $RemotePath.EndsWith("/"))
{
    $RemotePath = $RemotePath + "/"
}
if(-not $RemotePath.StartsWith("/"))
{
    $RemotePath = "/" + $RemotePath
}

$FtpUrl = $FtpHost + $RemotePath + [System.IO.Path]::GetFileName($Uz2File)
Write-Host "Uploading $Uz2File -> $FtpUrl ..."

$req = [System.Net.FtpWebRequest]::Create($FtpUrl)
$req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
$req.Credentials = New-Object System.Net.NetworkCredential($User, $Pass)
$req.KeepAlive = $false
$req.UseBinary = $true

try
{
    $content = [System.IO.File]::ReadAllBytes($Uz2File)
    $stream = $req.GetRequestStream()
    $stream.Write($content, 0, $content.Length)
    $stream.Close()
    $resp = $req.GetResponse()
    Write-Host ("Upload OK: " + $resp.StatusDescription)
    $resp.Close()
}
catch
{
    Write-Error ("Upload failed: " + $_.Exception.Message)
    exit 1
}

#--- 4. Verify the redirect URL is reachable (HTTP GET) ---
#The FTP path and the HTTP URL differ (FTP root is the server's home, but the
#file is served from the RedirectToURL path) - so the HTTP base comes from the
#5th creds line / -HttpBase param, NOT from the FTP remote folder.
if($HttpBase -eq "")
{
    $HttpBase = "http://" + $HostAddr.TrimEnd('/') + "/"
}
if(-not $HttpBase.EndsWith("/"))
{
    $HttpBase = $HttpBase + "/"
}
$HttpUrl = $HttpBase + [System.IO.Path]::GetFileName($Uz2File)
try
{
    $wc = New-Object System.Net.WebClient
    $len = $wc.DownloadData($HttpUrl).Length
    Write-Host ("Redirect URL OK: " + $HttpUrl + " (" + $len + " bytes served)")
}
catch
{
    Write-Host ("WARNING: could not verify redirect URL (may need a moment to propagate): " + $HttpUrl)
}

Write-Host "Done."
