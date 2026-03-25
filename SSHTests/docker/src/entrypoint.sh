#!/bin/sh

set -eu

HELPER_PORT="${FIXTURE_HELPER_PORT:-18080}"
HELPER_BIND="${FIXTURE_HELPER_BIND:-127.0.0.1}"

python3 /portforward_helper.py \
  --bind "${HELPER_BIND}" \
  --port "${HELPER_PORT}" \
  --run-id "${FIXTURE_RUN_ID:-legacy}" \
  --lane "${FIXTURE_LANE:-default}" \
  --remote-root "${FIXTURE_REMOTE_ROOT:-~/fps}" >/tmp/fixture-helper.log 2>&1 &

dropbear -RB -p 23

exec /usr/sbin/sshd -D -e "$@"
