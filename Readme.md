# Homelab
This repo contains the resources and instructions for my homelab setup centered around docker-compose.yml 
## Basic Setup
- Copy `.envexample` to `.env` and fill in variables
- `docker compose up`
## Services
### Timemachine
Server for mac backups. Note: It's currently hardcoded to 2 TB limit for backup data.
#### Prereqs
- avahi-daemon not running on host (`sudo systemctl stop avahi-daemon && sudo systemctl disable avihi-daemon`)
- smbd not bound to port 445 on host — native Samba (see Samba section) runs on 1445 and does not conflict
- nmbd not running on host (`sudo systemctl stop nmbd && sudo systemctl disable nmbd`)
- afpd & netatalk not running on host (`sudo systemctl stop netatalk && sudo systemctl disable netatalk`)
- static ip on host
- Firewall ports 137/UDP, 138/UDP, 139/TCP, 445/TCP open

#### Environment Variables
- `TM_PASSWORD` - password for the `timemachine` user
- `TM_DATA_PATH` - file path to persist backup data

#### Additional Setup
1. Once the container is running, press cmd+K in Finder from the mac to backup.
1. Enter `smb://<IP_OR_URL_OF_SERVER>` and connect.
1. Navigate to Time Machine in settings
1. Add a backup target
1. Choose TimeMachine and follow the prompts.

### Samba
General-purpose SMB file share. Runs natively on the host (not Docker) on port 1445 to avoid conflicts with the Timemachine container on port 445. Share path and user are hardcoded in `samba/smb.conf`.

#### Prereqs
- Firewall port 1445/TCP open

#### Setup
```bash
sudo apt install samba samba-vfs-modules
sudo useradd -M -s /sbin/nologin samba
sudo smbpasswd -a samba
sudo cp samba/smb.conf /etc/samba/smb.conf
sudo systemctl enable --now smbd
```

#### Connecting
- **Mac Finder:** `cmd+K` → `smb://<host>:1445/share`
- **Linux:** `mount -t cifs //<host>/share /mnt/point -o port=1445,username=samba`
- **Windows:** Non-standard SMB ports require a registry change — consider using a different service for Windows clients

### Caddy
Web server doing reverse proxy for lab services and redirects for shortcuts
#### Prereqs
- Firewall ports 80 and 443 open
- Nothing on host listening on 80 and 443 on host
- Static ip on host
- Domain registered through cloudflare
- Local DNS available

#### Environment Variables
- CF_API_TOKEN - Cloudflare API token with permissions described below

#### Additional Setup
1. Navigate to cloudflare API Token UI **My Profile → API Tokens → Create Token**
1. Create a token: Use the **Edit zone DNS** template, scoped to your specific zone (domain). The token needs these permissions:
    - `Zone / Zone / Read`
    - `Zone / DNS / Edit`
1. Paste Token into .env file
1. Add local dns record to point domain to the server's ip
1. Add local dns records for everything that is reverse proxied
1. Add local dns records for everything all url shortcuts

#### Additional Notes
- This service is configured to build from source in the docker compose.  It may need explicitly rebuilt at times by passing `--build` to `docker compose up`

### Pihole
DNS Server and Ad filtering
#### Prereqs
- Firewall port 53 open
- Nothing listening on port 53 of host (see https://www.turek.dev/posts/disable-systemd-resolved-cleanly/)
- Static IP

### Volume Backup
Runs a cron job daily at 2 am EST to copy docker volume contents to onedrive and delete backups more than 7 days (may change to 30) old
#### Prereqs
- Onedrive account with folder `/Documents/Homelab/Backups`
#### Additional Setup
On your host machine (not in Docker yet), run:
`rclone config`
- Choose n (new remote)
- Name: onedrive
- Storage: OneDrive
- Follow login flow
This creates:
`~/.config/rclone/rclone.conf`

Copy this file to the `volume-backup` directory before creating the container.

#### Additional Notes
- Keep rclone.conf safe. It contains an auth token
- To test without waiting for the cron job to fire `docker exec -it volume-backup /app/backup.sh`


### Budget
Two containers for the front end and back end of a custom budgeting app.  Should just run with nothing additional.

### Jellyfin
Media server with NVIDIA GPU hardware acceleration for transcoding. Media is mounted read-only.

#### Prereqs
- NVIDIA GPU on the host
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed on the host
  - After install, restart the Docker daemon: `sudo systemctl restart docker`
- A directory to serve as the media root (can be empty for initial PoC)

#### Environment Variables
- `JELLYFIN_MEDIA_PATH` - path on the host to mount as the media library (mounted read-only)

#### Additional Setup
1. Add `JELLYFIN_MEDIA_PATH=/path/to/media` to `.env`
1. Add a local DNS record pointing `jellyfin.lab.mattsmith.tech` to the server's IP
1. `docker compose up -d jellyfin`
1. Navigate to `https://jellyfin.lab.mattsmith.tech` and complete the setup wizard
1. When adding a media library, point it to `/data/media` (or a subdirectory within it)

#### Enabling Hardware Transcoding
1. In Jellyfin, go to **Dashboard → Playback → Transcoding**
1. Set **Hardware acceleration** to `Nvidia NVENC`
1. Enable the codec options you want (H.264, H.265/HEVC, etc.)

### Tradebot
Long-only, paper-first trading bot for US stocks (Alpaca) and Polymarket, with a web dashboard and backtester. Source lives in the `tradebot` git submodule. Runs fully keyless by default (synthetic market data + simulated fills) — no credentials required to try it out.

#### Prereqs
- `git submodule update --init tradebot` to check out the source (only needed once, or after the submodule pointer changes)
- Local DNS record for `tradebot.lab.mattsmith.tech`

#### Environment Variables
- `TRADEBOT_DASHBOARD_PASSWORD` - dashboard login password. Blank disables auth (trusted-LAN only)
- `TRADEBOT_ALPACA_API_KEY` / `TRADEBOT_ALPACA_API_SECRET` - Alpaca paper-trading keys. Leave blank to run keyless
- `TRADEBOT_POLYMARKET_PRIVATE_KEY` - wallet private key, only needed for live Polymarket trading
- `TRADEBOT_CONFIRM_LIVE` - hard gate for live trading; the dashboard live toggle stays disabled unless this is exactly `true`

#### Additional Setup
1. Add a local DNS record pointing `tradebot.lab.mattsmith.tech` to the server's IP
1. `docker compose up -d --build tradebot`
1. Navigate to `https://tradebot.lab.mattsmith.tech`

#### Additional Notes
- The Docker build runs tradebot's full test suite with a 90% coverage gate, so the first build is slow — a failing or uncovered change cannot produce an image
- Never commit real API keys or the Polymarket wallet key; they belong in `.env` only

### Price Tracker
Tracks product prices across several retailers (LEGO, Barnes & Noble, Woot, Target, Best Buy, Amazon, Walmart) and emails you when a tracked item drops below your threshold. Source lives in the `price-tracker` git submodule. Runs as two containers built from the same image: `price-tracker-web` (FastAPI dashboard on port 8000) and `price-tracker-worker` (background scraper/scheduler). Both share a `price_tracker_data` volume holding the SQLite database at `/data/price_tracker.db`.

#### Prereqs
- `git submodule update --init price-tracker` to check out the source (only needed once, or after the submodule pointer changes)
- Local DNS record for `pricetracker.lab.mattsmith.tech`

#### Environment Variables
- `PRICETRACKER_SCRAPE_INTERVAL_HOURS` - how often the worker re-scrapes prices (default `6`)
- `PRICETRACKER_PRICE_HISTORY_RETENTION_DAYS` - price history older than this is pruned daily (default `730`)
- `PRICETRACKER_SMTP_HOST` / `PRICETRACKER_SMTP_PORT` - outgoing mail server (e.g. `smtp.gmail.com` / `587`)
- `PRICETRACKER_SMTP_USER` / `PRICETRACKER_SMTP_PASS` - SMTP credentials. For Gmail, create an app password
- `PRICETRACKER_EMAIL_FROM` / `PRICETRACKER_EMAIL_TO` - sender and recipient for price-drop alerts

#### Additional Setup
1. Fill in the `PRICETRACKER_*` values in `.env`
1. Add a local DNS record pointing `pricetracker.lab.mattsmith.tech` to the server's IP
1. `docker compose up -d --build price-tracker-web price-tracker-worker`
1. Navigate to `https://pricetracker.lab.mattsmith.tech`

#### Additional Notes
- The image is based on `mcr.microsoft.com/playwright/python`, so the first build pulls a large browser-automation base image
- Never commit real SMTP credentials; they belong in `.env` only

### Calibre Web (Ebooks)
Web front-end for a Calibre ebook library, using [Calibre-Web-Automated](https://github.com/crocodilestick/Calibre-Web-Automated) (CWA). Runs as the `calibre-web-automated` container (web UI on port 8083) and gives household members a browser-based library plus an OPDS feed for reading apps on tablets/phones. Three volumes: `calibre_config` (app settings/users), `calibre_library` (the Calibre library and `metadata.db`), and `calibre_ingest` (a watched folder — any ebook dropped in is auto-converted and imported). All three are named volumes bind-backed onto the ZFS array via `driver_opts` (paths set by `CALIBRE_*_PATH` in `.env`), so the data lives on the pool. Only `calibre_config` is included in the off-site Volume Backup; the library is intentionally excluded (it can be large) and relies on ZFS snapshots/redundancy instead.

#### Prereqs
- Local DNS record for `books.lab.mattsmith.tech`
- The three `CALIBRE_*_PATH` directories on the ZFS array must exist before `docker compose up` — a `bind` volume will not create the target and the container fails to start if it is missing

#### Environment Variables
- `CALIBRE_CONFIG_PATH` - ZFS path for CWA app config/users (backs the `calibre_config` volume)
- `CALIBRE_LIBRARY_PATH` - ZFS path for the Calibre library and `metadata.db` (backs the `calibre_library` volume)
- `CALIBRE_INGEST_PATH` - ZFS path for the auto-import watched folder (backs the `calibre_ingest` volume)

#### Additional Setup
1. Create the three `CALIBRE_*_PATH` directories on the ZFS array (a dedicated dataset is a good fit) and set the paths in `.env`
1. Add a local DNS record pointing `books.lab.mattsmith.tech` to the server's IP
1. `docker compose up -d calibre-web-automated`
1. Navigate to `https://books.lab.mattsmith.tech` and log in with the default `admin` / `admin123`, then change the password immediately
1. To seed an existing Calibre library, copy its folder contents (including `metadata.db`) into `CALIBRE_LIBRARY_PATH` while the container is stopped, then start it. Alternatively, upload books through the web UI or drop files into `CALIBRE_INGEST_PATH`
1. Reading on an iPad/tablet: install an OPDS-capable reader (e.g. KyBook 3, Marvin, Panels) and point it at `https://books.lab.mattsmith.tech/opds`, or just read in the browser
1. (Optional) Send-to-email/Kindle: configure the SMTP server under Admin → Edit Email Server Settings in the web UI (the same Gmail app-password approach used by Price Tracker works)

#### Additional Notes
- Do not open the same library in desktop Calibre and CWA at the same time — `metadata.db` is not safe for concurrent writers. Let CWA own the library day-to-day
- The default `admin` / `admin123` credentials are well-known; change them on first login

## Hardcoded Setup-Specific Configuration

This repo contains values specific to this homelab that must be changed when adapting it for a different environment.

### Domain (`mattsmith.tech`)
Every service URL and TLS certificate is tied to `mattsmith.tech`. Replace all occurrences in:
- `caddy/Caddyfile` — wildcard cert blocks (`*.mattsmith.tech`, `*.lab.mattsmith.tech`) and all service hostnames
- `caddy/index.html` — all href links in the Useful Links section

### LAN Subnets (`192.168.1.0/24`, `192.168.20.0/24`)
`caddy/Caddyfile` uses `remote_ip` matchers to restrict access to these subnets. `192.168.1.0/24` is the primary LAN and `192.168.20.0/24` is a second network that is also allowed to reach Jellyfin (e.g. a media VLAN). Update both to match your network.

### UniFi Router IP (`192.168.1.1`)
Hardcoded in two places:
- `caddy/Caddyfile` — `http://unifi` redirect target
- `caddy/index.html` — UniFi Admin link href

### InkyPi Internal Hostname (`inky.lab.mattsmith.tech`)
`caddy/Caddyfile` proxies `inkypi.lab.mattsmith.tech` to `http://inky.lab.mattsmith.tech`. This is a device-specific internal DNS name that must match whatever hostname your InkyPi device has on your network.

### Tradebot Hostname (`tradebot.lab.mattsmith.tech`)
`caddy/Caddyfile` proxies `tradebot.lab.mattsmith.tech` (and the `tb/` shortcut) to `http://tradebot:8080`. Update if you rename the service or domain.

### Price Tracker Hostname (`pricetracker.lab.mattsmith.tech`)
`caddy/Caddyfile` proxies `pricetracker.lab.mattsmith.tech` (and the `pt/` shortcut) to `http://price-tracker-web:8000`. Update if you rename the service or domain.

### Calibre Web Hostname (`books.lab.mattsmith.tech`)
`caddy/Caddyfile` proxies `books.lab.mattsmith.tech` (and the `books/` shortcut) to `http://calibre-web-automated:8083`. Update if you rename the service or domain.

### Timezone (`America/Indiana/Indianapolis`)
Set for Pihole, Jellyfin, and Calibre Web in `docker-compose.yml`. Update the `TZ` environment variable on each service to match your timezone.

### Pihole Web Password
`FTLCONF_webserver_api_password: '2get2pihole'` is hardcoded in `docker-compose.yml`. This should be moved to `.env` as `PIHOLE_PASSWORD` and referenced as `${PIHOLE_PASSWORD}`.

### Jellyfin User/Group IDs (`PUID=1000`, `PGID=1000`)
Set in `docker-compose.yml` for the `jellyfin` service. These should match the UID/GID of the user that owns your media files on the host. Run `id` on the host to check.

### NVIDIA GPU (Jellyfin)
`docker-compose.yml` reserves an NVIDIA GPU for the Jellyfin container using the `nvidia` driver and sets `NVIDIA_VISIBLE_DEVICES=all`. This requires an NVIDIA GPU and the NVIDIA Container Toolkit on the host. Remove or replace the `deploy.resources.reservations.devices` block and the `NVIDIA_*` environment variables if using a different GPU vendor or no hardware transcoding.

### Volume Backup — OneDrive Path
`volume-backup/backup.sh` uploads to `onedrive:/Documents/Homelab/Backups`. Update this path and the `rclone` remote name (`onedrive`) to match your rclone configuration.

### Volume Backup — Databases
`volume-backup/backup.sh` explicitly backs up `gravity.db`, `pihole-FTL.db`, `budget.db`, `tradebot.db`, and `price_tracker.db`. Add or remove entries here if you add or remove services with persistent SQLite databases. (The Calibre library — including its `metadata.db` — is deliberately kept out of the off-site backup and protected by ZFS instead.)

### "Jeremy Files" Shortcut
`caddy/Caddyfile` (`http://jeremy`) and `caddy/index.html` contain a personal OneDrive share link. Replace or remove this shortcut.

## Things to consider for new services
- Does it need reverse proxy
- Should it backup data
- Should it be added to index.html
- Does it need a redirect/shortcut in Caddyfile
- Documentation

