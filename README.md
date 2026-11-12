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
git clone https://github.com/parkage-io/parkage-docker.git parkage
cd parkage
cp .env.example .env          # Windows: copy .env.example .env
mkdir -p data && sudo chown 65532:65532 data    # Linux only (container runs as non-root uid 65532)
docker compose up -d
```

**Option B — one-line installer**
```sh
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/parkage-io/parkage-docker/main/install.sh | sh
# Windows (Docker Desktop, PowerShell)
irm https://raw.githubusercontent.com/parkage-io/parkage-docker/main/install.ps1 | iex
```

Then open **http://localhost:9001** — the setup wizard creates your owner account and first access key.
The wizard asks for a one-time **setup code** so nobody else can claim your server. The installer prints it;
you can also find it with `docker compose logs parkage | grep "setup code"`.
Ports in use? Set `PARKAGE_S3_PORT` / `PARKAGE_CONSOLE_PORT` in `.env`.


## Update
```sh
git pull                      # newest compose/config from this repository
docker compose pull           # newest image
docker compose up -d          # restart — data in ./data is kept
```
Or enable automatic nightly updates: `docker compose --profile autoupdate up -d`.

## Migrate from MinIO
```sh
docker run --rm -e MIGRATE_SRC_SECRET=<minio-secret> -e MIGRATE_DST_SECRET=<parkage-secret> \
  ghcr.io/parkage-io/parkage:latest migrate \
  --src http://<minio-host>:9000 --src-key <minio-access-key> \
  --dst http://<parkage-host>:9000 --dst-key <parkage-access-key> --buckets bucket1,bucket2
```
Only reads from MinIO, verifies object counts and sizes, and is safe to re-run. Bucket policies stay private unless you add `--copy-policy`.
MinIO environment variables (`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `MINIO_DOMAIN`) are also accepted.

## Sync, verify and inventory (S3-style data tools)
Copy buckets between Parkage and any S3-compatible service (AWS S3, MinIO, another Parkage), then prove the copy is complete.
In the console: **Data tools** (administrators). From the command line, run the tools inside the container, so `127.0.0.1:9000` is this server:

```sh
export PARKAGE_SRC_KEY=<old-access-key> PARKAGE_SRC_SECRET=<old-secret>    # the source service
export PARKAGE_DST_KEY=<parkage-access-key> PARKAGE_DST_SECRET=<parkage-secret>
E="-e PARKAGE_SRC_KEY -e PARKAGE_SRC_SECRET -e PARKAGE_DST_KEY -e PARKAGE_DST_SECRET"

docker compose exec $E parkage parkage sync   https://old.example.com/photos http://127.0.0.1:9000/photos --dry-run
docker compose exec $E parkage parkage sync   https://old.example.com/photos http://127.0.0.1:9000/photos
docker compose exec $E parkage parkage verify https://old.example.com/photos http://127.0.0.1:9000/photos --checksum --report /data/diff.csv
docker compose exec $E parkage parkage batch  --op copy --manifest /data/diff.csv https://old.example.com/photos http://127.0.0.1:9000/photos
```

| Command | What it does |
|---|---|
| `sync SRC DST` | Copies new and changed objects with metadata and tags; skips identical ones. `--delete`, `--dry-run`, `--include` / `--exclude` (as `aws s3 sync`) |
| `verify A B` | Object-by-object cross-check: missing, size, ETag, content with `--checksum`. Exit code 0 = identical |
| `inventory SRC` | S3 Inventory report in the AWS format (CSV + `manifest.json`) |
| `batch --op copy\|delete\|tag` | Runs one operation on exactly the objects in an inventory or report (`delete` needs `--confirm`) |

A bare `-e NAME` passes the variable from your shell without putting the secret on the command line. Reports written to `/data/<file>.csv` appear in `./data` on the host; delete them when done.
Scheduled daily or weekly inventory reports are set per bucket in the console under *Bucket settings*.
Verify with `--checksum` before you delete a migration source.

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

## Security
- No default passwords: the setup wizard needs a one-time code from the server log.
- Buckets are private by default; give each app a bucket-scoped access key.
- The container runs as a non-root user on a read-only filesystem with no capabilities.
- Report a vulnerability privately: open a GitHub security advisory on this repository (Security -> Report a vulnerability).

## Links
Website and docs: https://parkage.io - Download page: https://parkage.io/download - Plans: https://parkage.io/pricing
