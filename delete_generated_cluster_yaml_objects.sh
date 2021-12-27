#!/usr/bin/env bash

vpc_name='karpenter'
get_vpc_id=$(aws ec2 describe-vpcs --filter Name=tag:Name,Values=${vpc_name} --query 'Vpcs[].VpcId' --output text)
get_all_subnets_in_vpc=$(aws ec2 describe-subnets --filter Name=vpc-id,Values=${get_vpc_id} \
    --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' | jq -r '.[]')
get_rt_by_vpc=$(aws ec2 describe-route-tables --filter "Name=vpc-id,Values=$get_vpc_id" \
    --query 'RouteTables[].RouteTableId' | jq -r '.[]')
get_rt_assocs_of_vpc=$(aws ec2 describe-route-tables --filter "Name=vpc-id,Values=$get_vpc_id" \
    --query 'RouteTables[].Associations[].RouteTableAssociationId' | jq -r '.[]')
get_vpc_sg_ids=$(aws ec2 describe-security-groups --filter "Name=vpc-id,Values=$get_vpc_id" \
    --query 'SecurityGroups[].GroupId' | jq -r '.[]')
get_nat_gw_id=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$get_vpc_id" \
    --query 'NatGateways[].NatGatewayId' --output text) && aws ec2 delete-nat-gateway --nat-gateway-id ${get_nat_gw_id} 
get_nat_gw_eip_id=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$get_vpc_id" \
    --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text) && aws ec2 release-address --allocation-id ${get_nat_gw_eip_id}
get_igw_id_by_vpc=$(aws ec2 describe-internet-gateways | \
    jq -r '.InternetGateways[]|select(.Attachments[].VpcId=="'$get_vpc_id'").InternetGatewayId')

aws ec2 detach-internet-gateway --internet-gateway-id=$get_igw_id_by_vpc --vpc-id=$get_vpc_id
aws ec2 delete-internet-gateway --internet-gateway-id=$get_igw_id_by_vpc


for route_table_assoc in ${get_rt_assocs_of_vpc}; do 
    aws ec2 disassociate-route-table --association-id ${route_table_assoc};  
done

for sc_id in $get_vpc_sg_ids; do aws ec2 delete-security-group --group-id ${sc_id}; done

for route_table in $get_rt_by_vpc; do 
    aws ec2 delete-route-table --route-table-id ${route_table}
done

for subnet_id in ${get_all_subnets_in_vpc}; do
    aws ec2 delete-subnet --subnet-id ${subnet_id}
done

### Note: VPC will note deleted until NAT and Internet gateway will not be deleted
aws ec2 delete-vpc --vpc-id=$get_vpc_id
