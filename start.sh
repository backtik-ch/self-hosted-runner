#!/bin/bash

# 🔑 Fix docker socket permissions BEFORE dropping privileges
if [ -S /var/run/docker.sock ]; then
  DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
  echo "Docker socket GID: $DOCKER_GID"

  # Create or update docker group with correct GID
  sudo groupmod -g $DOCKER_GID docker 2>/dev/null || \
  sudo groupadd -g $DOCKER_GID docker

  sudo usermod -aG docker docker
fi

# 👇 switch to docker user BEFORE running runner
exec sudo -u docker bash <<'EOF'

cd /home/docker/actions-runner || exit

./config.sh --url https://github.com/${REPO} --token ${REG_TOKEN} --name ${NAME}

cleanup() {
  echo "Removing runner..."
  ./config.sh remove --unattended --token ${REG_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh
EOF
