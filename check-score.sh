#!/bin/bash
IP=$(hostname -I | awk '{print $1}')
echo "=== SCORING CHECK ==="
curl -s http://$IP/score.php | grep -q "CCDC ECOM" && echo "HTTP: PASS" || echo "HTTP: FAIL"
echo "QUIT" | timeout 5 telnet $IP 25 | grep -q 220 && echo "SMTP: PASS" || echo "SMTP: FAIL"
echo "QUIT" | timeout 5 telnet $IP 110 | grep -q "+OK" && echo "POP3: PASS" || echo "POP3: FAIL"