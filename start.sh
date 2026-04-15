#!/bin/bash

set -e

# Fix docker socket permissions
if [ -S /var/run/docker.sock ]; then
  DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
  echo "Docker socket GID: $DOCKER_GID"

  groupmod -g $DOCKER_GID docker 2>/dev/null || true
  usermod -aG docker docker
fi

# Switch to docker user
sudo -u docker bash <<EOF

cd /home/docker/actions-runner || exit

# ✅ IMPORTANT: use unattended mode + required flags
./config.sh \
  --url https://github.com/${REPO} \
  --token ${REG_TOKEN} \
  --name ${NAME} \
  --unattended \
  --replace \
  --work _work

cleanup() {
  echo "Removing runner..."
  ./config.sh remove --unattended --token ${REG_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh

EOF
