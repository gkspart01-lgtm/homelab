#!/bin/bash
# Type a command into the console of VM 105 (HAOS) on pve via the QEMU monitor and
# return a console screenshot.
# usage: ha-console.sh "core info"
set -e
HOST=root@192.168.181.10
CMD="$1"

KEYS=""
for (( i=0; i<${#CMD}; i++ )); do
  c="${CMD:$i:1}"
  case "$c" in
    " ") k="spc" ;;
    "=") k="equal" ;;
    "-") k="minus" ;;
    ".") k="dot" ;;
    "/") k="slash" ;;
    "_") k="shift-minus" ;;
    *)  k="$c" ;;
  esac
  KEYS="${KEYS}sendkey ${k}
"
done
KEYS="${KEYS}sendkey ret
"

ssh -o BatchMode=yes "$HOST" "printf '%s' '$KEYS' | qm monitor 105 >/dev/null 2>&1; sleep 6; printf 'screendump /tmp/ha-console.ppm\n' | qm monitor 105 >/dev/null 2>&1"
scp -q -o BatchMode=yes "$HOST":/tmp/ha-console.ppm /home/hermes/.hermes/cache/scratch/ha-console.ppm
python3 /home/hermes/.hermes/cache/scratch/ppm2png.py /home/hermes/.hermes/cache/scratch/ha-console.ppm /home/hermes/.hermes/cache/scratch/ha-console.png
echo "screenshot: /home/hermes/.hermes/cache/scratch/ha-console.png"
