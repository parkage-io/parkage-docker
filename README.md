# Parkage — Docker deployment

Self-hosted, S3-compatible object storage with a web console and analytics.
This branch contains **only what you need to run Parkage** — no source code.

| Port | Service |
|---|---|
| `9000` | S3 API (AWS SDKs, CLI, rclone, mc…) |
| `9001` | Web console |

## Install

**Option A — git (recommended: updates with `git pull`)**
```sh
git clone -b docker --single-branch https://github.com/bhuvanesh1998/parkage.git parkage
cd parkage
cp .env.example .env          # Windows: copy .env.example .env
mkdir -p data && sudo chown 65532:65532 data    # Linux only (container runs as non-root uid 65532)
docker compose up -d
```

**Option B — one-line installer**
```sh
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/bhuvanesh1998/parkage/docker/install.sh | sh
# Windows (Docker Desktop, PowerShell)
irm https://raw.githubusercontent.com/bhuvanesh1998/parkage/docker/install.ps1 | iex
```

Then open **http://localhost:9001** — the setup wizard creates your owner account and first access key.
The wizard asks for a one-time **setup code** so nobody else can claim your server. The installer prints it;
you can also find it with `docker compose logs parkage | grep "setup code"`.
Ports in use? Set `PARKAGE_S3_PORT` / `PARKAGE_CONSOLE_PORT` in `.env`.


**Option C - without Docker (native program)**
```sh
# Linux (systemd service) / macOS (launch agent)
curl -fsSL https://raw.githubusercontent.com/bhuvanesh1998/parkage/docker/install-native.sh | sh
```
```powershell
# Windows - PowerShell as Administrator (starts at boot as LOCAL SERVICE)
irm https://raw.githubusercontent.com/bhuvanesh1998/parkage/docker/install-native.ps1 | iex
```
Both installers download the program for your CPU (x86-64 or ARM64) from the latest release and refuse to install it if
it does not match `SHA256SUMS`. Or download a program from the Releases page yourself and run `parkage server`
(data is kept in `./data`). Service files are in [`native/`](native/).

## Update
```sh
git pull                      # newest compose/config from this branch
docker compose pull           # newest image
docker compose up -d          # restart — data in ./data is kept
```
Or enable automatic nightly updates: `docker compose --profile autoupdate up -d`.

## Migrate from MinIO
```sh
docker run --rm -e MIGRATE_SRC_SECRET=<minio-secret> -e MIGRATE_DST_SECRET=<parkage-secret> \
  ghcr.io/bhuvanesh1998/parkage:latest migrate \
  --src http://<minio-host>:9000 --src-key <minio-access-key> \
  --dst http://<parkage-host>:9000 --dst-key <parkage-access-key> --buckets bucket1,bucket2
```
Only reads from MinIO, verifies object counts and sizes, and is safe to re-run. Bucket policies stay private unless you add `--copy-policy`.
MinIO environment variables (`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `MINIO_DOMAIN`) are also accepted.

## Configuration
All settings are environment variables — see [`.env.example`](.env.example). Common ones:

| Variable | Purpose |
|---|---|
| `PARKAGE_ROOT_USER` / `PARKAGE_ROOT_PASSWORD` | Optional root account (otherwise use the setup wizard) |
| `PARKAGE_SETUP_CODE` | Your own setup code instead of a generated one |
| `PARKAGE_TRUSTED_PROXIES` | Only behind a reverse proxy: its IPs/CIDRs (or `private`), so real client IPs are used |
| `PARKAGE_CORS_ORIGINS` | Browser apps allowed to call the S3 API directly |
| `PARKAGE_S3_PUBLIC_URL`, `PARKAGE_CONSOLE_PUBLIC_URL` | Public URLs behind a reverse proxy |
| `PARKAGE_METRICS_TOKEN` | Enables Prometheus scraping at `/metrics` |
| `PARKAGE_DATA_PATH` | Host folder for data (default `./data`) |

## Backup
Your objects are plain files in `./data/<bucket>/…`; server state is in `./data/.parkage.sys/`.
Back up the whole `data` folder (stop the container or use a filesystem snapshot for consistency).

## Health & logs
```sh
docker compose ps
docker compose logs -f parkage
```
