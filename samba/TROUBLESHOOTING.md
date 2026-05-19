# Samba Troubleshooting Notes

## macOS SMB client (`smbx`) quirks

- `mount_smbfs -o hard` is **not supported** — option is rejected
- Power management can suspend the SMB session during idle periods (encode pauses, between passes) — `caffeinate -dimsu` prevents this
- Finder can interfere with open SMB sessions — quitting Finder during long operations is worth trying
- `/etc/nsmb.conf` useful settings: `notify_off=yes`, `streams=no`

### macOS SMB kernel tuning parameters

These are the actual tunable sysctls (discovered via `sysctl -a | grep -i smb`):

```
net.smb.fs.kern_soft_deadtimer   # default 30s  — timeout for SOFT mounts
net.smb.fs.kern_deadtimer        # default 60s  — timeout for ALL mounts (fires ECONNRESET)
net.smb.fs.kern_hard_deadtimer   # default 600s — absolute maximum
net.smb.fs.maxread               # default 8388608 (8MB) — max bytes per SMB READ request
net.smb.fs.maxwrite              # default 8388608 (8MB)
net.smb.fs.tcpsndbuf             # default 2097152 (2MB)
net.smb.fs.tcprcvbuf             # default 2097152 (2MB)
```

`net.smb.fs.kern_smb_timo` does **not exist** despite being commonly mentioned online.

Recommended values when reading large files from a slow/contended HDD:
```bash
sudo sysctl -w net.smb.fs.kern_soft_deadtimer=300
sudo sysctl -w net.smb.fs.kern_deadtimer=600
sudo sysctl -w net.smb.fs.maxread=65536
```

Persist across reboots via `/etc/sysctl.conf` (create if it doesn't exist). Changes take effect immediately without remounting.

`maxread` reduction from 8MB to 64KB is the most impactful for reliability under disk contention — smaller chunks each complete faster, staying well under the dead timer.

## Native Samba vs Docker Samba

- Docker Samba (`ghcr.io/servercontainers/samba`) mounts smb.conf as `:ro` — see servercontainers section below
- Native Samba logs to `/var/log/samba/log.<client-hostname>`, essential for diagnosing connection drops
- `log file = /dev/stdout` crashes native smbd when run under systemd (no tty) — use `log file = /var/log/samba/log.%m`
- Native smbd crashes with ABRT if it can't bind to any port — always check `ss -tlnp | grep <port>` if it fails to start

## dperson/samba image is broken for macOS

- `dperson/samba` ships Samba 4.12.2 (2020, abandoned). Segfaults (Signal 11) in any smbd child process when `catia`, `fruit`, or `streams_xattr` VFS modules are loaded — affects all macOS clients
- Switch to `ghcr.io/servercontainers/samba` which ships 4.22+
- `lscr.io/linuxserver/samba` and `ghcr.io/linuxserver/samba` do **not exist** — the "denied" error from the registry means the image isn't published, not a firewall issue (linuxserver/jellyfin on lscr.io works fine, proving the registry is reachable)

## servercontainers/samba image config

- Image generates its own `/etc/samba/smb.conf` from env vars at startup
- **Mounting a custom smb.conf as `:ro` works** — the entrypoint logs "Read-only file system" errors but continues and uses your file. testparm output and `docker logs` will confirm your settings are active.
- Only a whitelist of ~4 `SAMBA_CONF_*` env vars are actually written to smb.conf: `LOG_LEVEL`, `WORKGROUP`, `SERVER_STRING`, `MAP_TO_GUEST`. All others (socket options, protocol, AIO, etc.) are silently ignored. Use a mounted smb.conf to guarantee settings are applied.
- When mounting a custom smb.conf, add `log file = /dev/stdout` explicitly — the image normally injects this but your file overrides it, so smbd logs go to `/var/log/samba/log.smbd` inside the container instead of docker stdout
- Share definitions via `SAMBA_VOLUME_CONFIG_<name>` as a multiline YAML block containing the full `[sharename]` stanza — ignored if smb.conf is mounted `:ro` (the append fails silently)
- User accounts via `ACCOUNT_<username>: <password>` — creates both OS and Samba user; required because macOS Ventura+ blocks guest SMB connections by default; this env var works regardless of smb.conf mounting
- Per-share `vfs objects = ...` **replaces** the global value for that share only — use this to strip modules the share doesn't need
- Default global config injected by the image includes `vfs objects = catia fruit streams_xattr`, `fruit:model = TimeCapsule`, `fruit:metadata = stream` — these appear even when using `SAMBA_CONF_*` env vars
- Override `fruit:model = MacSamba` per-share to avoid macOS applying Time Machine connection logic to a regular share
- Log level 2 minimum is required to see client connection and disconnect events in logs. Level 1 only shows level-0 errors (e.g. `vfs_fruit.c` failures). Level 2 adds session open/close events.

## macOS SMB error codes

- **Error -50** (`paramErr`): catch-all for early connection failures. Common causes: `force user` pointing to a non-existent OS user; `streams_xattr` segfault (dperson 4.12.2); fruit module trying to write Apple metadata to a directory the guest user can't write to; SMB protocol negotiation rejected by macOS
- **Error 100057** (`ECONNRESET`): the TCP connection was reset. Multiple causes:
  - `kern_deadtimer` fired — Samba took longer than the dead timer to respond to a READ/WRITE request (most common on HDD under disk contention). Fix: increase `kern_deadtimer` and reduce `maxread` on the Mac.
  - `oplocks = no` conflicting with SMB3 lease negotiation — macOS negotiates SMB2/3 leases even when Samba has oplocks disabled at the application level; fix by adding `max protocol = SMB2` or removing the fruit VFS stack from the share
  - Hairpin NAT reset — see section below

## Large file transfer failures (macOS → Samba)

- If ping works while the copy is frozen, it is an SMB-level stall, not a network problem
- **Approximately the same size every time** = timing issue. At a roughly constant transfer speed, same elapsed time = same bytes transferred. The macOS `kern_deadtimer` is firing after a consistent duration because disk contention causes Samba to stall responding to reads.
- **Exactly the same byte count every time** = bad sector. The HDD is retrying a specific sector, stalling for 30+ seconds per attempt. Check `dmesg | grep -iE "I/O error|failed command|sector"` — note `sr0` errors are the optical drive (normal during rips), not the data disk.
- `use sendfile = yes` **breaks reads** when `streams_xattr` or `fruit` is in the VFS stack — sendfile bypasses the VFS layer so alternate data streams (Apple metadata) can't be intercepted; macOS aborts mid-transfer
- `oplocks = no` + `level2 oplocks = no` prevents freeze when another process (e.g. Jellyfin) opens the same file — without this, Samba sends an oplock break and waits indefinitely for macOS to acknowledge
- `kernel oplocks = no` is deprecated in Samba 4.x — causes error 100057 when combined with SMB2/3 lease negotiation; do not use
- For plain file shares (MKV, etc.) where Apple metadata is irrelevant, use `vfs objects = catia` per-share to strip fruit/streams_xattr entirely, and cap at `max protocol = SMB2`
- AIO (`aio read size`, `aio write size`) is enabled by default in Samba 4.22 (compiled default = 1). No config needed. Testparm won't show it since it matches the default. AIO allows smbd to queue disk reads asynchronously, keeping the TCP connection alive while waiting for a slow disk.

## Disk contention (multiple concurrent readers/writers)

- Simultaneous HDD workloads (e.g. Jellyfin encoding + Samba large file read + Bluray rip write) cause each reader's effective throughput to drop dramatically due to head seeks
- `mq-deadline` (the common modern Linux I/O scheduler) **ignores** Docker `blkio_config: weight` — that setting only works with `bfq` or `cfq` schedulers. Check with `cat /sys/block/sdX/queue/scheduler`.
- BFQ scheduler supports per-process I/O priorities and `blkio_config` weighting. Switch with `echo bfq > /sys/block/sdX/queue/scheduler`. Persist via udev rule: `ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"`
- With `mq-deadline`, the only options are: increase macOS timers, reduce `maxread`, or accept that concurrent heavy I/O will slow or disconnect transfers

## Hairpin NAT

- Connecting via a public domain name (e.g. `smb://lab.example.com:1445`) from a LAN client routes traffic through the router twice (out WAN, back in LAN) — hairpin NAT
- Under heavy disk I/O, if Samba response slows, some routers mishandle the long-lived NAT session and send a RST, causing ECONNRESET (100057) on the Mac
- Test: mount using the server's local IP (`smb://192.168.x.x:1445/share`) to bypass router NAT entirely. If that works and the domain name doesn't, the router is the culprit.

## Guest access and permissions

- macOS Ventura+ disables guest SMB connections by default — use a real Samba user (`ACCOUNT_username`) instead of `guest ok = yes`
- `force user = nobody` in a share section causes connections to fail entirely in servercontainers/samba — do not use
- Guest connections map to the `nobody` user (UID 65534); the share directory on the host must be world-writable (`chmod 777`) or owned by UID 65534 for writes to work

## Non-standard port

- `smb ports = 1445` moves smbd off port 445 without any other changes needed
- Required when another service (e.g. timemachine Docker container) owns port 445

## ZFS + Samba

- Child ZFS datasets mounted inside the share root need the **execute bit** on directories (`drwxrw-rw-` has no execute for group/others — chdir fails)
- `force user = <owner>` in `[share]` is the cleanest fix — all file ops run as that user, bypassing permission juggling
- `fruit:metadata = netatalk` causes `ad_convert()` failures on Linux-created files with no AppleDouble metadata; add `fruit:convert = false` to suppress the conversion attempts and log spam

## Diagnostic commands

```bash
# Watch logs live (native)
sudo tail -f /var/log/samba/log.*

# Watch logs live (Docker)
docker logs -f samba

# Get logs since a specific time (Docker) — timestamp in UTC
docker logs samba --since "2026-05-18T23:00:00Z" 2>&1

# Check what's actually in the running smb.conf
docker exec samba testparm -s 2>/dev/null

# Confirm specific settings are active
docker exec samba testparm -s 2>/dev/null | grep -E "aio|socket options|protocol|vfs"

# Watch TCP connection state
watch -n 1 'ss -tnp | grep 1445'

# Watch active connections and locks
watch -n 2 'sudo smbstatus'

# Capture full log for post-mortem (native)
sudo journalctl -u smbd -f > /tmp/smbd.log &

# macOS SMB log
log stream --predicate 'subsystem == "com.apple.smb"' --level debug > /tmp/smb-mac.log

# Check macOS SMB tuning parameters
sysctl -a 2>/dev/null | grep -i smb

# Verify running config
sudo testparm -s 2>/dev/null | grep -A 10 "\[share\]"

# Check for disk I/O errors (sr0 = optical drive, normal during rips)
dmesg | grep -iE "I/O error|failed command|sector|ata[0-9]" | tail -20

# Check I/O scheduler for a disk
cat /sys/block/sda/queue/scheduler
```

## HandBrake over SMB from macOS

- M3 Pro media engine is significantly better than GTX 1060 for H.264/H.265 — encode locally, read source over SMB
- Connection drops during multipass encodes are a known pain point with macOS SMB client
- Run `caffeinate -dimsu` for the duration of the encode to prevent macOS power management from suspending the session
- Log pattern at failure: reads stop → `qfsinfo level=1003` → burst of `fcntl_getlock` → silent TCP drop (no disconnect in Samba logs)
