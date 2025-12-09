#!/bin/bash
# monitor-integrity.sh - Auto-detect & recover from Red Team attacks
# Runs every 2 minutes via cron

ALERT_LOG="/lamp/integrity-alerts.log"
GOLDEN="/lamp/.golden-hash.txt"
SERVICES="ccdc-web ccdc-db ccdc-mail ccdc-pop3 ccdc-ftp"

echo "[$(date)] Integrity check running..." >> $ALERT_LOG

# === FILE & FOLDER INTEGRITY ===
find /lamp/html /lamp/ftp/data -type f -exec sha256sum {} \; | sort > /tmp/current.txt
if [ -f "$GOLDEN" ]; then
  if ! diff /tmp/current.txt $GOLDEN > /dev/null; then
    echo "[ALERT] FILE TAMPERING DETECTED! Auto-recovering..." >> $ALERT_LOG
    cd /lamp && docker compose down && docker compose up -d
    cp /tmp/current.txt $GOLDEN  # Update golden after recovery
  fi
else
  cp /tmp/current.txt $GOLDEN
  echo "[INIT] Golden hash created." >> $ALERT_LOG
fi

# === ROGUE CRON JOBS ===
if crontab -l 2>/dev/null | grep -E "(wget|curl|rm -rf|killall|docker stop|nc |ncat|bash -i)"; then
  echo "[ALERT] MALICIOUS CRON DETECTED - REMOVING!" >> $ALERT_LOG
  crontab -l | grep -v "(wget|curl|rm -rf|killall|docker stop|nc |ncat|bash -i)" | crontab -
fi

# === SERVICE STATUS ===
for svc in $SERVICES; do
  if ! docker ps --format "table {{.Names}}" | grep -q "^$svc$"; then
    echo "[ALERT] SERVICE $svc DOWN - RESTARTING!" >> $ALERT_LOG
    cd /lamp && docker compose up -d
  fi
done

echo "[$(date)] Integrity check complete." >> $ALERT_LOG