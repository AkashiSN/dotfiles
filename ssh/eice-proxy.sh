#!/bin/bash
# Configuration
# Change these values to reflect your environment
AWS_REGION='ap-northeast-1'
MAX_ITERATION=20
SLEEP_DURATION=5

# Arguments passed from SSH client
HOST=$1
PORT=$2
USER=$3
AWS_PROFILE=${4:-'default'}

# Set aws cli path
PATH=/usr/local/bin:$PATH

STATUS=`aws ssm describe-instance-information --filters Key=InstanceIds,Values=${HOST} --output text --query 'InstanceInformationList[0].PingStatus' --profile ${AWS_PROFILE} --region ${AWS_REGION}`

# If the instance is online, start the session
if [ $STATUS == 'Online' ]; then
    aws ec2-instance-connect open-tunnel --instance-id=$HOST --profile $AWS_PROFILE
else
    # Instance is offline - start the instance
    aws ec2 start-instances --instance-ids $HOST --profile ${AWS_PROFILE} --region ${AWS_REGION}
    sleep ${SLEEP_DURATION}
    COUNT=0
    while [ ${COUNT} -le ${MAX_ITERATION} ]; do
        STATUS=`aws ssm describe-instance-information --filters Key=InstanceIds,Values=${HOST} --output text --query 'InstanceInformationList[0].PingStatus' --profile ${AWS_PROFILE} --region ${AWS_REGION}`
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
    aws ec2-instance-connect open-tunnel --instance-id=$HOST --profile $AWS_PROFILE
fi

# ssh-config

# Host HOSTNAME_ALIAS
#     HostName i-asdfgxcvb98ubcxbv
#     User ec2-user
#     ForwardAgent yes
#
# Match host i-*
#   ProxyCommand ~/.ssh/eice-proxy.sh %h %p %r {aws_profile}
