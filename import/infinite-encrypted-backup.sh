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

# install dependencies (ideally, already handled by dockerfile)
apt-get update -y
apt-get install -y unionfs-fuse encfs openssh-server inotify-tools python3-pip
pip3 install --upgrade --pre acdcli

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

# CRUD handler for acd_cli
echo -e '#!'"/bin/bash
FILENAME=\$(echo \$1 | cut -d/ -f3-)
ACTION=\$(echo \$1 | cut -d- -f2 | tr -d ' ')
ENCODEDIR=\$(ENCFS6_CONFIG=\"$KEY\" encfsctl encode --extpass=\"$ENCRYPT_PW\" $ENC_DATA_DIR \"/\$FILENAME\")
REALPATH=\"$ENC_DATA_DIR/\$ENCODEDIR\"

echo -e \"(\$\$) Filepath:\t/\$FILENAME\"
echo -e \"(\$\$) Action:\t\$ACTION\"
echo -e \"(\$\$) Realpath:\t\$REALPATH\"

# sync exact file to update or remove
if [[ \$1 != *\" - DELETE\"* && \$1 != *\"MOVED_FROM\"* ]]; then
  echo \"(\$\$) Uploading file: \$FILENAME @ \$REALPATH\"
  acd_cli upload \$REALPATH /
else
  echo \"(\$\$) Removing file: \$FILENAME @ \$REALPATH\"
  rm -r \$REALPATH
  acd_cli rm /\$ENCODEDIR
fi
acd_cli sync" > /bin/acd-sync
chmod +x /bin/acd-sync;

# pull remote file references to initialize. nothing to push up yet.
acd_cli sync

# setup ssh for exposure to host's sshfs mount
mkdir /var/run/sshd
sed -ri 's/^PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config
service ssh restart

# Script does the following:
#   - ignores system files when syncing
#     TODO: use array instead of so many shitty nested conditionals
#   - kills any sync (aka upload) processes that are in-progress for a file when
#     that file is modified again, even if the first upload was not yet complete
#     this is a janky attempt at debouncing when the filesystem updates a lot.
#     TODO: is there any way to prevent metadata updates from triggering a full
#           file re-upload, uploading new/modified metadata only?
# NOTE: this (-m) implementation avoids logfile requirement of daemonizing (-d)
inotifywait -mre "$SYNC_MONITORS" --timefmt '%G' --format '%T - %e - %w%f' \
  "$FUSED_DIR" | while read -r FILE; do \
    if [[ $FILE != *"/.TemporaryItems"* ]]; then \
      if [[ $FILE != *"DS_Store"* ]]; then \
        if [[ $FILE != *"/._"* ]]; then \
          if [[ $FILE != *"_HIDDEN~"* ]]; then \
            if [[ $FILE != *"/.unionfs-fuse"* ]]; then \
              PIDS=$(jobs -p 2>/dev/null | xargs ps -p 2>/dev/null | tail -n+2 | awk '{print $1,substr($0, index($0, $5))}' | grep "$FILE" | awk '{print $1}' | tr '\n' ' '); \
              if [[ $PIDS ]]; then echo "File sync already in progress. Killing PIDS: $PIDS"; kill -9 $PIDS; fi; \
              /bin/acd-sync "$FILE" & \
            fi; \
          fi; \
        fi; \
      fi; \
    fi; \
  done;

# TODO Cron job to delete files older than two weeks:
#   0 4 * * * find $ENC_DATA_DIR -type f -mtime +14 -exec rm -rf {} \;
#   #  (delete directories with: find . -type d -empty -delete)
