#!/usr/bin/env bash
# Eine komplette Runde: provision -> bootstrap -> deploy -> verify [-keep]
source "$(dirname "$0")/lib.sh"
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1
START=$(date +%s%3N)

log "RUNDE START $(date +%F' '%T)"
"$(dirname "$0")/provision-target.sh"
"$(dirname "$0")/bootstrap-target.sh"
"$(dirname "$0")/deploy-target.sh"

set +e
"$(dirname "$0")/verify-target.sh"; RC=$?
set -e
DUR=$(( ($(date +%s%3N) - START) / 1000 ))
log "RUNDE ENDE in ${DUR}s, verify-Exitcode ${RC}"

if [ "$KEEP" = "0" ] && [ "$RC" = "0" ]; then
  "$(dirname "$0")/destroy-target.sh"
  log "Ziel geloescht - naechste Runde startet wieder bei null"
else
  log "Ziel bleibt stehen (--keep oder verify fehlgeschlagen)"
fi
exit "$RC"
