#!/bin/sh
# HA-Watchdog: prueft HA Core und startet die VM bei anhaltendem Ausfall neu.
set -u

: "${HA_URL:?HA_URL fehlt}"
: "${PVE_API:?PVE_API fehlt}"
: "${PVE_NODE:?PVE_NODE fehlt}"
: "${PVE_TOKEN_ID:?PVE_TOKEN_ID fehlt}"
: "${PVE_TOKEN_SECRET:?PVE_TOKEN_SECRET fehlt}"
: "${VMID:?VMID fehlt}"

FAILS_BEFORE_REBOOT=${FAILS_BEFORE_REBOOT:-3}
COOLDOWN_SECONDS=${COOLDOWN_SECONDS:-3600}
CHECK_INTERVAL=${CHECK_INTERVAL:-60}
GRACE_SECONDS=${GRACE_SECONDS:-300}

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"; }

ha_ok() {
  wget -q -T 10 -O /dev/null "$HA_URL" 2>/dev/null
}

reboot_vm() {
  now=$(date +%s)
  if [ $((now - LAST_REBOOT)) -lt "$COOLDOWN_SECONDS" ]; then
    log "Ausfall anhaltend, aber Abkuehlzeit laeuft ($((COOLDOWN_SECONDS - (now - LAST_REBOOT)))s) - kein Reboot"
    return 0
  fi
  log "HA antwortet nicht -> Reboot VM $VMID auf $PVE_NODE"
  if wget -q --no-check-certificate -T 15 -O /dev/null \
      --header="Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}" \
      --post-data="" \
      "${PVE_API}/nodes/${PVE_NODE}/qemu/${VMID}/status/reboot" 2>/dev/null; then
    log "Reboot ausgeloest"
    LAST_REBOOT=$now
    FAILS=0
    sleep 120
  else
    log "FEHLER: Reboot-Aufruf an die PVE-API fehlgeschlagen"
  fi
}

START=$(date +%s)
LAST_REBOOT=0
FAILS=0
log "Watchdog startet: $HA_URL, VM $VMID auf $PVE_NODE, $FAILS_BEFORE_REBOOT Fehlversuche bis Reboot"

while :; do
  if ha_ok; then
    [ "$FAILS" -gt 0 ] && log "HA wieder erreichbar (nach $FAILS Fehlversuchen)"
    FAILS=0
  else
    FAILS=$((FAILS + 1))
    log "HA nicht erreichbar (Versuch $FAILS/$FAILS_BEFORE_REBOOT)"
    if [ "$FAILS" -ge "$FAILS_BEFORE_REBOOT" ]; then
      if [ $(( $(date +%s) - START )) -lt "$GRACE_SECONDS" ]; then
        log "Startphase - warte noch mit Reboot"
      else
        reboot_vm
      fi
    fi
  fi
  sleep "$CHECK_INTERVAL"
done
