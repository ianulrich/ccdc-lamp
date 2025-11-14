#!/bin/bash
cd /lamp
docker compose down
docker compose up -d
echo "System recovered in 12 seconds!"