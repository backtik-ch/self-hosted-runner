# Self-Hosted Runner Dockerization

Docker image and Compose stack for GitHub Actions self-hosted runners registered at organization level.

The stack runs 5 runner containers for the whole GitHub organization instead of attaching runners to individual repositories.

## Configuration

Create a `.env` file:

```sh
ORG=backtik-ch
NAME=org-runner
```

- `ORG`: GitHub organization where runners are registered.
- `NAME`: Runner name prefix. The container hostname is appended automatically.

## GitHub PAT Secret

Create the Docker secret expected by `docker-compose.yml`:

```sh
printf '%s' 'github_pat_xxxxxxxxxxxxxxxxx' | docker secret create github_runner_pat -
```

The PAT must be allowed to create organization runner registration tokens.

## GitHub Tokens

The container fetches a fresh registration token automatically at startup:

```sh
curl -fsSL \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/orgs/${ORG}/actions/runners/registration-token" \
| jq -r '.token'
```

During cleanup, it also fetches a fresh remove token:

```sh
curl -fsSL \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/orgs/${ORG}/actions/runners/remove-token" \
| jq -r '.token'
```

## Deploy

```sh
docker stack deploy -c docker-compose.yml github-runners
```

The stack declares 5 replicas:

```yaml
deploy:
  mode: replicated
  replicas: 5
```

## Files

- `Dockerfile`: Builds the GitHub Actions runner image with Docker CLI access.
- `start.sh`: Reads the PAT secret, fetches an organization registration token, configures the runner, and removes it on shutdown.
- `docker-compose.yml`: Deploys 5 organization runners and mounts the Docker socket.
