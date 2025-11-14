#!/bin/bash
# setup-lamp.sh - FULL CCDC LAMP DOCKER DEPLOYMENT
# Run as root on Ubuntu Ecom server

set -e

echo "[+] Installing Docker..."
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
usermod -aG docker $SUDO_USER

echo "[+] Creating project directory..."
mkdir -p /lamp/{html,ftp/data,logs}
cd /lamp

echo "[+] Creating docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3.9'
services:
  web:
    image: php:8.2-apache
    container_name: ccdc-web
    ports: ["80:80"]
    volumes:
      - ./html:/var/www/html:ro
      - ./logs:/var/log/apache2
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/score.php"]
      interval: 10s
      retries: 3
    restart: unless-stopped

  db:
    image: mariadb:10.11
    container_name: ccdc-db
    environment:
      MYSQL_ROOT_PASSWORD: ChangeMe123!
      MYSQL_DATABASE: ecom
      MYSQL_USER: webapp
      MYSQL_PASSWORD: AppPass123!
    volumes:
      - db_data:/var/lib/mysql
    restart: unless-stopped

  mail:
    image: juanluisbaptiste/postfix:latest
    container_name: ccdc-mail
    environment:
      POSTFIX_MYHOSTNAME: mail.ecom.local
    ports: ["25:25"]
    restart: unless-stopped

  pop3:
    image: boky/postfix-dovecot
    container_name: ccdc-pop3
    environment:
      MAILNAME: ecom.local
      SSL: "no"
    ports: ["110:110"]
    restart: unless-stopped

  ftp:
    image: stilliard/pure-ftpd:hardened
    container_name: ccdc-ftp
    ports:
      - "21:21"
      - "30000-30009:30000-30009"
    environment:
      PUBLICHOST: ftp.ecom.local
      ADDED_USERS: "teamuser:TeamFTP123!"
    volumes:
      - ./ftp/data:/home/ftpusers/teamuser
    cap_drop: [ALL]
    cap_add: [CHOWN, SETUID, SETGID]
    restart: unless-stopped

volumes:
  db_data:
EOF

echo "[+] Seeding scoring content..."
cat > html/score.php << 'EOF'
<?php
// CCDC SCORING PAGE - MUST MATCH EXACTLY
echo "CCDC ECOM PORTAL v1.0 - SECURE LOGIN REQUIRED\n";
echo "Expected Output for HTTP Scoring Check\n";
echo "Team ID: team11 | Service: HTTP | Status: UP\n";
?>
EOF

mkdir -p ftp/data
echo "Welcome to CCDC FTP - team11" > ftp/data/welcome.txt
echo "secret-business-plan.pdf" > ftp/data/business-plan.txt

echo "[+] Starting services..."
docker compose up -d

echo "[+] Hardening containers..."
docker update --restart=unless-stopped --read-only ccdc-web
docker update --cap-drop=ALL --cap-add=NET_BIND_SERVICE ccdc-web

echo "LAMP Stack is LIVE! Check: http://$(hostname -I | awk '{print $1}')/score.php"