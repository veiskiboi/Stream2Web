#!/bin/bash
set -euo pipefail

# Load env vars
set -a
source "$(dirname "$0")/../.env"
set +a

command_exist() {
  command -v "$1" >/dev/null 2>&1
}

# Check dependencies
deps=(nginx tee)
for dep in "${deps[@]}"; do
  if ! command_exist "$dep"; then
    echo "ERROR: Required command '$dep' not found. Please install it."
    exit 1
  fi
done

# Create nginx site config
NGINX_CONF_PATH="$NGINX_SITE_AVAILABLE"

cat > "$NGINX_CONF_PATH" <<EOF
server {
    listen 4000;
    server_name localhost;

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
else
  echo "Nginx site already enabled."
fi

# Reload nginx to apply changes
echo "Reloading nginx..."
sudo systemctl reload nginx

# Create stream folder and index.html
mkdir -p "$HLS_DIR"

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

