FROM ubuntu

RUN apt-get update -y && apt-get install -y \
  unionfs-fuse encfs openssh-server inotify-tools python3-pip
RUN pip3 install --upgrade --pre acdcli
