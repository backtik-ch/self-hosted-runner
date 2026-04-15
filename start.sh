#!/bin/bash
set -e

echo "Starting runner entrypoint..."

# ---- FIX DOCKER SOCKET PERMISSIONS ----
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
echo "Docker socket GID: $DOCKER_GID"

if getent group docker >/dev/null; then
  groupmod -g "$DOCKER_GID" docker || true
else
  groupadd -g "$DOCKER_GID" docker
fi

usermod -aG docker docker
chown -R docker:docker /home/docker

# ---- EXPORT ENV FOR CHILD ----
export REPO
export REG_TOKEN
export NAME

echo "Switching to docker user..."

# ---- RUN AS DOCKER USER ----
exec su - docker -c '
set -e

echo "Running as: $(whoami)"
echo "Repo: $REPO"

cd /home/docker/actions-runner || exit

if [ ! -f .runner ]; then
  echo "Configuring runner..."
  ./config.sh \
    --url https://github.com/${REPO} \
    --token ${REG_TOKEN} \
    --name ${NAME}-$(hostname) \
    --unattended \
    --replace
fi

cleanup() {
  echo "Removing runner..."
  ./config.sh remove --unattended --token ${REG_TOKEN}
}

trap "cleanup; exit 130" INT
trap "cleanup; exit 143" TERM

echo "Starting runner..."
exec ./run.sh
'
