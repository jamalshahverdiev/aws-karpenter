#!/usr/bin/env bash

cluster_template_yaml='cluster.yaml'
cluster_template_output='cluster_output.yaml' && rm ${cluster_template_output}
karpenter_key_name='karpenter_ec2_key'
cf_stack_file='setup-infrastructure.yaml'
new_cluster_name='karpenter-demo' 
stack_name='setup-karpenter-infra'
region_name='us-east-2'
all_keypair_names=$(aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName' --output text)
count=600

if [[ "$all_keypair_names" == *"$karpenter_key_name"* ]]; then
    echo "Key with name: ${karpenter_key_name} already exists."
else
    rm -rf ~/.ssh/${karpenter_key_name}.pem && \
    aws ec2 create-key-pair --key-name "${karpenter_key_name}" | jq -r ".KeyMaterial" > ~/.ssh/${karpenter_key_name}.pem
fi

if [[ $(aws cloudformation describe-stacks --stack-name ${stack_name} --query 'Stacks[].StackName' --output text) != ${stack_name} ]]; then
    aws cloudformation create-stack --stack-name ${stack_name} \
        --capabilities CAPABILITY_IAM \
        --template-body file://./${cf_stack_file} \
        --region ${region_name} &
fi


while [[ $count > 0 ]] ; do
    echo "$count"
    count=$(( $count - 1 ))
    if [[ $(aws cloudformation describe-stacks --stack-name ${stack_name} --query 'Stacks[].StackStatus' --region ${region_name} --output text) == 'CREATE_COMPLETE' ]]; then
        echo "Cloudformation stack for network settings deployed successful!"
        break
    fi
    sleep 5
done

get_cft_outputs=$(aws cloudformation describe-stacks --stack-name $stack_name --query 'Stacks[].Outputs[]')
az_one_subnet=$(echo $get_cft_outputs| jq -r '.[]|select(.OutputKey=="PrivateSubnetOne").OutputValue')
az_two_subnet=$(echo $get_cft_outputs| jq -r '.[]|select(.OutputKey=="PrivateSubnetTwo").OutputValue')
az_three_subnet=$(echo $get_cft_outputs| jq -r '.[]|select(.OutputKey=="PrivateSubnetThree").OutputValue')
get_vpc_id=$(echo $get_cft_outputs| jq -r '.[]|select(.OutputKey=="VpcId").OutputValue')

cp ${cluster_template_yaml} ${cluster_template_output} 
sed -i "s/replace_key_name/${karpenter_key_name}/g;\
    s/replace_cluster_name/${new_cluster_name}/g;\
    s/replace_vpc_id/${get_vpc_id}/g;\
    s/replace_az_one/${az_one_subnet}/g;\
    s/replace_az_two/${az_two_subnet}/g;\
    s/replace_az_three/${az_three_subnet}/g;\
    s/replace_region_name/${region_name}/g" ${cluster_template_output}

sed -i "s/replace_az_one/${az_one_subnet}/g;\
    s/replace_az_two/${az_two_subnet}/g;\
    s/replace_az_three/${az_three_subnet}/g;" karpenter_provisioner.yml

