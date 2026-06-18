#!/bin/bash
set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*" >&2
}

log "Starting org runner entrypoint..."

: "${ORG:?ORG is required, example: my-org}"
: "${NAME:=runner}"

log "Environment validated."
log "Organization: ${ORG}"
log "Runner name prefix: ${NAME}"
log "Hostname: $(hostname)"

# ---- READ GITHUB TOKEN FROM DOCKER SECRET OR ENV ----
GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-/run/secrets/github_runner_pat}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  log "GITHUB_TOKEN env var is not set. Reading token from file: ${GITHUB_TOKEN_FILE}"

  if [ ! -f "$GITHUB_TOKEN_FILE" ]; then
    log "GITHUB_TOKEN or GITHUB_TOKEN_FILE is required."
    log "Missing GitHub PAT secret file: $GITHUB_TOKEN_FILE"
    exit 1
  fi

  GITHUB_TOKEN="$(cat "$GITHUB_TOKEN_FILE")"
  log "GitHub token loaded from Docker secret file."
else
  log "GitHub token loaded from GITHUB_TOKEN env var."
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN or GITHUB_TOKEN_FILE is required}"
log "GitHub token is present."

# ---- FIX DOCKER SOCKET PERMISSIONS ----
log "Checking Docker socket..."

if [ -S /var/run/docker.sock ]; then
  DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"
  log "Docker socket found."
  log "Docker socket GID: $DOCKER_GID"

  if getent group docker >/dev/null; then
    log "docker group exists. Updating docker group GID to ${DOCKER_GID}..."
    groupmod -g "$DOCKER_GID" docker || true
    log "docker group GID update finished."
  else
    log "docker group does not exist. Creating docker group with GID ${DOCKER_GID}..."
    groupadd -g "$DOCKER_GID" docker
    log "docker group created."
  fi

  log "Adding docker user to docker group..."
  usermod -aG docker docker
  log "docker user group membership update finished."
else
  log "Warning: /var/run/docker.sock not found. Docker inside jobs may not work."
fi

log "Fixing /home/docker ownership..."
chown -R docker:docker /home/docker
log "/home/docker ownership fixed."

# ---- FUNCTION TO GET ORG REGISTRATION TOKEN ----
get_registration_token() {
  log "Calling GitHub registration-token endpoint for org ${ORG}..."

  curl -fsSL \
    --connect-timeout 10 \
    --max-time 30 \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${ORG}/actions/runners/registration-token" \
  | jq -r '.token'
}

# ---- FUNCTION TO GET ORG REMOVE TOKEN ----
get_remove_token() {
  log "Calling GitHub remove-token endpoint for org ${ORG}..."

  curl -fsSL \
    --connect-timeout 10 \
    --max-time 30 \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${ORG}/actions/runners/remove-token" \
  | jq -r '.token'
}

log "Getting GitHub org runner registration token..."

REG_TOKEN="$(get_registration_token)"

if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" = "null" ]; then
  log "Failed to get GitHub registration token."
  exit 1
fi

log "GitHub registration token fetched."

RUNNER_NAME="${NAME}-$(hostname)"
log "Full runner name: ${RUNNER_NAME}"

CLEANED_UP=0

cleanup() {
  if [ "$CLEANED_UP" -eq 1 ]; then
    log "Cleanup already ran. Skipping duplicate cleanup."
    return
  fi

  CLEANED_UP=1

  log "Cleanup started..."

  if [ -f /home/docker/actions-runner/.runner ]; then
    log "Runner config exists. Getting GitHub org runner remove token..."

    REMOVE_TOKEN="$(get_remove_token || true)"

    if [ -n "${REMOVE_TOKEN:-}" ] && [ "$REMOVE_TOKEN" != "null" ]; then
      log "GitHub remove token fetched."
      log "Removing runner from GitHub..."

      su - docker -c "
        echo '[cleanup] Running removal as:' \$(whoami)
        cd /home/docker/actions-runner || exit 0
        echo '[cleanup] Current directory:' \$(pwd)
        ./config.sh remove --unattended --token '${REMOVE_TOKEN}' || true
      "
      log "Runner removal command finished."
    else
      log "Could not get remove token. Skipping GitHub runner removal."
    fi
  else
    log "Runner config does not exist. Skipping GitHub runner removal."
  fi

  log "Cleaning workspace..."
  rm -rf /home/docker/actions-runner/_work/* || true
  log "Workspace cleaned."

  log "Cleaning temp..."
  rm -rf /tmp/* || true
  log "Temp cleaned."

  log "Cleaning caches..."
  rm -rf /home/docker/.cache/* || true
  rm -rf /root/.cache/* || true
  log "Caches cleaned."

  if command -v docker >/dev/null 2>&1 && [ -S /var/run/docker.sock ]; then
    log "Cleaning docker..."
    docker system prune -af || true
    log "Docker cleanup finished."
  else
    log "Docker cleanup skipped. docker command or socket unavailable."
  fi

  log "Cleanup finished."
}

trap 'log "Received INT signal."; cleanup; exit 130' INT
trap 'log "Received TERM signal."; cleanup; exit 143' TERM

log "Switching to docker user..."
log "Preparing runner process..."

set +e
su - docker -c "
  set -e

  echo '[runner] Shell started as:' \$(whoami)

  export ORG='${ORG}'
  export REG_TOKEN='${REG_TOKEN}'
  export RUNNER_NAME='${RUNNER_NAME}'

  echo '[runner] Org:' \$ORG
  echo '[runner] Runner name:' \$RUNNER_NAME

  echo '[runner] Changing directory to /home/docker/actions-runner...'
  cd /home/docker/actions-runner
  echo '[runner] Current directory:' \$(pwd)

  if [ ! -f .runner ]; then
    echo '[runner] .runner file not found. Configuring org runner...'

    ./config.sh \
      --url https://github.com/\${ORG} \
      --token \${REG_TOKEN} \
      --name \${RUNNER_NAME} \
      --unattended \
      --replace

    echo '[runner] Runner configuration finished.'
  else
    echo '[runner] Runner already configured.'
  fi

  echo '[runner] Starting runner...'
  ./run.sh
"
EXIT_CODE=$?
set -e

log "Runner process exited with code ${EXIT_CODE}."

cleanup

log "Entrypoint exiting with code ${EXIT_CODE}."
exit "$EXIT_CODE"
