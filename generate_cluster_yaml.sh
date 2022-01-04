#!/usr/bin/env bash

. ./variables.sh

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
export az_one_subnet=$(echo $get_cft_outputs| jq -r '.[]|select(.OutputKey=="PrivateSubnetOne").OutputValue')
export az_two_subnet=$(echo $get_cft_outputs| jq -r '.[]|select(.OutputKey=="PrivateSubnetTwo").OutputValue')
export az_three_subnet=$(echo $get_cft_outputs| jq -r '.[]|select(.OutputKey=="PrivateSubnetThree").OutputValue')
export get_vpc_id=$(echo $get_cft_outputs| jq -r '.[]|select(.OutputKey=="VpcId").OutputValue')

cat ${cluster_template_yaml} | envsubst > ${cluster_template_output}
cat ${karpenter_provisioner_template_file} | envsubst > ${provisioner_file}

