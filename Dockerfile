FROM ubuntu

RUN apt-get update -y && apt-get install -y \
  unionfs-fuse encfs openssh-server inotify-tools python3-pip

RUN pip3 install --upgrade --pre acdcli
RUN apt-get install -y npm
RUN npm init -y
RUN mkdir /app
RUN cd /app && npm i chokidar async

# setup ssh for exposure to host's sshfs mount
RUN mkdir /var/run/sshd
RUN sed -ri 's/^PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config

EXPOSE 22

#COPY import/package.json /app/
COPY import/index.js /app/
