#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -euo pipefail
# This script is invoked in /etc/cron.d/ec2-automatic-shutdown
# which uses the full path to the file: /home/<username>/.ec2/stop-if-inactive.sh
# Parse the username from the file path, which can vary based on the OS.
USER=$(echo $0 | cut -d'/' -f3)
CONFIG=$(cat /home/$USER/.ec2/autoshutdown-configuration)
SHUTDOWN_TIMEOUT=${CONFIG#*=}
if ! [[ $SHUTDOWN_TIMEOUT =~ ^[0-9]*$ ]]; then
    echo "shutdown timeout is invalid"
    exit 1
fi

is_shutting_down() {
    is_shutting_down_ubuntu &> /dev/null || is_shutting_down_al1 &> /dev/null || is_shutting_down_al2 &> /dev/null || is_shutting_down_al2023 &> /dev/null
}

is_shutting_down_ubuntu() {
    local TIMEOUT
    TIMEOUT=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager ScheduledShutdown)
    if [ "$?" -ne "0" ]; then
        return 1
    fi
    local SHUTDOWN_TIMESTAMP
    SHUTDOWN_TIMESTAMP="$(echo $TIMEOUT | awk "{print \$3}")"
    if [ $SHUTDOWN_TIMESTAMP == "0" ] || [ $SHUTDOWN_TIMESTAMP == "18446744073709551615" ]; then
        return 1
    else
        return 0
    fi
}

is_shutting_down_al1() {
    pgrep shutdown
}

is_shutting_down_al2() {
    local FILE
    FILE=/run/systemd/shutdown/scheduled
    if [[ -f "$FILE" ]]; then
        return 0
    else
        return 1
    fi
}

is_shutting_down_al2023() {
    local TIMEOUT
    TIMEOUT=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager ScheduledShutdown)
    if [ "$?" -ne "0" ]; then
        return 1
    fi
    local SHUTDOWN_TIMESTAMP
    SHUTDOWN_TIMESTAMP="$(echo $TIMEOUT | awk "{print \$3}")"
    if [ $SHUTDOWN_TIMESTAMP == "0" ] || [ $SHUTDOWN_TIMESTAMP == "18446744073709551615" ]; then
        return 1
    else
        return 0
    fi
}

is_ssh_connected() {
  who | while read line; do
    src_ip=$(echo "$line" | grep -oE '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)')
    if [[ -n "$src_ip" && "$src_ip" != "(127.0.0.1)" ]]; then
      return 0
    fi
  done

  return 1
}

is_ssm_connected() {
    pgrep -U root -f /usr/bin/ssm-session-worker -a >/dev/null
}

if is_shutting_down; then
    if is_ssm_connected || is_ssh_connected; then
        sudo shutdown -c
        echo > "/home/$USER/.ec2/autoshutdown-timestamp"
    else
        TIMESTAMP=$(date +%s)
        echo "$TIMESTAMP" > "/home/$USER/.ec2/autoshutdown-timestamp"
    fi
else
    if ! is_ssm_connected && ! is_ssh_connected; then
        sudo shutdown -h $SHUTDOWN_TIMEOUT
    fi
fi
