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

---

## Advanced Usage

- Install **sender** to stream live camera feed via HLS (UDP)
- Install **receiver** on local or remote server
- Use the `web-setup` script to configure Nginx automatically

Example access URL:  
```bash
{SERVER_IP}:{UDP_PORT}/{STREAM_LOCATION}
# e.g.
192.168.1.102:4000/stream
```
--

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
cd Stream2Web``
```
