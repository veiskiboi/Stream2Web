#!/bin/bash
set -euo pipefail

# Prevent multiple instances
SCRIPT_NAME=$(basename "$0")
LOCK_FILE="/tmp/${SCRIPT_NAME%.sh}.lock"

# Check for running instances using ps aux
if ps aux | grep -E "bash .*$SCRIPT_NAME" | grep -v "$$" | grep -v "grep" >/dev/null; then
  log "ERROR: Another instance of $SCRIPT_NAME is already running"
  exit 1
fi

# Acquire lock
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "ERROR: Failed to acquire lock for $SCRIPT_NAME"
  exit 1
fi

# Cleanup lock file on exit
cleanup() {
  if [ -f "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE" && log "Removed lock file $LOCK_FILE"
  fi
}
trap cleanup SIGINT SIGTERM EXIT

check_dependencies() {
  local deps=(ffmpeg ps)
  for cmd in "${Deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "ERROR: Required command '$cmd' not found. Please install it."
      exit 1
    fi
  done
}

check_dependencies

# Load env vars from repo root .env
set -a
source "$(dirname "$0")/../.env"
set +a

# Ensure required directories exist
mkdir -p "$HLS_DIR" "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$LOG_DIR/restream.log"
}

while true; do
  log "Starting FFmpeg restreaming..."

  ffmpeg -f mpegts -i "udp://0.0.0.0:$UDP_PORT?reuse=1" -c:v copy -c:a aac -f hls \
    -hls_time 2 -hls_list_size 3 \
    "$HLS_DIR/output.m3u8" 2>>"$LOG_DIR/restream_error.log" &

  FFMPEG_PID=$!
  wait $FFMPEG_PID
  FF_EXIT_CODE=$?

  if [ $FF_EXIT_CODE -ne 0 ]; then
    log "FFmpeg failed! Check $LOG_DIR/restream_error.log for details."
  else
    log "FFmpeg stopped normally, restarting..."
  fi

  sleep 5
done

