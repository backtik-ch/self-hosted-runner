#!/bin/bash
set -e

REPO=${REPO}
REG_TOKEN=${REG_TOKEN}
NAME=${NAME}

DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
echo "Docker socket GID: $DOCKER_GID"

if getent group docker >/dev/null; then
  groupmod -g "$DOCKER_GID" docker || true
else
  groupadd -g "$DOCKER_GID" docker
fi

usermod -aG docker docker

# ensure correct ownership
chown -R docker:docker /home/docker

exec su - docker -c "
cd /home/docker/actions-runner || exit

# Configure only if not already configured
if [ ! -f .runner ]; then
  ./config.sh \
    --url https://github.com/${REPO} \
    --token ${REG_TOKEN} \
    --name ${NAME}-\$(hostname) \
    --unattended \
    --replace
fi

cleanup() {
  echo 'Removing runner...'
  ./config.sh remove --unattended --token ${REG_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh
"
