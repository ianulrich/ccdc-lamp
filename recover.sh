#!/bin/bash
cd /lamp
docker compose down
docker compose up -d
echo "FULL RECOVERY COMPLETE - $(date)"
