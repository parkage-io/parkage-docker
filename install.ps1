# Parkage installer for Windows (Docker Desktop):
#   irm https://raw.githubusercontent.com/bhuvanesh1998/parkage/docker/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$Image  = if ($env:PARKAGE_IMAGE) { $env:PARKAGE_IMAGE } else { 'ghcr.io/bhuvanesh1998/parkage:latest' }
$Dir    = if ($env:PARKAGE_DIR) { $env:PARKAGE_DIR } else { Join-Path $HOME 'parkage' }
$S3Port = if ($env:PARKAGE_S3_PORT) { $env:PARKAGE_S3_PORT } else { '9000' }
$UiPort = if ($env:PARKAGE_CONSOLE_PORT) { $env:PARKAGE_CONSOLE_PORT } else { '9001' }

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop is required: https://docs.docker.com/desktop/install/windows-install/' }
docker compose version | Out-Null

foreach ($p in @($S3Port, $UiPort)) {
  if (Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) {
    throw "Port $p is in use. Set `$env:PARKAGE_S3_PORT / `$env:PARKAGE_CONSOLE_PORT to free ports and re-run."
  }
}

Say "Installing Parkage into $Dir"
New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'data') | Out-Null
Set-Location $Dir
@"
name: parkage
services:
  parkage:
    image: $Image
    container_name: parkage
    restart: unless-stopped
    env_file: .env
    ports: ["${S3Port}:9000", "${UiPort}:9001"]
    volumes: ["parkage-data:/data"]
    read_only: true
    security_opt: ["no-new-privileges:true"]
    cap_drop: [ALL]
    tmpfs: [/tmp]
volumes:
  parkage-data: {}
"@ | Set-Content -Encoding utf8 docker-compose.yml
if (-not (Test-Path .env)) {
  "PARKAGE_ROOT_USER=`nPARKAGE_ROOT_PASSWORD=`nPARKAGE_REGION=us-east-1" | Set-Content -Encoding utf8 .env
}

Say "Pulling $Image"
docker compose pull
docker compose up -d

Say 'Waiting for the server...'
$ok = $false
for ($i = 0; $i -lt 30; $i++) {
  try { Invoke-WebRequest -UseBasicParsing "http://localhost:$S3Port/minio/health/live" -TimeoutSec 2 | Out-Null; $ok = $true; break } catch { Start-Sleep 1 }
}
if (-not $ok) { throw "Server did not start. Check: docker compose logs (in $Dir)" }

Write-Host "`nParkage is running!`n" -ForegroundColor Green
Write-Host "  Web console : http://localhost:$UiPort   (open it to create your owner account)"
Write-Host "  S3 endpoint : http://localhost:$S3Port"
Write-Host "  Update      : cd $Dir; docker compose pull; docker compose up -d`n"
Start-Process "http://localhost:$UiPort"
