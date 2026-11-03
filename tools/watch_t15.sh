#!/bin/sh
# Poll the T15 over the t15link bridge every 30 s until it disconnects (reboot).
H=/home/manojb/Documents/macos/tools
OUT=$H/t15-progress.log
MISS=0
SEEN=0
while true; do
  R=$(python3 -I $H/t15link.py run 'date +%H:%M:%S; df -m "/Volumes/Macintosh HD" | awk "NR==2{print \"usedMB=\"\$3}"; D="/Volumes/Macintosh HD/Applications/Install macOS Ventura.app/Contents/SharedSupport/SharedSupport.dmg"; [ -f "$D" ] && echo "ssdmgMB=$(( $(stat -f %z "$D") / 1048576 ))"; ls -d "/Volumes/Macintosh HD/macOS Install Data" 2>/dev/null; ps axo etime,%cpu,command | grep -iE "installer -pkg|startosinstall|osinstallersetupd|cp /Volumes" | grep -v grep | cut -c1-120; tail -c 300 /Volumes/INSTALL/logs/startosinstall.txt 2>/dev/null | tr "\r" "\n" | tail -2' 40 2>&1)
  echo "$R" | tr '\n' ' ' | sed 's/$/\n/' >> "$OUT"
  case "$R" in
    *"NOT CONNECTED"*|*"connection closed"*|*"timed out"*|*"Connection refused"*) MISS=$((MISS + 1)) ;;
    *) MISS=0; SEEN=1 ;;
  esac
  [ $SEEN = 1 ] && [ $MISS -ge 4 ] && { echo "T15 disconnected (likely rebooting)"; tail -5 "$OUT"; exit 0; }
  sleep 30
done
