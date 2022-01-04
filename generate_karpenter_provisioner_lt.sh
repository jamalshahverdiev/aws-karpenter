#!/usr/bin/env bash

. ./variables.sh
cluster_vpc_object=$(aws eks describe-cluster --region ${region_name} --name ${CLUSTER_NAME} --query 'cluster.resourcesVpcConfig')
CLUSTER_VPCID_GET=$(echo $cluster_vpc_object | jq -r '.vpcId')

apply_provisioner_and_deployment(){
    for object in ${provisioner_file} ${DEPLOYMENT_FILE}; do kubectl apply -f ${object}; done
}

prepare_userdata_file(){
    export API_SERVER_URL=$(aws eks describe-cluster --region ${region_name} \
        --name ${CLUSTER_NAME} --query 'cluster.[endpoint,certificateAuthority][0]' --output text)
    export B64_CLUSTER_CA=$(aws eks describe-cluster --region ${region_name} \
        --name ${CLUSTER_NAME} --query 'cluster.[endpoint,certificateAuthority][1]' --output text)
    cat ${userdata_template_file} | envsubst > ${userdata_output}
    export b64_encoded_userdata=$(cat ${userdata_output}| base64 | tr -d "\n")
    # echo ${b64_encoded_userdata} | base64 -d > somefile.txt
}

prepare_security_group_rules(){
    CLUSTER_ADDITIONAL_SG=$(echo ${cluster_vpc_object}| jq -r '.securityGroupIds[]')
    CLUSTER_SG_GET=$(echo ${cluster_vpc_object} | jq -r '.clusterSecurityGroupId')
    CLUSTER_SG_RULE_RESULT=$(aws ec2 authorize-security-group-ingress --region ${region_name} \
        --group-id $CLUSTER_SG_GET \
        --protocol all --port all --source-group $CREATE_GET_SECURTY_GROUP_ID)
    CLUSTER_ADDITIONAL_SG_RULE_RESULT=$(aws ec2 authorize-security-group-ingress --region ${region_name} \
        --group-id $CLUSTER_ADDITIONAL_SG --protocol tcp --port 443 --source-group $CREATE_GET_SECURTY_GROUP_ID)
    for secur_gr_igress in ${CLUSTER_ADDITIONAL_SG} ${CLUSTER_SG_GET}; do 
        aws ec2 authorize-security-group-ingress --region ${region_name} \
            --group-id ${CREATE_GET_SECURTY_GROUP_ID} \
            --protocol all --port all --source-group ${secur_gr_igress} &
    done
    aws ec2 authorize-security-group-ingress --region ${region_name} \
            --group-id ${CREATE_GET_SECURTY_GROUP_ID} \
            --protocol all --port all --cidr 10.0.0.0/8 &
    for secur_gr_egress in '443' '1025-65535'; do
        aws ec2 authorize-security-group-egress --region ${region_name} \
            --group-id $CLUSTER_ADDITIONAL_SG \
            --protocol tcp --port ${secur_gr_egress} \
            --source-group $CREATE_GET_SECURTY_GROUP_ID &
    done
}

generate_karpenter_launchtemplate(){
    karpenter_launchtemp_input=$1
    prepare_userdata_file ${userdata_template_file}
    export CREATE_GET_SECURTY_GROUP_ID=$(aws ec2 create-security-group --group-name ${KARPENTER_SG_NAME} \
        --description "${KARPENTER_SG_NAME} for EC2 instances" \
        --vpc-id ${CLUSTER_VPCID_GET} | jq -r '.GroupId')
    aws ec2 create-tags --resources ${CREATE_GET_SECURTY_GROUP_ID} --tags Key=Name,Value=${KARPENTER_SG_NAME}
    prepare_security_group_rules
    cat ${karpenter_launchtemp_input} | envsubst > ${karpenter_launchtemp_output}
    karpenter_ct_stack_result=$(aws cloudformation create-stack --stack-name KarpenterLaunchTemplateStack \
        --template-body file://$(pwd)/${karpenter_launchtemp_output} \
        --capabilities CAPABILITY_NAMED_IAM)
    echo ${karpenter_ct_stack_result}
}

aws_auth_apply_configmap() {
    export get_nodeinstance_role_name=$(aws iam list-roles | grep -i eksctl | grep -iv service | tail -n1 | cut -f2 -d'/' | tr -d '",')
    cat ${aws_auth_configmap_file} | envsubst > ${aws_auth_configmap_output}
    kubectl apply -f ${aws_auth_configmap_output}
}

apply_provisioner_and_deployment
generate_karpenter_launchtemplate ${karpenter_launchtemp_template_file}
aws_auth_apply_configmap
