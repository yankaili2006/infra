#!/bin/bash
# Fix E2B template cache with password

BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
CACHE_ID="074f8a4c-3ecf-4fe7-9f36-34d56e52accf"
CACHE_DIR="/home/primihub/e2b-storage/e2b-template-cache/${BUILD_ID}/cache/${CACHE_ID}"
SOURCE_DIR="/home/primihub/e2b-storage/e2b-template-storage/${BUILD_ID}"

echo "Creating cache directory..."
echo "Primihub@2022." | sudo -S mkdir -p "$CACHE_DIR"

echo "Copying template files..."
echo "Primihub@2022." | sudo -S cp "$SOURCE_DIR/metadata.json" "$CACHE_DIR/"
echo "Primihub@2022." | sudo -S cp "$SOURCE_DIR/rootfs.ext4" "$CACHE_DIR/"

echo "Setting permissions..."
echo "Primihub@2022." | sudo -S chmod -R 755 "/home/primihub/e2b-storage/e2b-template-cache/${BUILD_ID}"
echo "Primihub@2022." | sudo -S chown -R primihub:primihub "/home/primihub/e2b-storage/e2b-template-cache/${BUILD_ID}"

echo "Verifying..."
ls -lh "$CACHE_DIR"

echo "Done! Cache directory created and populated."
