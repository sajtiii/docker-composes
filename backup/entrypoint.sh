#!/bin/sh
set -e

# --- Convert comma-separated BACKUP_FOLDERS to TOML array ---
TOML_SOURCES=""
OLD_IFS="$IFS"
IFS=','
for folder in $BACKUP_FOLDERS; do
  folder=$(echo "$folder" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$TOML_SOURCES" ] && TOML_SOURCES="${TOML_SOURCES}, "
  TOML_SOURCES="${TOML_SOURCES}\"/host${folder}\""
done
IFS="$OLD_IFS"

# --- Convert comma-separated BACKUP_EXCLUDE to TOML array ---
TOML_EXCLUDES=""
if [ -n "$BACKUP_EXCLUDE" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for pattern in $BACKUP_EXCLUDE; do
    pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$TOML_EXCLUDES" ] && TOML_EXCLUDES="${TOML_EXCLUDES}, "
    TOML_EXCLUDES="${TOML_EXCLUDES}\"${pattern}\""
  done
  IFS="$OLD_IFS"
fi

# --- Build retention block (only include set vars) ---
RETENTION_TOML=""
[ -n "$KEEP_LAST" ]    && RETENTION_TOML="${RETENTION_TOML}  keep-last = ${KEEP_LAST}\n"
[ -n "$KEEP_HOURLY" ]  && RETENTION_TOML="${RETENTION_TOML}  keep-hourly = ${KEEP_HOURLY}\n"
[ -n "$KEEP_DAILY" ]   && RETENTION_TOML="${RETENTION_TOML}  keep-daily = ${KEEP_DAILY}\n"
[ -n "$KEEP_WEEKLY" ]  && RETENTION_TOML="${RETENTION_TOML}  keep-weekly = ${KEEP_WEEKLY}\n"
[ -n "$KEEP_MONTHLY" ] && RETENTION_TOML="${RETENTION_TOML}  keep-monthly = ${KEEP_MONTHLY}\n"
[ -n "$KEEP_YEARLY" ]  && RETENTION_TOML="${RETENTION_TOML}  keep-yearly = ${KEEP_YEARLY}\n"

# --- Resolve schedule ---
SCHEDULE="${BACKUP_SCHEDULE:-@daily-random}"
if [ "$SCHEDULE" = "@daily-random" ]; then
  read -r RAND_HOUR RAND_MIN << EOF
$(awk 'BEGIN{srand(); print int(rand()*24), int(rand()*60)}')
EOF
  SCHEDULE="*-*-* $(printf '%02d' "$RAND_HOUR"):$(printf '%02d' "$RAND_MIN"):00"
fi

# --- Build optional blocks ---
PROMETHEUS_TOML=""
[ -n "$PUSHGATEWAY_URL" ] && PROMETHEUS_TOML="
  prometheus-push = \"${PUSHGATEWAY_URL}\"
  prometheus-push-job = \"restic\"
  extended-status = true"


# --- Generate resticprofile config ---
mkdir -p /resticprofile /var/spool/cron/crontabs
touch /var/spool/cron/crontabs/root
cat > /resticprofile/profiles.toml << TOML
version = "1"

[global]
  scheduler = "crond"

[default]
  repository = "rest:https://${RESTIC_REPO_USERNAME}:${RESTIC_REPO_PASSWORD}@${RESTIC_REPO_HOST}/${HOSTNAME}"
  password = "${RESTIC_PASSWORD}"
  initialize = true
  cache-dir = "/tmp/restic-cache"
${PROMETHEUS_TOML}

[default.backup]
  source = [${TOML_SOURCES}]
$([ -n "$TOML_EXCLUDES" ] && printf '  exclude = [%s]\n' "$TOML_EXCLUDES")
  schedule = "${SCHEDULE}"
  schedule-permission = "system"
  run-after-fail = ["/hooks/on-backup-fail.sh"]

[default.retention]
$(printf "$RETENTION_TOML")
  prune = true

TOML

echo "[entrypoint] profiles.toml generated. Schedule: ${SCHEDULE}"

# --- Register schedules with crond ---
resticprofile schedule --all
sed -i '/resticprofile/s|$| >> /proc/1/fd/1 2>\&1|' /var/spool/cron/crontabs/root

echo "[entrypoint] Schedules registered. Starting cron daemon..."
exec crond -f -l 8 -L /proc/1/fd/1
