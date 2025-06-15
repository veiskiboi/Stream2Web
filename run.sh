#!/bin/bash
set -euo pipefail

# Base directory of repo (this script should be in repo root)
BASE_DIR="$(dirname "$0")"

# Run each script in background from BASE_DIR
bash "$BASE_DIR/scripts/sender.sh" &
bash "$BASE_DIR/scripts/web-setup.sh" &
bash "$BASE_DIR/scripts/receiver.sh" &
bash "$BASE_DIR/scripts/mp4compiler.sh" &

echo "All services started. Logs are in respective LOG_DIRs as configured in .env."

wait
