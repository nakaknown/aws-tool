#!/bin/bash
set -eu

ASG_NAME=$1
INSTANCE_ID=$2
TG_ARN=$(aws elbv2 describe-target-groups --names ${ASG_NAME} --query 'TargetGroups[].[TargetGroupArn]' --output text)

# Get now desire count for asg
BEFORE_DESIRE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
--auto-scaling-group-names ${ASG_NAME} \
--query 'AutoScalingGroups[].DesiredCapacity' --output text)
# Calculate desire count for asg
AFTER_DESIRE_COUNT=$(echo $((BEFORE_DESIRE_COUNT+1)))
echo "Change the number of desire instances in the group from ${BEFORE_DESIRE_COUNT} to ${AFTER_DESIRE_COUNT}."

# Change desire count
aws autoscaling set-desired-capacity \
--auto-scaling-group-name ${ASG_NAME} \
--desired-capacity ${AFTER_DESIRE_COUNT}

echo "Started: All instances have passed the health check."
while true
do
    sleep 30
    # Check healthy count
    HEALTHY_HOST_COUNT=`aws elbv2 describe-target-health \
    --target-group-arn ${TG_ARN} \
    --query 'TargetHealthDescriptions[].TargetHealth[].[State]' --output text | wc -l`
    # Check numbers match
    if [ ${HEALTHY_HOST_COUNT} -eq ${AFTER_DESIRE_COUNT} ] ; then
        echo "Finished: All instances have passed the health check."
        break
    else
        echo "In progress: Please wait for a while."
    fi
done

aws elbv2 deregister-targets \
--target-group-arn ${TG_ARN} \
--targets Id=${INSTANCE_ID}

echo "Started: Draining instances from the target group."
while true
do
    sleep 30
    # Check target instance id
    TARGETS_ID=$(aws elbv2 describe-target-health \
    --target-group-arn ${TG_ARN} \
    --query 'TargetHealthDescriptions[].Target[].Id' | egrep "i-")
    # Check desired numbers match
    if echo "${TARGETS_ID}" | egrep "${INSTANCE_ID}" >/dev/null ; then
        echo "In progress: Please wait for a while."
    else
        echo "Finished: Draining instances from the target group."
        break
    fi
done

# Terminate instances
aws ec2 terminate-instances \
--instance-ids ${INSTANCE_ID}

echo "Started. Draining instances from the target group."
while true
do
    sleep 30
    # Check terminating instance status
    INSTANCE_STATUS=$(aws ec2 describe-instances \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[].Instances[].State[].[Name]' --output text)
    # Check status match
    if [ "${INSTANCE_STATUS}" = "terminated" ] ; then
        echo "Finished!!! Draining instances from the target group."
        break
    else
        echo "In progress: Please wait for a while."
    fi
done
