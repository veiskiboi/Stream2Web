#!/bin/bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
LOCK_FILE="/tmp/${SCRIPT_NAME%.sh}.lock"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*"
}

log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: $*" >&2
}

# Acquire lock or exit if another instance is running
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log_error "Another instance of $SCRIPT_NAME is already running."
  exit 1
fi

log "Lock acquired for $SCRIPT_NAME"

# Cleanup lock file on exit
cleanup() {
  rm -f "$LOCK_FILE" && log "Removed lock file $LOCK_FILE"
}

trap cleanup SIGINT SIGTERM EXIT

check_dependencies() {
  local deps=(ffmpeg awk du ls sort mktemp stat)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "ERROR: Required command '$cmd' not found. Please install it." >&2
      exit 1
    fi
  done
}

check_dependencies

# Load environment variables from .env in repo root
set -a
source "$(dirname "$0")/../.env"
set +a

# Validate environment variables
for var in HLS_DIR ARCHIVE_DIR LOG_DIR SEGMENT_DURATION MINUTES_PER_FILE STATE_FILE; do
  if [ -z "${!var}" ]; then
    echo "ERROR: Environment variable $var is not set" >&2
    exit 1
  fi
done

SEGMENTS_PER_FILE=$(( (60 / SEGMENT_DURATION) * MINUTES_PER_FILE ))
echo "SEGMENTS_PER_FILE calculated as: $SEGMENTS_PER_FILE" >&2

mkdir -p "$HLS_DIR" "$ARCHIVE_DIR" "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$LOG_DIR/mp4_compiler.log"
  if [[ "$*" == ERROR* || "$*" == WARNING* ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >&2
  fi
}

# Clean up leftover .ts files before starting
if compgen -G "$HLS_DIR/*.ts" > /dev/null; then
  log "Cleaning up leftover .ts files in $HLS_DIR"
  sudo rm -f "$HLS_DIR"/*.ts
fi

# Clear STATE_FILE to handle filename reuse
log "Clearing STATE_FILE to handle filename reuse"
: > "$STATE_FILE"

is_file_stable() {
  local file=$1
  local size1 size2
  if [[ "$OSTYPE" == "darwin"* ]]; then
    size1=$(stat -f%z "$file" 2>/dev/null) || { log "ERROR: stat failed for $file"; return 1; }
  else
    size1=$(stat -c%s "$file" 2>/dev/null) || { log "ERROR: stat failed for $file"; return 1; }
  fi
  sleep 1
  if [[ "$OSTYPE" == "darwin"* ]]; then
    size2=$(stat -f%z "$file" 2>/dev/null) || { log "ERROR: stat failed for $file"; return 1; }
  else
    size2=$(stat -c%s "$file" 2>/dev/null) || { log "ERROR: stat failed for $file"; return 1; }
  fi
  [[ "$size1" == "$size2" && -n "$size1" && -n "$size2" ]]
}

validate_segment() {
  local file=$1
  if ! ffprobe -hide_banner -loglevel error "$file" 2>/dev/null; then
    log "WARNING: Skipping corrupt or invalid file $file"
    return 1
  fi
  return 0
}

declare -A processed_ts

while true; do
  mapfile -t all_ts < <(find "$HLS_DIR" -maxdepth 1 -name "output*.ts" -type f 2>/dev/null | sort -V)
  log "Found ${#all_ts[@]} .ts files: ${all_ts[*]}"

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
  log "Unprocessed files: ${unprocessed[*]} (count: $count_unprocessed)"

  if [ "$count_unprocessed" -lt $((SEGMENTS_PER_FILE + 2)) ]; then
    log "Not enough segments ($count_unprocessed/$((SEGMENTS_PER_FILE + 2))), sleeping 5 seconds"
    sleep 5
    continue
  fi

  chunks=$(( count_unprocessed / SEGMENTS_PER_FILE ))

  for ((c=0; c<chunks; c++)); do
    start=$(( c * SEGMENTS_PER_FILE ))
    end=$(( start + SEGMENTS_PER_FILE - 1 ))

    tmp_list=$(mktemp)
    delete_list=()
    for ((i=start; i<=end; i++)); do
      echo "${unprocessed[i]}"
    done | sort -V | while read -r fname; do
      echo "file '$HLS_DIR/$fname'" >> "$tmp_list"
      delete_list+=("$HLS_DIR/$fname")
    done

    output_file="$ARCHIVE_DIR/stream_$(date +%Y%m%d_%H%M%S).mp4"
    log "Creating MP4 from segments $((start+1)) to $((end+1)) → $output_file"

    ffmpeg -hide_banner -loglevel error -fflags +igndts -f concat -safe 0 -i "$tmp_list" -c copy -r 30 "$output_file" 2>> "$LOG_DIR/mp4_compiler.log"
    ffmpeg_result=$?
    rm -f "$tmp_list"

    if [ $ffmpeg_result -ne 0 ]; then
      log "ERROR: Failed to create MP4 file $output_file"
      sleep 5
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

    MAX_ARCHIVE_SIZE=$((10 * 1024 * 1024 * 1024))
    while true; do
      total_size=$(du -sb "$ARCHIVE_DIR" | awk '{print $1}')
      if [ "$total_size" -le "$MAX_ARCHIVE_SIZE" ]; then
        break
      fi
      oldest_file=$(ls -1tr "$ARCHIVE_DIR"/*.mp4 | head -n1)
      if [ -z "$oldest_file" ]; then
        log "No files to delete but archive size exceeds limit"
        break
      fi
      log "Deleting oldest archive file $oldest_file to maintain 10GB limit"
      sudo rm -f "$oldest_file"
    done
  done

  log "Cycle complete. Sleeping 5 seconds"
  sleep 5
done

