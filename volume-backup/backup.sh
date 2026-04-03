#!/bin/bash

set -e

SOURCE_DIR="/data"
TMP_DIR="/tmp/backups"
DATE=$(date +"%Y-%m-%d")
ARCHIVE_NAME="backup-$DATE.zip"

mkdir -p $TMP_DIR

echo "Creating archive..."
docker compose down budget-backend
zip -r "$TMP_DIR/$ARCHIVE_NAME" "$SOURCE_DIR"
docker compose up -d budget-backend

echo "Uploading to OneDrive..."
rclone copy "$TMP_DIR/$ARCHIVE_NAME" onedrive:/Documents/Homelab/Backups

echo "Removing local temp file..."
rm "$TMP_DIR/$ARCHIVE_NAME"

echo "Deleting remote files older than 7 days..."
rclone delete onedrive:/Documents/Homelab/Backups --min-age 7d

echo "Done."