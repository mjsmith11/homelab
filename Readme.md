# Homelab
This repo contains the resources and instructions for my homelab setup centered around docker-compose.yml 
## Basic Setup
- Copy `.envexample` to `.env` and fill in variables
- `docker network create caddy`
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

#### Additional Setup
1. Configure to pull certs (details TODO)
1. Add local dns record to point domain to the server's ip
1. Add local dns records for everything that is reverse proxied
1. Add local dns records for everything all url shortcuts

### Pihole
DNS Server and Ad filtering
#### Prereqs
- Firewall port 53 open
- Nothing listening on port 53 of host (see https://www.turek.dev/posts/disable-systemd-resolved-cleanly/)
- Static IP

## Things to consider for new services
- Does it need reverse proxy
- Should it backup data
- Should it be added to index.html
- Does it need a redirect/shortcut in Caddyfile
