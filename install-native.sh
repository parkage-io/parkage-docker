#!/usr/bin/env sh
# Parkage native installer (no Docker) for Linux and macOS:
#   curl -fsSL https://raw.githubusercontent.com/bhuvanesh1998/parkage/docker/install-native.sh | sh
# Linux: installs a hardened systemd service (data in /var/lib/parkage). Needs sudo.
# macOS: installs a launch agent for your user (data in ~/Library/Application Support/Parkage).
set -eu

RELEASES="${PARKAGE_RELEASES:-https://github.com/bhuvanesh1998/parkage/releases/latest/download}"
say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }
need curl; need tar

case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=darwin ;; *) die "unsupported OS $(uname -s) - use Docker instead" ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) die "unsupported CPU $(uname -m)" ;; esac
PKG="parkage-$OS-$ARCH.tar.gz"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

say "Downloading $PKG"
curl -fsSL -o "$TMP/$PKG" "$RELEASES/$PKG" || die "download failed: $RELEASES/$PKG"
curl -fsSL -o "$TMP/SHA256SUMS" "$RELEASES/SHA256SUMS" || die "could not download checksums"
say "Verifying checksum"
if command -v sha256sum >/dev/null 2>&1; then SUM="sha256sum -c"; else SUM="shasum -a 256 -c"; fi   # Linux / macOS
( cd "$TMP" && grep " $PKG\$" SHA256SUMS > want.sum && $SUM want.sum ) >/dev/null 2>&1 \
  || die "checksum mismatch - the download is corrupt or was tampered with"
tar -xzf "$TMP/$PKG" -C "$TMP"

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
say "Installing /usr/local/bin/parkage"
$SUDO install -m 0755 "$TMP/parkage" /usr/local/bin/parkage

if [ "$OS" = linux ]; then
  command -v systemctl >/dev/null 2>&1 || die "systemd not found - run /usr/local/bin/parkage server yourself"
  id parkage >/dev/null 2>&1 || $SUDO useradd --system --home /var/lib/parkage --shell /usr/sbin/nologin parkage
  $SUDO install -d -m 0750 -o parkage -g parkage /var/lib/parkage
  $SUDO install -d -m 0750 /etc/parkage
  [ -f /etc/parkage/parkage.env ] || printf '# Parkage settings (see https://parkage.io/download)\n#PARKAGE_ROOT_USER=\n#PARKAGE_ROOT_PASSWORD=\n' | $SUDO tee /etc/parkage/parkage.env >/dev/null
  $SUDO chmod 0640 /etc/parkage/parkage.env
  $SUDO install -m 0644 "$TMP/parkage.service" /etc/systemd/system/parkage.service
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now parkage
  sleep 2
  CODE=$($SUDO journalctl -u parkage -n 50 --no-pager 2>/dev/null | grep -o 'setup code: [A-Z0-9-]*' | tail -n 1 | cut -d' ' -f3 || true)
  UPDATE="re-run this installer (data is kept)"
else
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/Parkage" "$HOME/Library/Application Support/Parkage"
  PL="$HOME/Library/LaunchAgents/io.parkage.server.plist"
  sed "s|__HOME__|$HOME|g" "$TMP/io.parkage.server.plist" > "$PL"
  launchctl unload "$PL" 2>/dev/null || true
  launchctl load -w "$PL"
  sleep 2
  CODE=$(grep -o 'setup code: [A-Z0-9-]*' "$HOME/Library/Logs/Parkage/parkage.log" 2>/dev/null | tail -n 1 | cut -d' ' -f3 || true)
  UPDATE="re-run this installer (data is kept)"
fi

/usr/local/bin/parkage healthcheck >/dev/null 2>&1 || sleep 3
printf '\n\033[1;32mParkage %s is running!\033[0m\n\n' "$(/usr/local/bin/parkage version | cut -d' ' -f2)"
printf '  Web console : http://localhost:9001\n  S3 endpoint : http://localhost:9000\n'
[ -n "${CODE:-}" ] && printf '  Setup code  : \033[1m%s\033[0m   (the setup wizard asks for it)\n' "$CODE"
printf '  Update      : %s\n\n' "$UPDATE"
