# Homelab
This repo contains the resources and instructions for my homelab setup centered around docker-compose.yml 
## Basic Setup
- Copy `.envexample` to `.env` and fill in variables
- `docker compose up`
## Services
### Timemachine
Server for mac backups. Note: It's currently hardcoded to 1 TB limit for backup data.
#### Prereqs
- avahi-daemon not running on host (`sudo systemctl stop avahi-daemon && sudo systemctl disable avihi-daemon`)
- smbd not running on host (`sudo systemctl stop smbd && sudo systemctl disable smbd`)
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

## Things to consider for new services
- Does it need reverse proxy
- Should it backup data
- Should it be added to index.html
- Does it need a redirect/shortcut in Caddyfile

