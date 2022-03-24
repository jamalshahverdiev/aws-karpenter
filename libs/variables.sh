#!/usr/bin/env bash

yaml_files_path='yamls'
export region_name='us-east-2'
userdata_template_file="${yaml_files_path}/userdata-encode-template.txt"
userdata_output="${yaml_files_path}/userdata_output.txt"
karpenter_launchtemp_template_file="${yaml_files_path}/karpenter_launchtemp_template.yml"
karpenter_launchtemp_output="${yaml_files_path}/karpenter_launchtemp_template_output.yml"
aws_auth_configmap_output="${yaml_files_path}/aws-auth-output.yml"
aws_auth_configmap_file="${yaml_files_path}/aws-auth.yml"
provisioner_file="${yaml_files_path}/karpenter_provisioner.yml"
DEPLOYMENT_FILE="${yaml_files_path}/inflate_deployment.yaml"
export karpenter_key_name='karpenter_ec2_key'
export LAUNCH_TEMPLATE_NAME='KarpenterCustomLaunchTemplate'
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ami_to_set='ami-04635d3effed08298'
export CLUSTER_NAME='karpenter-scaler'
KARPENTER_SG_NAME='Karpenter-EC2-SG'
karpenter_provisioner_template_file="${yaml_files_path}/karpenter_provisioner_template.yml"
cluster_template_yaml="${yaml_files_path}/cluster.yaml"
cluster_template_output="${yaml_files_path}/cluster_output.yaml" 
vpc_cf_stack_file="${yaml_files_path}/setup-infrastructure.yaml"
stack_name='setup-karpenter-infra'
all_keypair_names=$(aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName' --output text)
count=600