#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/GMK67.app"
DEST_DIR="$HOME/Applications"
OPEN_APP=1

usage() {
  cat <<'USAGE'
Usage: Scripts/install-app.sh [--dest DIR] [--no-open]

Installs dist/GMK67.app into ~/Applications by default.
Run Scripts/build-app.sh first if the app bundle does not exist.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      DEST_DIR="$2"
      shift 2
      ;;
    --no-open)
      OPEN_APP=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  echo "Build it first with: Scripts/build-app.sh" >&2
  exit 1
fi

DEST="$DEST_DIR/GMK67.app"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "Installed $DEST"
if [[ "$OPEN_APP" -eq 1 ]]; then
  open "$DEST"
fi
