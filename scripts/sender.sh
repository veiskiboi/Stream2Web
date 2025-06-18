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
LOG_FILE="$LOG_DIR/${SCRIPT_NAME}.log"

mkdir -p "$LOG_DIR"

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
  local deps=(ffmpeg fuser pgrep pkill ping sudo ps)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command '$cmd' not found. Please install it."
      exit 1
    fi
  done
}
check_dependencies

check_video_device() {
  if fuser "$VIDEO_DEVICE" &>/dev/null; then
    log_error "$VIDEO_DEVICE is in use! Attempting to free it..."
    sudo fuser -k "$VIDEO_DEVICE" 2>>"$LOG_DIR/error.log"
    sleep 2
    if fuser "$VIDEO_DEVICE" &>/dev/null; then
      log_error "Failed to free $VIDEO_DEVICE"
      return 1
    fi
  fi
  return 0
}

[ ! -e "$VIDEO_DEVICE" ] && log_error "Video device $VIDEO_DEVICE not found!" && exit 1

cleanup_ffmpeg() {
  if pgrep -f "ffmpeg.*$VIDEO_DEVICE" &>/dev/null; then
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

  if ping -c 2 -W 2 "$SERVER_IP" &>/dev/null; then
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

