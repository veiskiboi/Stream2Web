#!/bin/bash
set -euo pipefail

# Normalize paths
SCRIPT_NAME=$(basename "$0")
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load env vars from repo root .env
set -a
source "$BASE_DIR/.env"
set +a

LOG_DIR="$BASE_DIR/${LOG_DIR#./}"
LOCK_DIR="$BASE_DIR/${LOCK_DIR#./}"
LOCK_FILE="$LOCK_DIR/${SCRIPT_NAME%.sh}.lock"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

mkdir -p "$HLS_DIR" "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: $*" | tee -a "$LOG_DIR/error.log" >&2
}

# --- Lock Handling ---
if [ -f "$LOCK_FILE" ] && ! lsof "$LOCK_FILE" >/dev/null 2>&1; then
  log "Stale lock detected. Removing..."
  rm -f "$LOCK_FILE"
fi

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log_error "Another instance of $SCRIPT_NAME is already running. $LOCK_FILE"
  exit 1
fi

cleanup() {
  rm -f "$LOCK_FILE"
  log "Cleanup complete. Lock file removed."
}
trap cleanup SIGINT SIGTERM

check_dependencies() {
  local deps=(ffmpeg ps)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command '$cmd' not found. Please install it."
      exit 1
    fi
  done
}
check_dependencies


while true; do
  log "Starting FFmpeg restreaming..."

  ffmpeg -f mpegts -i "udp://0.0.0.0:$UDP_PORT?reuse=1" -c:v copy -c:a aac -f hls \
    -hls_time "$SEGMENT_DURATION" -hls_list_size 3 \
    "$HLS_DIR/output.m3u8" 2>>"$LOG_DIR/restream_error.log" &

  FFMPEG_PID=$!
  wait $FFMPEG_PID
  FF_EXIT_CODE=$?

  if [ $FF_EXIT_CODE -ne 0 ]; then
    log_error "FFmpeg failed! Check $LOG_DIR/restream_error.log"
  else
    log "FFmpeg stopped normally. Restarting..."
  fi

  sleep 5
done

