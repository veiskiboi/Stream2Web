#!/bin/bash
set -euo pipefail

check_dependencies() {
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ERROR: Required command 'ffmpeg' not found. Please install it." >&2
    exit 1
  fi
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

