# Stream2Web

**Stream2Web** allows you to stream your camera directly to a web interface via Raspberry Pi or any Linux device.  
The stream is archived automatically in segments, and accessible remotely.

---

## Features

- 📹 Live streaming via HLS
- 💾 Automatic archiving of streams
- 🗑 Archive size management
- 🌐 Lightweight web interface with Nginx
- 🔒 .env based configuration
- 🚀 Fully scriptable setup and deployment

### For advanced users:
  - Install sender to send live camera feed via HSL (UDP)
  - Install receiver to either local server or remote one.
  - Run conceniently the web-setup file for preconfigured nginx site Stream2Web on {SERVER_IP}:{UDP_PORT}/{STREAM_LOCATION}
  
---

## Requirements

- Linux (tested on Debian 24 & Raspberry Pi OS)
- `ffmpeg`
- `nginx`
- `sudo`
- `awk`, `du`, `ls`, `sort`, `mktemp`, `stat`, `bc`, `fuser`  
(All dependencies are checked automatically by scripts)

---

## Installation

### Clone repository

```bash
git clone git@github.com:veiskiboi/Stream2Web.git
cd Stream2Web
