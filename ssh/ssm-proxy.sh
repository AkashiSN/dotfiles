#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Configuration
# Change these values to reflect your environment
MAX_ITERATION=20
SLEEP_DURATION=5

# Arguments passed from SSH client
HOST=$1
PORT=$2
USER=$3
export AWS_PROFILE=$4

# Set aws cli path
PATH=/usr/local/bin:$PATH

STATUS=`aws ssm describe-instance-information --filters Key=InstanceIds,Values=${HOST} --output text --query 'InstanceInformationList[0].PingStatus'`

# If the instance is online, start the session
if [ $STATUS == 'Online' ]; then
    aws ssm start-session --target ${HOST} --document-name AWS-StartSSHSession --parameters portNumber=${PORT}
else
    # Instance is offline - start the instance
    aws ec2 start-instances --instance-ids ${HOST}
    sleep ${SLEEP_DURATION}
    COUNT=0
    while [ ${COUNT} -le ${MAX_ITERATION} ]; do
        STATUS=`aws ssm describe-instance-information --filters Key=InstanceIds,Values=${HOST} --output text --query 'InstanceInformationList[0].PingStatus'`
        if [ ${STATUS} == 'Online' ]; then
            break
        fi
        # Max attempts reached, exit
        if [ ${COUNT} -eq ${MAX_ITERATION} ]; then
            exit 1
        else
            let COUNT=COUNT+1
            sleep ${SLEEP_DURATION}
        fi
    done
    # Instance is online now - start the session
    aws ssm start-session --target ${HOST} --document-name AWS-StartSSHSession --parameters portNumber=${PORT}
fi

# ssh-config

# Host HOSTNAME_ALIAS
#     HostName      i-asdfgxcvb98ubcxbv
#     User          ec2-user
#     ForwardAgent  yes
#     IdentityFile  ~/.ssh/id_ed25519
#
# Match host i-*
#   ProxyCommand ~/.ssh/ssm-proxy.sh %h %p %r {aws_profile}
