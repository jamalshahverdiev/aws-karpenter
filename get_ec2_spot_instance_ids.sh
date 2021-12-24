#!/usr/bin/env bash
CLUSTER_NAME=$(cat ${cluster_yaml_file}| grep -A1 metadata | tail -n1 | awk '{ print $(NF)}')
tag_value="karpenter.sh/${CLUSTER_NAME}"
all_spot_instances=$(aws ec2 describe-instances --filters "Name=instance-lifecycle,Values=spot")
echo ${all_spot_instances} | jq -r '.Reservations[].Instances[]|select(.Tags[].Value=="'${tag_value}'")|.InstanceId'
# echo ${all_spot_instances} | jq -r '.Reservations[].Instances[]|select(.Tags[].Value=="'${tag_value}'")|.PrivateIpAddress'

#aws eks update-kubeconfig --name vagrant-karpenter-demo