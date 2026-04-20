#!/bin/bash +e

filehash() {
  sha256sum "$1" | awk '{print $1}'
}

require_env() {
  if [ -z "${!1}" ]; then
    echo "Error: required environment variable $1 is not set" >&2
    exit 1
  fi
}

compose_handle() {
  local dir="$1"
  local enabled="$2"
  local files="-f $dir/docker-compose.yml"
  
  if [ "$MONITORING_ENABLED" = "true" ] && [ -f "$dir/docker-compose.monitoring.yml" ]; then
    files="$files -f $dir/docker-compose.monitoring.yml"
  fi

  if [ "$enabled" = "true" ]; then
    echo "Starting $dir container(s)..."
    docker compose $files up -d
  else
    echo "$dir is disabled. Stopping..."
    docker compose $files down
  fi
}

: "${TZ:=UTC}"
: "${DATA_DIR:=/srv}"
: "${AUTOHEAL_ENABLED:=true}"
: "${WATCHTOWER_ENABLED:=true}"

export TZ DATA_DIR
export HOSTNAME=$(hostname)

if [ "$AUTOHEAL_ENABLED" = "true" ]; then
  echo "Starting autoheal..."
  compose_up autoheal
fi

if [ "$OFELIA_ENABLED" = "true" ]; then
  echo "Starting ofelia..."
  compose_up backup
fi

if [ "$MONITORING_ENABLED" = "true" ]; then
  export PROMETHEUS_SCRAPE_INTERVAL="${PROMETHEUS_SCRAPE_INTERVAL:-15s}"
  require_env PROMETHEUS_REMOTE_WRITE_URL
  require_env PROMETHEUS_REMOTE_WRITE_USER
  require_env PROMETHEUS_REMOTE_WRITE_PASSWORD
  echo "Starting monitoring containers..."
  envsubst < prometheus-agent/config/prometheus.yml.tmpl > prometheus-agent/config/prometheus.yml
  chown 65534:899 prometheus-agent/config/prometheus.yml
  chmod 755 prometheus-agent/config/prometheus.yml
  export PROMETHEUS_CONFIG_HASH=$(filehash prometheus-agent/config/prometheus.yml)
fi
compose_handle prometheus-agent $MONITORING_ENABLED
compose_handle node-exporter $MONITORING_ENABLED
compose_handle cadvisor $MONITORING_ENABLED

if [ "$WATCHTOWER_ENABLED" = "true" ]; then
  echo "Starting watchtower..."
  export WATCHTOWER_DOCKER_CONFIG_JSON="${WATCHTOWER_DOCKER_CONFIG_JSON:-{\}}"
  envsubst < watchtower/config/config.json.tmpl > watchtower/config/config.json
  chmod 600 watchtower/config/config.json
fi
compose_handle watchtower $WATCHTOWER_ENABLED

if [ "$TRAEFIK_ENABLED" = "true" ]; then
  require_env LETSENCRYPT_EMAIL
  require_env CLOUDFLARE_API_TOKEN
fi
compose_handle traefik $TRAEFIK_ENABLED

if [ -n "$BACKUP_FOLDERS" ]; then
  require_env RESTIC_REPO_HOST
  require_env RESTIC_REPO_USERNAME
  require_env RESTIC_REPO_PASSWORD
  require_env RESTIC_PASSWORD
  export BACKUP_ENTRYPOINT_HASH=$(filehash backup/entrypoint.sh)
  export BACKUP_ON_FAIL_HOOK_HASH=$(filehash backup/hooks/on-backup-fail.sh)
fi
compose_handle backup "$([ -n "$BACKUP_FOLDERS" ] && echo true || echo false)"
