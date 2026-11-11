#!/bin/sh
set -eu
mkdir -p /backups
while true; do
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  target="/backups/granmap-${stamp}.dump"
  if pg_dump --format=custom --file="${target}.partial" && pg_restore --list "${target}.partial" >/dev/null; then
    mv "${target}.partial" "$target"
    printf 'GranMap: backup validado %s\n' "$stamp"
  else
    printf 'GranMap: falha no backup; arquivos anteriores preservados.\n' >&2
  fi
  # Keep all backups for now. Retention/deletion is a separate operator choice.
  sleep 86400
done
