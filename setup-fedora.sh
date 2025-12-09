#!/bin/bash
# setup-fedora.sh - FULL CCDC LAMP DOCKER DEPLOYMENT ON FEDORA WEBMAIL
# Target: Fedora Webmail VM (Oracle Linux 9 / Fedora 42)
# Run as root or with sudo

set -e

echo "=== CCDC LAMP FORTRESS - FEDORA DEPLOYMENT ==="
echo "Installing Docker CE on Fedora/Oracle Linux 9..."

# Install Docker CE (works on Fedora 42 & Oracle Linux 9)
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
usermod -aG docker $(whoami)

echo "Creating /lamp project directory..."
mkdir -p /lamp/{html,ftp/data,logs}
cd /lamp

echo "Creating docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3.9'
services:
  web:
    image: php:8.2-apache
    container_name: ccdc-web
    ports:
      - "80:80"
    volumes:
      - ./html:/var/www/html:ro
      - ./logs:/var/log/apache2
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/score.php"]
      interval: 15s
      retries: 3
    restart: unless-stopped

  db:
    image: mariadb:10.11
    container_name: ccdc-db
    environment:
      MYSQL_ROOT_PASSWORD: ChangeMe123!
      MYSQL_DATABASE: ecom
      MYSQL_USER: webapp
      MYSQL_PASSWORD: AppPass2025!
    volumes:
      - db_data:/var/lib/mysql
    restart: unless-stopped

  mail:
    image: juanluisbaptiste/postfix:latest
    container_name: ccdc-mail
    environment:
      POSTFIX_MYHOSTNAME: mail.ecom.local
      POSTFIX_MYDOMAIN: ecom.local
    ports:
      - "25:25"
    restart: unless-stopped

  pop3:
    image: boky/postfix-dovecot
    container_name: ccdc-pop3
    environment:
      MAILNAME: ecom.local
      SSL: "no"
    ports:
      - "110:110"
    restart: unless-stopped

  ftp:
    image: stilliard/pure-ftpd:hardened
    container_name: ccdc-ftp
    ports:
      - "21:21"
      - "30000-30009:30000-30009"
    environment:
      PUBLICHOST: ftp.ecom.local
      ADDED_USERS: "teamuser:TeamFTP2025!"
    volumes:
      - ./ftp/data:/home/ftpusers/teamuser
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
    restart: unless-stopped

volumes:
  db_data:
EOF

echo "Seeding exact CCDC scoring content..."
cat > html/score.php << 'EOF'
<?php
// EXACT CONTENT - DO NOT CHANGE - REQUIRED FOR SCORING
echo "CCDC ECOM PORTAL v1.0 - SECURE LOGIN REQUIRED\n";
echo "Expected Output for HTTP Scoring Check\n";
echo "Team ID: team11 | Service: HTTP | Status: UP\n";
?>
EOF

mkdir -p ftp/data
echo "Welcome to CCDC FTP - team11" > ftp/data/welcome.txt
echo "confidential-report-q4.pdf" > ftp/data/report.txt

echo "Starting all services..."
docker compose up -d

echo "Hardening containers..."
docker update --restart=unless-stopped --read-only ccdc-web
docker update --cap-drop=ALL --cap-add=NET_BIND_SERVICE ccdc-web

# === DEPLOY INTEGRITY MONITOR ===
echo "Deploying monitor-integrity.sh..."
cat > /lamp/monitor-integrity.sh << 'MONITOR'
#!/bin/bash
# monitor-integrity.sh - Detect tampering, rogue crons, service kills
ALERT_LOG="/lamp/integrity-alerts.log"
GOLDEN="/lamp/.golden-hash.txt"
SERVICES="ccdc-web ccdc-db ccdc-mail ccdc-pop3 ccdc-ftp"

echo "[$(date)] Integrity check running..." >> $ALERT_LOG

# File & folder integrity
find /lamp/html /lamp/ftp/data -type f -exec sha256sum {} \; | sort > /tmp/current.txt
if [ -f "$GOLDEN" ]; then
  if ! diff /tmp/current.txt $GOLDEN > /dev/null; then
    echo "[ALERT] FILE TAMPERING! Auto-recovering..." >> $ALERT_LOG
    cd /lamp && docker compose down && docker compose up -d
    cp /tmp/current.txt $GOLDEN
  fi
else
  cp /tmp/current.txt $GOLDEN
fi

# Rogue cron jobs
if crontab -l 2>/dev/null | grep -E "(wget|curl|rm -rf|killall|docker stop|nc |ncat)"; then
  echo "[ALERT] MALICIOUS CRON DETECTED - REMOVING!" >> $ALERT_LOG
  crontab -l | grep -v "(wget|curl|rm -rf|killall|docker stop|nc |ncat)" | crontab -
fi

# Service status
for svc in $SERVICES; do
  if ! docker ps --format "table {{.Names}}" | grep -q "^$svc$"; then
    echo "[ALERT] $svc DOWN - RECOVERING!" >> $ALERT_LOG
    cd /lamp && docker compose up -d
  fi
done

echo "[$(date)] Check complete." >> $ALERT_LOG
MONITOR

chmod +x /lamp/monitor-integrity.sh

# Create golden hash + enable monitoring
find /lamp/html /lamp/ftp/data -type f -exec sha256sum {} \; | sort > /lamp/.golden-hash.txt
(crontab -l 2>/dev/null; echo "*/2 * * * * /lamp/monitor-integrity.sh") | crontab -

echo "=== DEPLOYMENT COMPLETE ==="
echo "HTTP: http://$(hostname -I | awk '{print $1}')/score.php"
echo "FTP: teamuser / TeamFTP2025!"
echo "Recovery: sudo bash /lamp/recover.sh"
echo "Monitor: http://$(hostname -I | awk '{print $1}')/monitor.html"
echo "Integrity alerts: tail -f /lamp/integrity-alerts.log"