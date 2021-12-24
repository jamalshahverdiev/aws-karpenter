#!/usr/bin/env bash

userdata_template_file='userdata-encode-template.txt'
karpenter_launchtemp_template_file='karpenter_launchtemp_template.yml'
key_name='delete-after-test-nonprod'
LAUNCH_TEMPLATE_NAME='KarpenterCustomLaunchTemplate'
KARPENTER_SG_NAME='Karpenter-EC2-SG'
aws_auth_configmap_file='aws-auth.yml'
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# Hardened AMI
ami_to_set='ami-0194c8e3f6dd95767'
cluster_yaml_file='cluster.yaml'
CLUSTER_NAME=$(cat ${cluster_yaml_file}| grep -A1 metadata | tail -n1 | awk '{ print $(NF)}')
cluster_vpc_object=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.resourcesVpcConfig')
CLUSTER_VPCID_GET=$(echo $cluster_vpc_object | jq -r '.vpcId')
provisioner_file='karpenter_provisioner.yml'
DEPLOYMENT_FILE='inflate_deployment.yaml'

apply_provisioner_and_deployment(){
    provisioner_output_file='karpenter_provisioner_output.yml' && rm ${provisioner_output_file}
    cp ${provisioner_file} ${provisioner_output_file} 
    sed -i "s/replace_cluster_name/${CLUSTER_NAME}/g;s/replace_launch_template/${LAUNCH_TEMPLATE_NAME}/g" ${provisioner_output_file}
    for object in ${provisioner_output_file} ${DEPLOYMENT_FILE}; do kubectl apply -f ${object}; done
}

prepare_userdata_file(){
    userdata_template_input=$1
    userdata_output='userdata_output.txt' && rm ${userdata_output}
    cp ${userdata_template_input} ${userdata_output} 
    CLUSTER_NAME=$(cat ${cluster_yaml_file}| grep -A1 metadata | tail -n1 | awk '{ print $(NF)}')
    API_SERVER_URL=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.[endpoint,certificateAuthority][0]' --output text)
    B64_CLUSTER_CA=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.[endpoint,certificateAuthority][1]' --output text)
    sed -i "s/replace_cluster_name/${CLUSTER_NAME}/g;s|replace_kubeapiurl|${API_SERVER_URL}|g;s/replace_cluster_ca/${B64_CLUSTER_CA}/g" ${userdata_output}
    # cat ${userdata_output} 
    b64_encoded_userdata=$(cat ${userdata_output}| base64 | tr -d "\n")
    # echo ${b64_encoded_userdata} | base64 -d > zibil.txt
}

prepare_security_group_rules(){
    CLUSTER_ADDITIONAL_SG=$(echo ${cluster_vpc_object}| jq -r '.securityGroupIds[]')
    CLUSTER_SG_GET=$(echo ${cluster_vpc_object} | jq -r '.clusterSecurityGroupId')
    CLUSTER_SG_RULE_RESULT=$(aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG_GET --protocol all --port all --source-group $CREATE_GET_SECURTY_GROUP_ID)
    CLUSTER_ADDITIONAL_SG_RULE_RESULT=$(aws ec2 authorize-security-group-ingress --group-id $CLUSTER_ADDITIONAL_SG --protocol tcp --port 443 --source-group $CREATE_GET_SECURTY_GROUP_ID)
    for secur_gr_igress in ${CLUSTER_ADDITIONAL_SG} ${CLUSTER_SG_GET}; do 
        aws ec2 authorize-security-group-ingress --group-id ${CREATE_GET_SECURTY_GROUP_ID} --protocol all --port all --source-group ${secur_gr_igress} &
    done
    aws ec2 authorize-security-group-ingress --group-id ${CREATE_GET_SECURTY_GROUP_ID} --protocol all --port all --cidr 10.0.0.0/8 &
    for secur_gr_egress in '443' '1025-65535'; do
        aws ec2 authorize-security-group-egress --group-id $CLUSTER_ADDITIONAL_SG --protocol tcp --port ${secur_gr_egress} --source-group $CREATE_GET_SECURTY_GROUP_ID &
    done
}

generate_karpenter_launchtemplate(){
    karpenter_launchtemp_input=$1
    karpenter_launchtemp_output='karpenter_launchtemp_template_output.yml' && rm ${karpenter_launchtemp_output}
    cp ${karpenter_launchtemp_input} ${karpenter_launchtemp_output} 
    prepare_userdata_file ${userdata_template_file}
    CREATE_GET_SECURTY_GROUP_ID=$(aws ec2 create-security-group --group-name ${KARPENTER_SG_NAME} --description "${KARPENTER_SG_NAME} for EC2 instances" --vpc-id ${CLUSTER_VPCID_GET} | jq -r '.GroupId')
    aws ec2 create-tags --resources ${CREATE_GET_SECURTY_GROUP_ID} --tags Key=Name,Value=${KARPENTER_SG_NAME}
    prepare_security_group_rules
    sed -i "s/UserData_Replace/${b64_encoded_userdata}/g;s/replace_key_name/${key_name}/g;s/company_ami_to_relpace/${ami_to_set}/g;s/replace_security_group/${CREATE_GET_SECURTY_GROUP_ID}/g;s/replace_launch_template/${LAUNCH_TEMPLATE_NAME}/g" ${karpenter_launchtemp_output}
    karpenter_ct_stack_result=$(aws cloudformation create-stack --stack-name KarpenterLaunchTemplateStack --template-body file://$(pwd)/${karpenter_launchtemp_output} --capabilities CAPABILITY_NAMED_IAM)
    echo ${karpenter_ct_stack_result}
}

# aws_auth_apply_configmap() {
#     aws_auth_configmap_output='aws-auth-output.yml' && rm ${aws_auth_configmap_output}
#     cp ${aws_auth_configmap_file} ${aws_auth_configmap_output} 
#     sed -i "s/REPLACE_AWS_ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" ${aws_auth_configmap_output}
#     kubectl apply -f 
# }

apply_provisioner_and_deployment
generate_karpenter_launchtemplate ${karpenter_launchtemp_template_file}