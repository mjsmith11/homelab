# Homelab
This repo contains the resources and instructions for my homelab setup centered around docker-compose.yml 
## Basic Setup
- Copy `.envexample` to `.env` and fill in variables
- `docker compose up`
## Services
### Timemachine
Server for mac backups. Note: It's currently hardcoded to 1 TB limit for backup data.
#### Prereqs
- avahi-daemon not running on host
- smbd not running on host
- nmbd not running on host
- afpd & netatalk not running on host
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
