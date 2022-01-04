#!/usr/bin/env bash

# cluster_yaml_script='generate_cluster_yaml.sh'
export region_name='us-east-2'
userdata_template_file='userdata-encode-template.txt'
karpenter_launchtemp_template_file='karpenter_launchtemp_template.yml'
karpenter_launchtemp_output='karpenter_launchtemp_template_output.yml'
aws_auth_configmap_output='aws-auth-output.yml'
aws_auth_configmap_file='aws-auth.yml'
provisioner_file='karpenter_provisioner.yml'
DEPLOYMENT_FILE='inflate_deployment.yaml'
# export key_name=$(cat ${cluster_yaml_script} | grep karpenter_key_name | head -n1 | cut -f2 -d'=' | tr -d "'")
export karpenter_key_name='karpenter_ec2_key'
export LAUNCH_TEMPLATE_NAME='KarpenterCustomLaunchTemplate'
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ami_to_set='ami-04635d3effed08298'
export CLUSTER_NAME='karpenter-scaler'
# export new_cluster_name='karpenter-demo'
KARPENTER_SG_NAME='Karpenter-EC2-SG'
# cluster_yaml_file=$(cat ${cluster_yaml_script} | grep cluster_template_output | head -n1 | awk '{ print $1 }' | cut -f2 -d'=' | tr -d "'")
# export CLUSTER_NAME=$(cat ${cluster_yaml_file}| grep -A1 metadata | tail -n1 | awk '{ print $(NF)}')
cluster_vpc_object=$(aws eks describe-cluster --region ${region_name} \
    --name ${CLUSTER_NAME} --query 'cluster.resourcesVpcConfig')
CLUSTER_VPCID_GET=$(echo $cluster_vpc_object | jq -r '.vpcId')
karpenter_provisioner_template_file='karpenter_provisioner_template.yml'
cluster_template_yaml='cluster.yaml'
cluster_template_output='cluster_output.yaml' # && rm ${cluster_template_output}
cf_stack_file='setup-infrastructure.yaml'
stack_name='setup-karpenter-infra'
all_keypair_names=$(aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName' --output text)
count=600