#!/bin/bash
set -euo pipefail

check_dependencies() {
  local deps=(ffmpeg fuser pgrep pkill ping sudo)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "ERROR: Required command '$cmd' not found. Please install it." >&2
      exit 1
    fi
  done
}

check_dependencies

# Load env vars from repo root .env
set -a
source "$(dirname "$0")/../.env"
set +a

mkdir -p "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$LOG_DIR/stream.log"
}

log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: $*" | tee -a "$LOG_DIR/error.log"
}

check_video_device() {
  if fuser "$VIDEO_DEVICE" >/dev/null 2>&1; then
    log_error "$VIDEO_DEVICE is in use by another process! Attempting to free it..."
    sudo fuser -k "$VIDEO_DEVICE" 2>>"$LOG_DIR/error.log"
    sleep 2
    if fuser "$VIDEO_DEVICE" >/dev/null 2>&1; then
      log_error "Failed to free $VIDEO_DEVICE"
      return 1
    fi
  fi
  return 0
}

if [ ! -e "$VIDEO_DEVICE" ]; then
  log_error "Video device $VIDEO_DEVICE not found!"
  exit 1
fi

cleanup_ffmpeg() {
  if pgrep -f "ffmpeg.*$VIDEO_DEVICE" >/dev/null; then
    log "Killing existing ffmpeg processes..."
    pkill -f "ffmpeg.*$VIDEO_DEVICE"
    sleep 2
  fi
}

while true; do
  cleanup_ffmpeg

  if ! check_video_device; then
    log_error "Video device busy, retrying in 10 seconds..."
    sleep 10
    continue
  fi

  if ping -c 2 -W 2 "$SERVER_IP" >/dev/null 2>&1; then
    log "Server reachable, starting streaming..."
    ffmpeg -f v4l2 -i "$VIDEO_DEVICE" \
      -c:v libx264 -preset veryfast -tune zerolatency -g 25 -sc_threshold 0 \
      -f mpegts "udp://$SERVER_IP:$UDP_PORT?pkt_size=1316" 2>>"$LOG_DIR/stream_error.log" &
    STREAM_PID=$!
    wait $STREAM_PID
    if [ $? -ne 0 ]; then
      log_error "Streaming failed! See $LOG_DIR/stream_error.log"
    else
      log "Streaming stopped normally, restarting loop..."
    fi
  else
    log_error "Server unreachable, retrying in 10 seconds..."
    sleep 10
  fi

  log "Waiting 5 seconds before next iteration..."
  sleep 5
done

