#!/bin/sh

[ -z "$DISCORD_WEBHOOK_URL" ] && exit 0

ERROR=$(printf '%s' "${ERROR_STDERR:-unknown}" | tr -d '\n\r' | sed 's/"/\\"/g')

PAYLOAD=$(printf \
  '{"embeds":[{"title":":x: Restic backup failed","color":15158332,"fields":[{"name":"Host","value":"`%s`","inline":true},{"name":"Profile","value":"`%s`","inline":true},{"name":"Exit Code","value":"`%s`","inline":true},{"name":"Error","value":"```%s```","inline":false}]}]}' \
  "$HOSTNAME" \
  "${PROFILE_NAME:-default}" \
  "${ERROR_EXIT_CODE:-unknown}" \
  "$ERROR")

wget -qO /dev/null \
  --header='Content-Type: application/json' \
  --post-data="$PAYLOAD" \
  "$DISCORD_WEBHOOK_URL"
