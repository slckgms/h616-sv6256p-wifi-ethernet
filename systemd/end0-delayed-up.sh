#!/bin/bash
# The RMII PHY behind end0 is only ready about 9 seconds into a cold boot. Any
# "open" attempt before that gets -EINVAL out of phylink_validate, and the
# recovery path then pins the link at 10 Mbps half duplex until the next reboot.
#
# So: wait until uptime clears a safe margin, then make the genuine first
# attempt. 12s gets Ethernet up roughly eight times sooner than a flat sleep 60.
TARGET=12
while [ "$(awk '{print int($1)}' /proc/uptime)" -lt "$TARGET" ]; do sleep 1; done
logger "end0-delayed-up: bringing end0 up (uptime=$(awk '{print int($1)}' /proc/uptime)s)"
ip link set end0 up
sleep 3
SPEED=$(ethtool end0 2>/dev/null | awk -F': ' '/Speed:/{print $2}')
logger "end0-delayed-up: negotiated speed = ${SPEED:-unknown}"
networkctl reconfigure end0 2>/dev/null
exit 0
