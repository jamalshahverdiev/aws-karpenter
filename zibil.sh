#!/usr/bin/env bash

karpenter_key_name='karpenter_ec2_key'
all_keypair_names=$(aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName' --output text)
count=600

if [[ "$all_keypair_names" == *"$karpenter_key_name"* ]]; then
    echo "Key with name: ${karpenter_key_name} already exists."
else
    aws ec2 create-key-pair --key-name "${karpenter_key_name}" | jq -r ".KeyMaterial" > ~/.ssh/${karpenter_key_name}.pem
fi

if [[ $(aws cloudformation describe-stacks --stack-name setup-infrastructure --query 'Stacks[].StackName' --output text) != 'setup-infrastructure' ]]; then
    aws cloudformation create-stack --stack-name setup-infrastructure \
        --capabilities CAPABILITY_IAM \
        --template-body file://./${cf_stack_file} \
        --region ${region_name} &
fi

while [[ $count > 0 ]] ; do
    echo "$count"
    count=$(( $count - 1 ))
    if [[ $(aws cloudformation describe-stacks --stack-name setup-infrastructure --query 'Stacks[].StackStatus' --output text) == 'CREATE_COMPLETE' ]]; then
        echo "Cloudformation stack for network settings deployed successful!"
        break
    fi
done

echo salam