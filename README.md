# Stream2Web

**Stream2Web** allows you to stream your camera directly to a web interface via Raspberry Pi or any Linux device.  
The stream is archived automatically in segments, and accessible remotely.

---
## ⚠️ Important Notice
This version still utilizes slow and semi-unstable HLS, this will be updated to WebRTC on next version for convenience and performance.

---
## Features

- 📹 Live streaming via HLS
- 💾 Automatic archiving of streams
- 🗑 Archive size management
- 🌐 Lightweight web interface with Nginx
- 🔒 .env based configuration
- 🚀 Fully scriptable setup and deployment

## Archiving

- Streams are saved in segmented `.st` files.  
- These segments are automatically converted to 30-minute `.mp4` videos by default for easier playback and storage. (`.st` segments are cleaned afterwards). 
- Archive size is managed by deleting the oldest files when limits are reached. Default max (1GB)

Example archive URL:
```bash
{SERVER_IP}:{WEB_PORT}/{ARCHIVE_DIR}
# e.g.
127.0.0.1:4000/archive
&
/etc/var/www/html/archive
```

---
## Advanced Usage

- Install `sender` to stream live camera feed via HLS (UDP)
- Install `receiver` on local or remote server
- Use the `web-setup` script to configure Nginx automatically
- Use the `nginx-stop` script to stop Nginx web server. To resume, run `web-setup` again
- Use USB-port reset `usbreset` to ensure each USB-webcam is found. This is designed for USB-A port devices.

Example access URL:  
```bash
{SERVER_IP}:{WEB_PORT}/{STREAM_LOCATION}
# e.g.
127.0.0.1:4000/stream
&
/etc/var/www/html/stream
```

---
## Requirements

- Linux (tested on Debian 24 & Raspberry Pi OS)
- `ffmpeg`
- `nginx`
- `sudo`
- `awk`, `du`, `ls`, `sort`, `mktemp`, `stat`, `bc`, `fuser`  
(All dependencies are checked automatically by scripts)

## Installation

### Clone repository

```bash
git clone https://github.com/veiskiboi/Stream2Web.git
cd Stream2Web
sudo ./run.sh # Standard setup. For advanced, check Advanced Usage
```
