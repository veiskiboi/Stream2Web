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

mkdir -p "$HLS_DIR"

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
  local deps=(nginx tee)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command '$cmd' not found. Please install it."
      exit 1
    fi
  done
}
check_dependencies

# Create nginx site config
NGINX_CONF_PATH="$NGINX_SITE_AVAILABLE"

cat > "$NGINX_CONF_PATH" <<EOF
server {
    listen $WEB_PORT;
    server_name $SERVER_IP;

    root $WEB_ROOT;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location $STREAM_LOCATION/ {
        add_header Access-Control-Allow-Origin *;
        try_files \$uri \$uri/ =404;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF

echo "Nginx site config created at $NGINX_CONF_PATH"

# Enable site
if [ ! -L "$NGINX_SITE_ENABLED" ]; then
  ln -s "$NGINX_SITE_AVAILABLE" "$NGINX_SITE_ENABLED"
  echo "Enabled nginx site by linking to sites-enabled."
  cleanup
else
  echo "Nginx site already enabled."
  cleanup
fi

# Reload nginx to apply changes
echo "Reloading nginx..."
sudo systemctl reload nginx

cat > "$HLS_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Camera Stream</title>
    <style>
        body { margin: 0; padding: 20px; font-family: Arial, sans-serif; background-color: #f0f0f0; }
        h1 { text-align: center; }
        video { display: block; margin: 0 auto; max-width: 100%; border: 2px solid #333; }
    </style>
</head>
<body>
    <h1>Live Camera Stream</h1>
    <video controls autoplay muted>
        <source src="$STREAM_LOCATION/output.m3u8" type="application/x-mpegURL" />
        Your browser does not support the video tag.
    </video>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
    <script>
        const video = document.querySelector('video');
        const videoSrc = '$STREAM_LOCATION/output.m3u8';
        if (Hls.isSupported()) {
            const hls = new Hls();
            hls.loadSource(videoSrc);
            hls.attachMedia(video);
        } else if (video.canPlayType('application/x-mpegURL')) {
            video.src = videoSrc;
        }
    </script>
</body>
</html>
EOF

echo "Stream index.html created at $HLS_DIR/index.html"
