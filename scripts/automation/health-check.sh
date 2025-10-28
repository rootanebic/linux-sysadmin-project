#!/bin/bash
# health-check.sh
# Description: Collect system health info and append to /var/log/health-check.log

DATE=$(date '+%Y-%m-%d %H:%M:%S')
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
MEM=$(free -m | awk 'NR==2{printf "%s/%sMB", $3,$2 }')
DISK=$(df -h / | awk 'NR==2{print $3"/"$2}')
USERS=$(who | wc -l)
FAILED_LOGINS=$(grep 'Failed password' /var/log/auth.log | wc -l)

echo "$DATE CPU: $CPU% MEM: $MEM DISK: $DISK USERS: $USERS FAILED_LOGINS: $FAILED_LOGINS" >> /var/log/health-check.log
