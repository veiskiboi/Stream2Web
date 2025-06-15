#!/bin/bash
set -euo pipefail

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

SEGMENTS_PER_FILE=$(( (60 / SEGMENT_DURATION) * MINUTES_PER_FILE ))  # 900 segments per 30 min

mkdir -p "$HLS_DIR" "$ARCHIVE_DIR" "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$LOG_DIR/mp4_compiler.log"
}

# Clean up any leftover .ts files before starting
if compgen -G "$HLS_DIR/*.ts" > /dev/null; then
  log "Cleaning up leftover .ts files in $HLS_DIR"
  rm -f "$HLS_DIR"/*.ts
fi

# Check if a file is stable (not growing in size)
is_file_stable() {
  local file=$1
  local size1 size2
  size1=$(stat -c%s "$file")
  sleep 1
  size2=$(stat -c%s "$file")
  [[ "$size1" -eq "$size2" ]]
}

# Read processed segments from state file into an associative array for quick lookup
declare -A processed_ts
if [ -f "$STATE_FILE" ]; then
  while IFS= read -r line; do
    processed_ts["$line"]=1
  done < "$STATE_FILE"
fi

while true; do
  # List all .ts files sorted by name (assumed time-ordered)
  mapfile -t all_ts < <(ls -1 "$HLS_DIR"/*.ts 2>/dev/null | sort)

  # Filter unprocessed and stable .ts files
  unprocessed=()
  for f in "${all_ts[@]}"; do
    filename=$(basename "$f")
    if [ -z "${processed_ts[$filename]-}" ]; then
      if is_file_stable "$f"; then
        unprocessed+=("$filename")
      else
        log "File $filename is still being written, skipping"
      fi
    fi
  done

  if [ ${#unprocessed[@]} -lt $SEGMENTS_PER_FILE ]; then
    log "Not enough new stable segments yet (${#unprocessed[@]}/$SEGMENTS_PER_FILE). Waiting..."
    sleep 60
    continue
  fi

  chunks=$(( ${#unprocessed[@]} / SEGMENTS_PER_FILE ))

  for ((c=0; c<chunks; c++)); do
    start=$(( c * SEGMENTS_PER_FILE ))
    end=$(( start + SEGMENTS_PER_FILE - 1 ))

    tmp_list=$(mktemp)
    for ((i=start; i<=end; i++)); do
      echo "file '$HLS_DIR/${unprocessed[i]}'" >> "$tmp_list"
    done

    output_file="$ARCHIVE_DIR/stream_$(date +%Y%m%d_%H%M%S).mp4"
    log "Creating MP4 from segments $((start+1)) to $((end+1)) → $output_file"

    ffmpeg -hide_banner -loglevel error -f concat -safe 0 -i "$tmp_list" -c copy "$output_file"
    ffmpeg_result=$?
    rm -f "$tmp_list"

    if [ $ffmpeg_result -ne 0 ]; then
      log "ERROR: Failed to create MP4 file."
      sleep 30
      continue
    fi

    for ((i=start; i<=end; i++)); do
      fname="${unprocessed[i]}"
      echo "$fname" >> "$STATE_FILE"
      processed_ts["$fname"]=1
      rm -f "$HLS_DIR/$fname"
    done

    log "Created $output_file and cleaned up processed .ts files."

    MAX_ARCHIVE_SIZE=$((10 * 1024 * 1024 * 1024))  # 10 GB
    while true; do
      total_size=$(du -sb "$ARCHIVE_DIR" | awk '{print $1}')
      if [ "$total_size" -le "$MAX_ARCHIVE_SIZE" ]; then
        break
      fi
      oldest_file=$(ls -1tr "$ARCHIVE_DIR"/*.mp4 | head -n1)
      if [ -z "$oldest_file" ]; then
        log "No files to delete but archive size exceeds limit."
        break
      fi
      log "Deleting oldest archive file $oldest_file to maintain 10GB limit."
      rm -f "$oldest_file"
    done
  done

  log "Cycle complete. Sleeping 60 seconds."
  sleep 60
done

