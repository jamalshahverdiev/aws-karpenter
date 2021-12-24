#!/usr/bin/env bash

cluster_template_yaml='cluster.yaml'
cluster_template_output='cluster_output.yaml' && rm ${cluster_template_output}
karpenter_key_name='karpenter_ec2_key'
new_cluster_name='karpenter-demo' 
all_keypair_names=$(aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName' --output text)
subnet_third_octets='''
11
12
13
20
21
22
23
'''

if [[ "$all_keypair_names" == *"$karpenter_key_name"* ]]; then
    echo "Key with name: ${karpenter_key_name} already exists."
else
    aws ec2 create-key-pair --key-name "${karpenter_key_name}" | jq -r ".KeyMaterial" > ~/.ssh/${karpenter_key_name}.pem
fi

create_ngw_igw() {
    create_subnet_object=$(aws ec2 create-subnet --vpc-id ${get_vpc_id} --cidr-block 10.0.10.0/24)
    subnet_id_of_object=$(echo ${create_subnet_object} | jq -r '.Subnet.SubnetId')
    aws ec2 create-tags --resources ${subnet_id_of_object} --tags Key=Name,Value=Public_10 &
    create_internet_gateway_object_for_vpc=$(aws ec2 create-internet-gateway)
    get_internet_geateway_id=$(echo $create_internet_gateway_object_for_vpc | jq -r '.InternetGateway.InternetGatewayId')
    aws ec2 create-tags --resources ${get_internet_geateway_id} --tags Key=Name,Value=Karpenter-VPC-IGW
    aws ec2 attach-internet-gateway --internet-gateway-id ${get_internet_geateway_id} --vpc-id ${get_vpc_id}
    create_elastic_ip_object_for_ngw=$(aws ec2 allocate-address --domain vpc)
    elastic_allocation_id=$(echo ${create_elastic_ip_object_for_ngw} | jq -r '.AllocationId')
    create_nat_gw_obj=$(aws ec2 create-nat-gateway --subnet-id ${subnet_id_of_object} --allocation-id ${elastic_allocation_id})
    get_nat_gateway_id=$(echo $create_nat_gw_obj  | jq -r '.NatGateway.NatGatewayId')
    aws ec2 create-tags --resources ${get_nat_gateway_id} --tags Key=Name,Value=Karpenter-NGW    
}
create_network_objects() {
    create_vpc_object=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16)
    get_vpc_id=$(echo ${create_vpc_object} | jq -r '.Vpc.VpcId')
    aws ec2 create-tags --resources ${get_vpc_id} --tags Key=Name,Value=karpenter
    create_ngw_igw
    for octet in ${subnet_third_octets}; do
        create_subnet_object=$(aws ec2 create-subnet --vpc-id ${get_vpc_id} --cidr-block 10.0.${octet}.0/24)
        subnet_id_of_object=$(echo ${create_subnet_object} | jq -r '.Subnet.SubnetId')
        create_route_table_object=$(aws ec2 create-route-table --vpc-id ${get_vpc_id})
        route_table_id_of_object=$(echo $create_route_table_object | jq -r '.RouteTable.RouteTableId')
        definition='Public_'
        if [[ ${octet} == 20 || ${octet} == 21 || ${octet} == 22 || ${octet} == 23 ]]; then 
            definition='Private_';
            aws ec2 create-route --route-table-id ${route_table_id_of_object} \
                --destination-cidr-block 0.0.0.0/0 --gateway-id ${get_nat_gateway_id} &
        else
            aws ec2 create-route --route-table-id ${route_table_id_of_object} \
                --destination-cidr-block 0.0.0.0/0 --gateway-id ${get_internet_geateway_id} &
            
        fi
        aws ec2 associate-route-table --route-table-id ${route_table_id_of_object} --subnet-id ${subnet_id_of_object} &
        for object in ${subnet_id_of_object} ${route_table_id_of_object}; do
            aws ec2 create-tags --resources ${object} --tags Key=Name,Value=${definition}${octet} &
        done
    done
}

create_network_objects

cp ${cluster_template_yaml} ${cluster_template_output} 
sed -i "s/replace_key_name/${karpenter_key_name}/g;s/replace_cluster_name/${new_cluster_name}/g;s/replace_vpc_id/${get_vpc_id}/g" ${cluster_template_output}

