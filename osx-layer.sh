#!/bin/bash

#FIXME: trap SIGINT SIGTERM and kill script. Recursive calls are preventing
#       termination

NAME=${NAME:-amazon-cloud-drive}
PLACE_SYMLINK_AT=${1:-$HOME/Desktop/}
IMPORT_DIR=${IMPORT_DIR:-/import}
SSH_PORT=1234
# helps host manage guest (container)
SSH_OPTS="NoHostAuthenticationForLocalhost=yes"
PWD=$(pwd)

which sshfs > /dev/null
if [[ $? -gt 0 ]]; then
  echo "sshfs must be installed on the host (osx) system"
  return 1
fi

echo "# !!Warning!!
# - this script will replace any existing docker image tagged name:$NAME
# - this script will replace any existing docker container named $NAME
#     Replacing the container will ONLY clear the following:
#       - OSX filesystem metadata that exist as 'attrib' changes to inotifywait
#       - Any data that has not yet synced from the existing container to ACD..
#           just don't run this shortly after any large file additions to share.
# - this script will kill any running sshfs processes on host (osx)
#     As an assurance against sshfs bug. If you have other sshfs mounts (you
#     don't), they will need to be reestablished.
"
read -r -p "Are you sure? [Y/n]" RESPONSE
RESPONSE=$(echo "$RESPONSE" | tr "[:upper:]" "[:lower:]")
echo "$RESPONSE"
if [[ ! $RESPONSE =~ ^(yes|y| ) ]]; then
  return 1;
fi

PUB_KEY="$HOME/.ssh/id_rsa.pub"
if [ ! -f "$PUB_KEY" ]; then
  echo "pub key must exist for script. Trying $PUB_KEY"
  return 1;
fi

# this resolves infrequent bug w/ dissociated mountpoint. stops SSHFS manually.
pkill -9 sshfs
umount -f "$PWD"/"$NAME" > /dev/null 2>&1 || true
docker rm -f "$NAME" > /dev/null 2>&1 || true

# build image used by container
docker build -t name:"$NAME" .

echo "spinning up docker container"
# (runs daemonized, privileged inotify container for acd with $NAME)
# Note: attrib goes nuts on OSX where filesystem metadata is vastly utilized
#       to enable: "SYNC_MONITORS=create,modify,attrib,move,delete"
docker run \
  -d --name "$NAME" -p $SSH_PORT:22 \
  -e "NAME=$NAME" \
  -e "ENC_PASSWORD=$ENC_PASSWORD" \
  -e "IMPORT_DIR=$IMPORT_DIR" \
  -e "KEY=$IMPORT_DIR/ACD_DATA_KEY" \
  -e "OAUTH_DATA=$IMPORT_DIR/oauth_data" \
  -e "SYNC_MONITORS=create,modify,move,delete" \
  -v "$PWD""$IMPORT_DIR":"$IMPORT_DIR" \
  -w "$IMPORT_DIR" \
  --privileged --cap-add=ALL \
  name:"$NAME" /bin/bash \
  -c "$IMPORT_DIR/infinite-encrypted-backup.sh"

# echo PUB_KEY into container for ssh access
INSERT_KEY="mkdir -p /root/.ssh"
INSERT_KEY+=" && chmod 700 /root/.ssh"
INSERT_KEY+=" && touch /root/.ssh/authorized_keys"
INSERT_KEY+=" && chmod 640 /root/.ssh/authorized_keys"
INSERT_KEY+=" && echo '$(cat "$PUB_KEY")' >> /root/.ssh/authorized_keys"

echo "Waiting for docker container..."
check_container_availability() {
  docker exec -it "$NAME" /bin/bash -c "$INSERT_KEY"
  if [ $? -gt 0 ]; then
    sleep 3
    check_container_availability
  fi
}
check_container_availability

echo "Waiting for ssh..."
check_ssh_availability() {
  ssh -p $SSH_PORT -q -o $SSH_OPTS root@localhost exit
  if [ $? -gt 0 ]; then
    sleep 3
    check_ssh_availability
  fi
}
check_ssh_availability

# touch file to sshfs dir to test
echo "Mount Amazon Cloud Drive FUSE directory on host machine @ $PWD/$NAME"
rm -rf "$NAME"
mkdir "$NAME"
sshfs -p $SSH_PORT -o $SSH_OPTS root@localhost:/"$NAME" "$NAME"

# symlink to desktop
echo "Creating symlink @ $PLACE_SYMLINK_AT$NAME"
rm -rf "$PLACE_SYMLINK_AT""$NAME"
ln -s "$PWD"/"$NAME"/ "$PLACE_SYMLINK_AT"
