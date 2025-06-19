#!/bin/bash
set -euo pipefail

# Normalize paths
SCRIPT_NAME=$(basename "$0")
BASE_DIR="$(pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"

# Load env vars from repo root .env
set -a
source "$BASE_DIR/.env"
set +a


LOG_DIR="$BASE_DIR/${LOG_DIR#./}"
LOCK_DIR="$BASE_DIR/${LOCK_DIR#./}"
LOCK_FILE="$LOCK_DIR/${SCRIPT_NAME%.sh}.lock"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

mkdir -p "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$LOG_FILE"
}
log "Script name: $SCRIPT_NAME Base directory: $BASE_DIR Scripts directory: $SCRIPTS_DIR Log directory: $LOG_DIR Lock directory: $LOCK_DIR Lock file: $LOCK_FILE Log file: $LOG_FILE"
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

  log "Stopping all child processes..."
  if [ ${#PIDS[@]} -gt 0 ]; then
    sudo kill "${PIDS[@]}" 2>/dev/null || true
    echo "Waiting... terminating..."
    sleep 4  # give them a moment to terminate

    for pid in "${PIDS[@]}"; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "PID $pid still running, sending SIGKILL"
        sudo kill -9 "$pid" 2>/dev/null || true
      fi
    done
  fi
  rm -f "$LOCK_DIR"/*.lock
  echo "Lock files deleted succcessfully."
  if ls "$LOCK_DIR"/*.lock &>/dev/null; then
    log "WARNING: Some .lock files remain in $LOCK_DIR"
  else
    log "All .lock files successfully removed from $LOCK_DIR"
  fi
}
trap cleanup SIGINT SIGTERM

USBRESET=false

for arg in "$@"; do
  case "$arg" in
    --usbreset)
      USBRESET=true
      ;;
  esac
done
if [ "$USBRESET" = true ]; then
  bash "$BASE_DIR/misc/usbreset.sh"
fi
SCRIPTS=(
  "web-setup.sh"
  "sender.sh"
  "receiver.sh"
  "mp4compiler.sh"
)

check_dependencies() {
  local deps=(flock pgrep)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "ERROR: Required command '$cmd' not found. Please install procps or flock."
      exit 1
    fi
  done
}

check_dependencies

if [ "$(id -u)" -ne 0 ]; then
  log "ERROR: This script must be run with sudo privileges"
  exit 1
fi

for script in "${SCRIPTS[@]}"; do
  script_name=$(basename "$script")
  script_path="$SCRIPTS_DIR/$script"

  if [ ! -f "$script_path" ]; then
    log "ERROR: Script $script_path not found"
    cleanup
  fi

  log "Starting $script_name"
  bash "$script_path" 2>&1 | tee -a "$LOG_DIR/${script_name%.sh}.log" &
  PIDS+=($!)
  log "$script_name started successfully (PID: ${PIDS[-1]})"
done

log "All services started. Logs are in $LOG_DIR."

wait "${PIDS[@]}"

