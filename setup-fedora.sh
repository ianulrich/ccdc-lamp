#!/bin/bash
# setup-mail-ftp-only.sh - CCDC MINIMAL MAIL + FTP FORTRESS
# Only SMTP, POP3, and FTP in Docker → 100% scoring on those services
# Zero web, zero database, zero attack surface for HTTP

set -e

echo "=== CCDC MAIL + FTP ONLY FORTRESS ==="
echo "Installing Docker CE on Fedora Webmail..."
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
usermod -aG docker $(whoami)

echo "Creating /mailftp directory..."
mkdir -p /mailftp/{ftp/data,logs}
cd /mailftp

echo "Creating docker-compose.yml (SMTP + POP3 + FTP only)..."
cat > docker-compose.yml << 'EOF'
version: '3.9'
services:
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
EOF

echo "Creating FTP test files..."
mkdir -p ftp/data
echo "Welcome to CCDC FTP - team11" > ftp/data/welcome.txt
echo "quarterly-report.pdf" > ftp/data/report.txt

echo "Starting Mail + POP3 + FTP containers..."
docker compose up -d

# === MINIMAL INTEGRITY MONITOR (only these 3 services) ===
cat > /mailftp/monitor-mailftp.sh << 'MON'
#!/bin/bash
LOG="/mailftp/alerts.log"
SERVICES="ccdc-mail ccdc-pop3 ccdc-ftp"

echo "[$(date)] Mail/FTP check" >> $LOG

for svc in $SERVICES; do
  if ! docker ps --format "table {{.Names}}" | grep -q "^$svc$"; then
    echo "[ALERT] $svc DOWN - RECOVERING!" >> $LOG
    cd /mailftp && docker compose up -d
  fi
done

# Simple FTP file check
if ! ls /mailftp/ftp/data/welcome.txt >/dev/null 2>&1; then
  echo "[ALERT] FTP files missing - recovering" >> $LOG
  cd /mailftp && docker compose down && docker compose up -d
fi
MON

chmod +x /mailftp/monitor-mailftp.sh
(crontab -l 2>/dev/null; echo "*/2 * * * * /mailftp/monitor-mailftp.sh") | crontab -

echo "=== MAIL + FTP FORTRESS READY ==="
echo "SMTP: Port 25 (Postfix)"
echo "POP3: Port 110 (Dovecot)"
echo "FTP: teamuser / TeamFTP2025!"
echo "Recovery: cd /mailftp && docker compose down && docker compose up -d"
echo "Alerts: tail -f /mailftp/alerts.log"
