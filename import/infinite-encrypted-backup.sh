#!/bin/bash

if [ -z "$ENC_PASSWORD" ]; then
  echo "\$ENC_PASSWORD is a required environment variable!!"
  exit 1
fi

AMZN_DIR="clouddrive_backup"
DATA_DIR="proxy_to_${NAME}_directory"
ENC_DATA_DIR="/.$DATA_DIR"
DEC_DATA_DIR="/$DATA_DIR"
ENC_AMZN_DIR="/.$AMZN_DIR"
DEC_AMZN_DIR="/$AMZN_DIR"
FUSED_DIR="/$NAME"
ENCRYPT_PW="echo $ENC_PASSWORD"

# make directories to be used
mkdir -p "$DEC_DATA_DIR" "$ENC_DATA_DIR" "$DEC_AMZN_DIR" "$ENC_AMZN_DIR" "$FUSED_DIR" ~/.cache/acd_cli

# if no key is being imported,
if [ ! -f "$KEY" ]; then
  # specify dir in which to store encrypted and unencrypted files, in that order
  encfs --standard --extpass="$ENCRYPT_PW" "$ENC_DATA_DIR" "$DEC_DATA_DIR"
  fusermount -u "$DEC_DATA_DIR" # unmount the filesystem

  # Security Critical!! (moves encryption key from sync dir to $IMPORT_DIR)
  mv "$ENC_DATA_DIR"/.encfs6.xml "$KEY"
else
  echo "FOUND PRE-EXISTING KEY TO IMPORT. USING: $KEY"
  ENCFS6_CONFIG="$KEY" encfs --extpass="$ENCRYPT_PW" "$ENC_DATA_DIR" "$DEC_DATA_DIR"
fi

# fuse local drive directory with clouddrive directory
unionfs-fuse -o cow "$DEC_DATA_DIR"=RW:$DEC_AMZN_DIR=RO "$FUSED_DIR"

# Reference key location to be used by encfs
ENCFS6_CONFIG="$KEY" encfs --extpass="$ENCRYPT_PW" "$ENC_DATA_DIR" "$DEC_DATA_DIR"

cp "$OAUTH_DATA" ~/.cache/acd_cli/oauth_data
acd_cli sync
acd_cli mount $ENC_AMZN_DIR

# setup decryption layer for amzn dir
ENCFS6_CONFIG="$KEY" encfs --extpass="$ENCRYPT_PW" $ENC_AMZN_DIR $DEC_AMZN_DIR

DEC_DATA_DIR="$ENC_DATA_DIR" ENCRYPT_PW="$ENCRYPT_PW" KEY="$KEY" ENC_DATA_DIR="$ENC_DATA_DIR" FUSED_DIR="$FUSED_DIR" nodejs /app/index.js

# TODO Cron job to delete files older than two weeks:
#   0 4 * * * find $ENC_DATA_DIR -type f -mtime +14 -exec rm -rf {} \;
#   #  (delete directories with: find . -type d -empty -delete)
