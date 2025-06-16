#!/bin/bash
set -euo pipefail

# Load .env for variables
set -a
source "$(dirname "$0")/../.env"
set +a

echo "Disabling Stream2Web nginx site..."

if [ -L "$NGINX_SITE_ENABLED" ]; then
  sudo rm "$NGINX_SITE_ENABLED"
  echo "Site disabled."
else
  echo "Site is not enabled."
fi

echo "Reloading nginx..."
sudo systemctl reload nginx

echo "Nginx site stopped."
