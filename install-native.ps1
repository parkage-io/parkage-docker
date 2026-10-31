# Parkage native installer for Windows (no Docker). Run in an elevated PowerShell:
#   irm https://raw.githubusercontent.com/bhuvanesh1998/parkage/docker/install-native.ps1 | iex
# Installs to Program Files, keeps data in ProgramData\Parkage and starts Parkage at boot as the
# low-privilege LOCAL SERVICE account (a scheduled task), so it keeps running without anyone signed in.
$ErrorActionPreference = 'Stop'
$Releases = if ($env:PARKAGE_RELEASES) { $env:PARKAGE_RELEASES } else { 'https://github.com/bhuvanesh1998/parkage/releases/latest/download' }
function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Please run PowerShell as Administrator.'
}
$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$Pkg = "parkage-windows-$Arch.zip"
$Tmp = Join-Path $env:TEMP ("parkage-" + [guid]::NewGuid())
New-Item -ItemType Directory $Tmp | Out-Null
try {
  Say "Downloading $Pkg"
  Invoke-WebRequest -UseBasicParsing "$Releases/$Pkg" -OutFile "$Tmp\$Pkg"
  Invoke-WebRequest -UseBasicParsing "$Releases/SHA256SUMS" -OutFile "$Tmp\SHA256SUMS"
  Say 'Verifying checksum'
  $want = (Select-String -Path "$Tmp\SHA256SUMS" -Pattern " $([regex]::Escape($Pkg))$").Line.Split(' ')[0]
  $got = (Get-FileHash "$Tmp\$Pkg" -Algorithm SHA256).Hash.ToLower()
  if (-not $want -or $want -ne $got) { throw 'Checksum mismatch - the download is corrupt or was tampered with.' }
  Expand-Archive "$Tmp\$Pkg" -DestinationPath $Tmp

  $Bin = Join-Path $env:ProgramFiles 'Parkage'
  $Data = Join-Path $env:ProgramData 'Parkage'
  New-Item -ItemType Directory -Force $Bin, "$Data\data", "$Data\logs" | Out-Null
  Unregister-ScheduledTask -TaskName 'Parkage' -Confirm:$false -ErrorAction SilentlyContinue
  Get-Process parkage -ErrorAction SilentlyContinue | Stop-Process -Force
  Copy-Item "$Tmp\parkage.exe" "$Bin\parkage.exe" -Force
  # only LOCAL SERVICE and administrators may touch the data
  icacls $Data /inheritance:r /grant:r '*S-1-5-19:(OI)(CI)M' '*S-1-5-32-544:(OI)(CI)F' 'SYSTEM:(OI)(CI)F' | Out-Null

  Say 'Registering the Parkage startup task'
  $cmd = "set PARKAGE_DATA_DIR=$Data\data&& `"$Bin\parkage.exe`" server >> `"$Data\logs\parkage.log`" 2>&1"
  $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c $cmd"
  $trigger = New-ScheduledTaskTrigger -AtStartup
  $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\LOCAL SERVICE' -LogonType ServiceAccount
  $settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName 'Parkage' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Parkage S3-compatible object storage' | Out-Null
  Start-ScheduledTask -TaskName 'Parkage'

  $ok = $false
  for ($i = 0; $i -lt 20; $i++) { try { Invoke-WebRequest -UseBasicParsing http://localhost:9000/minio/health/live -TimeoutSec 2 | Out-Null; $ok = $true; break } catch { Start-Sleep 1 } }
  if (-not $ok) { throw "Parkage did not start. See $Data\logs\parkage.log" }
  Write-Host "`nParkage is running!`n" -ForegroundColor Green
  Write-Host '  Web console : http://localhost:9001'
  Write-Host '  S3 endpoint : http://localhost:9000'
  $code = Select-String -Path "$Data\logs\parkage.log" -Pattern 'setup code: ([A-Z0-9-]+)' | Select-Object -Last 1
  if ($code) { Write-Host "  Setup code  : $($code.Matches[0].Groups[1].Value)   (the setup wizard asks for it)" -ForegroundColor Yellow }
  Write-Host "  Data        : $Data\data"
  Write-Host "  Update      : re-run this installer (data is kept)`n"
  Start-Process 'http://localhost:9001'
} finally { Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue }
