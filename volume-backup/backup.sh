#!/bin/bash

set -e

SOURCE_DIR="/data"
TMP_DIR="/tmp/backups"
DATE=$(date +"%Y-%m-%d")
ARCHIVE_NAME="backup-$DATE.zip"

mkdir -p $TMP_DIR

echo "Backing up SQLite databases..."
sqlite3 /data/pihole_data/gravity.db ".backup '$TMP_DIR/gravity.db'"
sqlite3 /data/pihole_data/pihole-FTL.db ".backup '$TMP_DIR/pihole-FTL.db'"
sqlite3 /data/budget_data/budget.db ".backup '$TMP_DIR/budget.db'"

echo "Creating archive..."
zip -r "$TMP_DIR/$ARCHIVE_NAME" "$SOURCE_DIR"
zip "$TMP_DIR/$ARCHIVE_NAME" "$TMP_DIR/gravity.db" "$TMP_DIR/pihole-FTL.db" "$TMP_DIR/budget.db"

echo "Uploading to OneDrive..."
rclone copy "$TMP_DIR/$ARCHIVE_NAME" onedrive:/Documents/Homelab/Backups

echo "Removing local temp files..."
rm "$TMP_DIR/$ARCHIVE_NAME" "$TMP_DIR/gravity.db" "$TMP_DIR/pihole-FTL.db" "$TMP_DIR/budget.db"

echo "Deleting remote files older than 30 days..."
rclone delete onedrive:/Documents/Homelab/Backups --min-age 30d

echo "Done."