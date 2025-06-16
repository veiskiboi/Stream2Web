# Stream2Web

**Stream2Web** allows you to stream your camera directly to a web interface via Raspberry Pi or any Linux device.  
The stream is archived automatically in segments, and accessible remotely.

---
##⚠️ Important Notice
The archive size management feature (10GB limit cleanup) is still experimental.
While the script tries to keep the archive folder under 10GB by deleting the oldest files, it may not always work perfectly in all scenarios.
Use with caution and monitor your storage until you're confident it behaves as expected.

Contributions and feedback to improve this feature are welcome!
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
- These segments are automatically converted to 30-minute `.mp4` videos for easier playback and storage.  
- Archive size is managed by deleting the oldest files when limits are reached. Default max (10GB)

Example archive URL:
```bash
{SERVER_IP}:{UDP_PORT}/{ARCHIVE_DIR}
# e.g.
192.168.1.102:4000/archive
&
/etc/var/www/html/archive
```
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
&
/etc/var/www/html/stream
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
cd Stream2Web
```
