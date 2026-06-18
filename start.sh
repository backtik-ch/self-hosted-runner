#!/bin/bash
set -euo pipefail

echo "Starting org runner entrypoint..."

: "${ORG:?ORG is required, example: my-org}"
: "${NAME:=runner}"

# ---- READ GITHUB TOKEN FROM DOCKER SECRET OR ENV ----
GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-/run/secrets/github_runner_pat}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  if [ ! -f "$GITHUB_TOKEN_FILE" ]; then
    echo "GITHUB_TOKEN or GITHUB_TOKEN_FILE is required."
    echo "Missing GitHub PAT secret file: $GITHUB_TOKEN_FILE"
    exit 1
  fi

  GITHUB_TOKEN="$(cat "$GITHUB_TOKEN_FILE")"
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN or GITHUB_TOKEN_FILE is required}"

# ---- FIX DOCKER SOCKET PERMISSIONS ----
if [ -S /var/run/docker.sock ]; then
  DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"
  echo "Docker socket GID: $DOCKER_GID"

  if getent group docker >/dev/null; then
    groupmod -g "$DOCKER_GID" docker || true
  else
    groupadd -g "$DOCKER_GID" docker
  fi

  usermod -aG docker docker
else
  echo "Warning: /var/run/docker.sock not found. Docker inside jobs may not work."
fi

chown -R docker:docker /home/docker

# ---- FUNCTION TO GET ORG REGISTRATION TOKEN ----
get_registration_token() {
  curl -fsSL \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${ORG}/actions/runners/registration-token" \
  | jq -r '.token'
}

# ---- FUNCTION TO GET ORG REMOVE TOKEN ----
get_remove_token() {
  curl -fsSL \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${ORG}/actions/runners/remove-token" \
  | jq -r '.token'
}

echo "Getting GitHub org runner registration token..."

REG_TOKEN="$(get_registration_token)"

if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" = "null" ]; then
  echo "Failed to get GitHub registration token."
  exit 1
fi

RUNNER_NAME="${NAME}-$(hostname)"
CLEANED_UP=0

cleanup() {
  if [ "$CLEANED_UP" -eq 1 ]; then
    return
  fi

  CLEANED_UP=1

  echo "Cleanup started..."

  if [ -f /home/docker/actions-runner/.runner ]; then
    echo "Getting GitHub org runner remove token..."

    REMOVE_TOKEN="$(get_remove_token || true)"

    if [ -n "${REMOVE_TOKEN:-}" ] && [ "$REMOVE_TOKEN" != "null" ]; then
      echo "Removing runner from GitHub..."

      su - docker -c "
        cd /home/docker/actions-runner || exit 0
        ./config.sh remove --unattended --token '${REMOVE_TOKEN}' || true
      "
    else
      echo "Could not get remove token. Skipping GitHub runner removal."
    fi
  fi

  echo "Cleaning workspace..."
  rm -rf /home/docker/actions-runner/_work/* || true

  echo "Cleaning temp..."
  rm -rf /tmp/* || true

  echo "Cleaning caches..."
  rm -rf /home/docker/.cache/* || true
  rm -rf /root/.cache/* || true

  if command -v docker >/dev/null 2>&1 && [ -S /var/run/docker.sock ]; then
    echo "Cleaning docker..."
    docker system prune -af || true
  fi

  echo "Cleanup finished."
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

echo "Switching to docker user..."

set +e
su - docker -c "
  set -e

  export ORG='${ORG}'
  export REG_TOKEN='${REG_TOKEN}'
  export RUNNER_NAME='${RUNNER_NAME}'

  echo 'Running as:' \$(whoami)
  echo 'Org:' \$ORG
  echo 'Runner name:' \$RUNNER_NAME

  cd /home/docker/actions-runner

  if [ ! -f .runner ]; then
    echo 'Configuring org runner...'

    ./config.sh \
      --url https://github.com/\${ORG} \
      --token \${REG_TOKEN} \
      --name \${RUNNER_NAME} \
      --unattended \
      --replace
  else
    echo 'Runner already configured.'
  fi

  echo 'Starting runner...'
  ./run.sh
"
EXIT_CODE=$?
set -e

cleanup

exit "$EXIT_CODE"
