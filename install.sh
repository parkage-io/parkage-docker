#!/usr/bin/env sh
# Parkage one-line installer (Linux / macOS):
#   curl -fsSL https://raw.githubusercontent.com/bhuvanesh1998/parkage/docker/install.sh | sh
set -eu

IMAGE="${PARKAGE_IMAGE:-ghcr.io/bhuvanesh1998/parkage:latest}"
DIR="${PARKAGE_DIR:-$HOME/parkage}"
S3_PORT="${PARKAGE_S3_PORT:-9000}"
UI_PORT="${PARKAGE_CONSOLE_PORT:-9001}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker is required: https://docs.docker.com/get-docker/"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required (docker compose)."

for p in "$S3_PORT" "$UI_PORT"; do
  if (command -v ss >/dev/null 2>&1 && ss -ltn | grep -q ":$p ") ; then
    die "Port $p is in use. Re-run with PARKAGE_S3_PORT / PARKAGE_CONSOLE_PORT set to free ports."
  fi
done

say "Installing Parkage into $DIR"
mkdir -p "$DIR/data"
cd "$DIR"
# the container runs as uid 65532 (non-root)
chown 65532:65532 data 2>/dev/null || sudo chown 65532:65532 data 2>/dev/null || \
  die "Could not hand $DIR/data to the container user. Run: sudo chown 65532:65532 $DIR/data  (never chmod 777)"

cat > docker-compose.yml <<EOF
name: parkage
services:
  parkage:
    image: $IMAGE
    container_name: parkage
    restart: unless-stopped
    env_file: .env
    ports: ["$S3_PORT:9000", "$UI_PORT:9001"]
    volumes: ["./data:/data"]
    read_only: true
    security_opt: ["no-new-privileges:true"]
    cap_drop: [ALL]
    tmpfs: [/tmp]
EOF

[ -f .env ] || cat > .env <<EOF
# Leave empty to create the owner account in the browser.
PARKAGE_ROOT_USER=
PARKAGE_ROOT_PASSWORD=
PARKAGE_REGION=us-east-1
EOF

say "Pulling $IMAGE"
docker compose pull
docker compose up -d

HOST=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -n "${HOST:-}" ] || HOST=localhost
say "Waiting for the server to become healthy..."
i=0; until curl -fsS "http://localhost:$S3_PORT/minio/health/live" >/dev/null 2>&1; do
  i=$((i+1)); [ $i -gt 30 ] && die "Server did not start. Check: docker compose -f $DIR/docker-compose.yml logs"
  sleep 1
done

printf '\n\033[1;32mParkage is running!\033[0m\n\n'
printf '  Web console : http://%s:%s   (open it to create your owner account)\n' "$HOST" "$UI_PORT"
CODE=$(docker compose logs parkage 2>/dev/null | grep -o 'setup code: [A-Z0-9-]*' | tail -n 1 | cut -d' ' -f3)
[ -n "${CODE:-}" ] && printf '  Setup code  : \033[1m%s\033[0m   (the wizard asks for it)\n' "$CODE"
printf '  S3 endpoint : http://%s:%s\n' "$HOST" "$S3_PORT"
printf '  Data folder : %s/data\n\n' "$DIR"
printf '  Update      : cd %s && docker compose pull && docker compose up -d\n\n' "$DIR"
