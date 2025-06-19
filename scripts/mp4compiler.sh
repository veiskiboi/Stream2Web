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
exit_requested=0
mkdir -p "$HLS_DIR" "$ARCHIVE_DIR" "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$LOG_FILE"
}
echo "Log file: $LOG_FILE"
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
  exit_requested=1
}
trap cleanup SIGINT SIGTERM

check_dependencies() {
  local deps=(ffmpeg awk du ls sort mktemp stat)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command '$cmd' not found. Please install it."
      exit 1
    fi
  done
}
check_dependencies

SEGMENTS_PER_FILE=$(( (60 / SEGMENT_DURATION) * MINUTES_PER_FILE ))
log "SEGMENTS_PER_FILE calculated as: $SEGMENTS_PER_FILE"

if compgen -G "$HLS_DIR/*.ts" > /dev/null; then
  log "Cleaning up leftover .ts files in $HLS_DIR"
  sudo rm -f "$HLS_DIR"/*.ts
fi

log "Clearing STATE_FILE to handle filename reuse"
: > "$BASE_DIR/$STATE_FILE"

is_file_stable() {
  # Placeholder, always return true (stable)
  return 0
}

validate_segment() {
  local file=$1
  if ! ffprobe -hide_banner -loglevel error "$file" 2>/dev/null; then
    log "WARNING: Skipping corrupt or invalid file $file"
    return 1
  fi
  return 0
}

cleanup_archive() {
  local max_bytes total_size oldest_files file_size

  max_bytes=$(( MAX_ARCHIVE_SIZE_GB * 1024 * 1024 * 1024 ))
  total_size=$(sudo du -sb "$ARCHIVE_DIR" 2>/dev/null | awk '{print $1}' || echo 0)

  log "Current archive size: $total_size bytes (limit: $max_bytes bytes)"

  mapfile -t oldest_files < <(ls -1tr "$ARCHIVE_DIR"/*.mp4 2>/dev/null || true)

  for f in "${oldest_files[@]}"; do
    if [ "$total_size" -le "$max_bytes" ]; then
      break
    fi

    file_size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    if sudo rm -f -- "$f"; then
      log "Deleted $f to reduce archive size"
      total_size=$(( total_size - file_size ))
      log "Archive size now approx: $total_size bytes"
    else
      log "ERROR: Failed to delete $f"
      break
    fi
  done

  if [ "$total_size" -gt "$max_bytes" ]; then
    log "WARNING: Archive size still exceeds limit after cleanup."
  else
    log "Archive size is within limit after cleanup."
  fi
}

declare -A processed_ts

while true; do
  # Check exit_requested flag before looping
  if [ $exit_requested -eq 1 ]; then
    break
  fi

  event_file=$(inotifywait -e close_write,create --format '%f' --quiet --timeout 10 "$HLS_DIR" --exclude '.*[^t][^s]$') || {
    # Check exit_requested here as well
    if [ $exit_requested -eq 1 ]; then
      break
    fi
    log "WARNING: inotifywait failed, timed out, or was interrupted; retrying in 1s"
    sleep 1
    continue
  }

  # Check exit_requested again after inotifywait
  if [ $exit_requested -eq 1 ]; then
    break
  fi

  if [ -n "$event_file" ]; then
    log "Detected event for file: $event_file"
  else
    log "No event detected within timeout, checking for files anyway"
  fi

  mapfile -t all_ts < <(find "$HLS_DIR" -maxdepth 1 -name "output*.ts" -type f 2>/dev/null | sort -V)

  unprocessed=()
  for f in "${all_ts[@]}"; do
    filename=$(basename "$f")
    if [ -n "${processed_ts[$filename]-}" ]; then
      log "Skipping $filename: already processed"
    elif is_file_stable "$f" && validate_segment "$f"; then
      unprocessed+=("$filename")
    else
      log "Skipping $filename: file is unstable or invalid"
    fi
  done

  count_unprocessed=${#unprocessed[@]}
  log "Unprocessed files: $count_unprocessed"

  if [ "$count_unprocessed" -lt "$SEGMENTS_PER_FILE" ]; then
    log "Not enough segments ($count_unprocessed/$SEGMENTS_PER_FILE)"
    continue
  fi

  chunks=$(( count_unprocessed / SEGMENTS_PER_FILE ))

  for ((c=0; c<chunks; c++)); do
    start=$(( c * SEGMENTS_PER_FILE ))
    end=$(( start + SEGMENTS_PER_FILE - 1 ))

    tmp_list=$(mktemp)
    for ((i=start; i<=end; i++)); do
      echo "file '$HLS_DIR/${unprocessed[i]}'"
    done | sort -V > "$tmp_list"

    output_file="$ARCHIVE_DIR/stream_$(date +%Y%m%d_%H%M%S).mp4"
    log "Creating MP4 from segments $((start+1)) to $((end+1)) → $output_file"

    ffmpeg -hide_banner -loglevel error -fflags +igndts -f concat -safe 0 -i "$tmp_list" -c copy -r 30 "$output_file" 2>> "$LOG_FILE"
    ffmpeg_result=$?
    rm -f "$tmp_list"

    if [ $ffmpeg_result -ne 0 ]; then
      log "ERROR: Failed to create MP4 file $output_file"
      sleep 1
      continue
    fi

    for ((i=start; i<=end; i++)); do
      fname="${unprocessed[i]}"
      echo "$fname" >> "$STATE_FILE"
      processed_ts["$fname"]=1
    done

    for ((i=start; i<=end; i++)); do
      fname="${unprocessed[i]}"
      full_path="$HLS_DIR/$fname"
      for attempt in {1..3}; do
        if sudo rm -f "$full_path" && [ ! -f "$full_path" ]; then
          log "Deleted processed file $fname"
          break
        else
          log "WARNING: Failed to delete $full_path (attempt $attempt)"
          sleep 1
        fi
      done
      if [ -f "$full_path" ]; then
        log "ERROR: Could not delete $full_path after 3 attempts"
      fi
    done

    log "Created $output_file and cleaned up processed .ts files"

    cleanup_archive
  done
done

