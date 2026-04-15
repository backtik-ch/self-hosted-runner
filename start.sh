#!/bin/bash

# Fix docker socket permissions dynamically
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)

echo "Docker socket GID: $DOCKER_GID"

# Create or update docker group to match socket
if getent group docker >/dev/null; then
  echo "Updating docker group GID"
  groupmod -g "$DOCKER_GID" docker
else
  echo "Creating docker group"
  groupadd -g "$DOCKER_GID" docker
fi

# Add user to docker group
usermod -aG docker docker

# Refresh group membership
newgrp docker <<EOF
echo "Docker group applied"
EOF

REPO=$REPO
REG_TOKEN=$REG_TOKEN
NAME=$NAME

cd /home/docker/actions-runner || exit
./config.sh --url https://github.com/${REPO} --token ${REG_TOKEN} --name ${NAME}

cleanup() {
  echo "Removing runner..."
  ./config.sh remove --unattended --token ${REG_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh & wait $!
