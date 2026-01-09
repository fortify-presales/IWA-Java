#!/usr/bin/env bash
set -euo pipefail

# docker-entrypoint.sh
# Waits for mail server only when configured (SPRING_MAIL_HOST and SPRING_MAIL_PORT)
# and when SPRING_MAIL_TEST_CONNECTION is not false/0. Defaults to a 15s timeout.

lc() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

TEST_CONN="${SPRING_MAIL_TEST_CONNECTION:-true}"
MAIL_HOST="${SPRING_MAIL_HOST:-}"
MAIL_PORT="${SPRING_MAIL_PORT:-}"
TIMEOUT_SECONDS="${SPRING_MAIL_CONNECT_TIMEOUT:-15}"

if [ -n "$MAIL_HOST" ] && [ -n "$MAIL_PORT" ] && [ "$(lc "$TEST_CONN")" != "false" ] && [ "$TEST_CONN" != "0" ]; then
  echo "Mail server configured: $MAIL_HOST:$MAIL_PORT (will wait up to ${TIMEOUT_SECONDS}s)..."
  start_ts=$(date +%s)
  while ! bash -c ">/dev/tcp/${MAIL_HOST}/${MAIL_PORT}" 2>/dev/null; do
    now_ts=$(date +%s)
    elapsed=$((now_ts - start_ts))
    if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
      echo "Timed out waiting for mail server ${MAIL_HOST}:${MAIL_PORT} after ${TIMEOUT_SECONDS}s" >&2
      break
    fi
    sleep 1
  done

  if bash -c ">/dev/tcp/${MAIL_HOST}/${MAIL_PORT}" 2>/dev/null; then
    echo "Mail server ${MAIL_HOST}:${MAIL_PORT} is reachable."
  else
    echo "Proceeding without mail server available (startup will continue)."
  fi
else
  echo "Mail server not configured or test disabled (SPRING_MAIL_TEST_CONNECTION=${TEST_CONN}); skipping wait."
fi

# If no args provided, run the default java command with expanded JAVA_OPTS
if [ "$#" -eq 0 ]; then
  exec sh -c "exec java $JAVA_OPTS -jar /app/app.jar"
else
  exec "$@"
fi

