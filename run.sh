#!/bin/bash
set -euo pipefail

# Lock file to prevent multiple run.sh instances
LOCK_FILE="/tmp/run.sh.lock"
PIDS=()

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$LOG_FILE"
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >&2
}

# Cleanup function to remove lock file and kill child processes
cleanup() {
  log "Stopping all child processes..."
  if [ ${#PIDS[@]} -gt 0 ]; then
    sudo kill "${PIDS[@]}" 2>/dev/null || true
    sleep 2  # give them a moment to terminate

    for pid in "${PIDS[@]}"; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "PID $pid still running, sending SIGKILL"
        sudo kill -9 "$pid" 2>/dev/null || true
      fi
    done
  fi

  if [ -f "$LOCK_FILE" ]; then
    sudo rm -f "$LOCK_FILE"
    log "Removed lock file $LOCK_FILE"
  fi

  log "All child processes stopped. Exiting."
  exit
}

# Trap signals for cleanup
trap cleanup SIGINT SIGTERM EXIT

# Base directory of repo
BASE_DIR="$(dirname "$0")"
SCRIPTS_DIR="$BASE_DIR/scripts"

# Log directory (align with .env or adjust as needed)
LOG_DIR="/var/log/streaming"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run.log"

# Check if another run.sh is actually running
if pgrep -f "bash .*/run.sh" >/dev/null && [ -f "$LOCK_FILE" ]; then
  log "ERROR: Another instance of run.sh is already running"
  exit 1
elif [ -f "$LOCK_FILE" ]; then
  log "Removing stale lock file $LOCK_FILE"
  rm -f "$LOCK_FILE" || log "WARNING: Failed to remove stale $LOCK_FILE"
fi

# Acquire lock
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "ERROR: Failed to acquire lock on $LOCK_FILE"
  exit 1
fi

# List of scripts to manage
SCRIPTS=(
  "sender.sh"
  "web-setup.sh"
  "receiver.sh"
  "mp4compiler.sh"
)

# Check dependencies
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

# Check for sudo privileges
if [ "$(id -u)" -ne 0 ]; then
  log "ERROR: This script must be run with sudo privileges"
  exit 1
fi

for script in "${SCRIPTS[@]}"; do
  script_name=$(basename "$script")
  script_path="$SCRIPTS_DIR/$script"

  # Check if script exists
  if [ ! -f "$script_path" ]; then
    log "ERROR: Script $script_path not found"
    cleanup
  fi

  # Start the script without nohup, track PID
  log "Starting $script_name"
  bash "$script_path" >> "$LOG_DIR/${script_name%.sh}.log" 2>&1 &
  PIDS+=($!)
  log "$script_name started successfully (PID: ${PIDS[-1]})"
done

log "All services started. Logs are in $LOG_DIR."

# Wait for all child processes and handle signals
wait "${PIDS[@]}"

