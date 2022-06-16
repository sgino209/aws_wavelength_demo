#!/bin/bash

# Created by Danit Consultancy & Development at June 2022
# All rights reserved

# ------------------------       -----------------------------------------
# | us-east1 Region      |       | Wavelength Zone (BOS)                 |
# | -------------------------------------------------------------------- |
# | | VPC                |       |                                     | |
# | | ------------------ |       | ---------------------               | |
# | | | Public subnet  | |       | | Private subnet    |               | |
# | | | -------------- | |       | | ----------------- |   ----------- | |    ------------
# | | | | Web Server | | |       | | |  API server   | |   | Carrier | | |    | Telecom  |
# | | | | (Bastion)  |<-----SSH----->|  ("proxy")    |<--->| Gateway |<------>| Provider |<---> 5G Mobile
# | | | |            | | |   |   | | |               | |   ----------- | |    ------------      Client
# | | | -------------- | |   |   | | ----------------- |               | |         |
# | | |       |        | |   |   | | -------- -------- |               | |         |
# | | |       |        | |   ------->| App1 | | App2 | |               | |         |
# | | |       |        | |       | | -------- -------- |               | |         |
# | | --------|--------- |       | ---------------------               | |         |
# | ----------|--------------------------------------------------------- |         |
# |           |          |       |                                       |         |
# ------------|-----------       -----------------------------------------         |
#             |                                                                    |
#             --------------------------Internet -----------------------------------


# Load setup parameters
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
else
  echo "[ERROR] Could not find .env file with essential setup parameters"
  exit 2
fi

# -------------------------- Create the VPC and associated resources --------------------------

# Use the AWS CLI to create the VPC:
export VPC_ID=$(aws ec2 --region $REGION --output text create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId')
echo '\nVPC_ID='$VPC_ID

# Create an internet gateway and attach it to the VPC:
export IGW_ID=$(aws ec2 --region $REGION --output text create-internet-gateway --query 'InternetGateway.InternetGatewayId')
echo '\nIGW_ID='$IGW_ID

aws ec2 --region $REGION attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# Add the carrier gateway:
export CAGW_ID=$(aws ec2 --region $REGION --output text create-carrier-gateway --vpc-id $VPC_ID --query 'CarrierGateway.CarrierGatewayId')
echo '\nCAGW_ID='$CAGW_ID

# -------------------------------- Deploy the security groups ---------------------------------

# Create the bastion security group and add the ingress SSH role (note that SSH access is only being allowed from your current IP address)
export BASTION_SG_ID=$(aws ec2 --region $REGION \
export BASTION_SG_ID=$(aws ec2 --region $REGION --output text create-security-group --group-name bastion-sg --description "Security group for bastion host" --vpc-id $VPC_ID --query 'GroupId')
echo '\nBASTION_SG_ID='$BASTION_SG_ID

curr_ip_address=$(curl https://checkip.amazonaws.com)
aws ec2 --region $REGION authorize-security-group-ingress --group-id $BASTION_SG_ID --protocol tcp --port 22 --cidr $curr_ip_address/32
aws ec2 --region $REGION authorize-security-group-ingress --group-id $BASTION_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

# Create the API security group along with two ingress rules: one for SSH from the bastion security group and one opening up the port the API server communicates on (5000):
export API_SG_ID=$(aws ec2 --region $REGION --output text create-security-group --group-name api-sg --description "Security group for API host" --vpc-id $VPC_ID --query 'GroupId')
echo '\nAPI_SG_ID='$API_SG_ID

aws ec2 --region $REGION authorize-security-group-ingress --group-id $API_SG_ID --protocol tcp --port 22 --source-group $BASTION_SG_ID
aws ec2 --region $REGION authorize-security-group-ingress --group-id $API_SG_ID --protocol tcp --port 5000 --cidr 0.0.0.0/0

# Create the security group for the inference server along with three ingress rules: one for SSH from the bastion security group, 
# and opening the ports the inference server communicates on (8080 and 8081) to the API security group:
export INFERENCE_SG_ID=$(aws ec2 --region $REGION --output text create-security-group --group-name inference-sg --description "Security group for inference host" --vpc-id $VPC_ID --query 'GroupId')
echo '\nINFERENCE_SG_ID='$INFERENCE_SG_ID

aws ec2 --region $REGION authorize-security-group-ingress --group-id $INFERENCE_SG_ID --protocol tcp --port 22 --source-group $BASTION_SG_ID
aws ec2 --region $REGION authorize-security-group-ingress --group-id $INFERENCE_SG_ID --protocol tcp --port 8080 --source-group $API_SG_ID
aws ec2 --region $REGION authorize-security-group-ingress --group-id $INFERENCE_SG_ID --protocol tcp --port 8081 --source-group $API_SG_ID

# ---------------------------- Add the subnets and routing tables -----------------------------

# Create the subnet for the Wavelength Zone:
export WL_SUBNET_ID=$(aws ec2 --region $REGION --output text create-subnet --cidr-block 10.0.0.0/24 --availability-zone $WL_ZONE --vpc-id $VPC_ID --query 'Subnet.SubnetId')
echo '\nWL_SUBNET_ID='$WL_SUBNET_ID

# Create the route table for the Wavelength subnet:
export WL_RT_ID=$(aws ec2 --region $REGION --output text create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId')
echo '\nWL_RT_ID='$WL_RT_ID

# Associate the route table with the Wavelength subnet and a route to route traffic to the carrier gateway which in turns routes traffic to the carrier mobile network:
aws ec2 --region $REGION associate-route-table --route-table-id $WL_RT_ID --subnet-id $WL_SUBNET_ID
aws ec2 --region $REGION create-route --route-table-id $WL_RT_ID --destination-cidr-block 0.0.0.0/0 --carrier-gateway-id $CAGW_ID

# Create the bastion subnet:
BASTION_SUBNET_ID=$(aws ec2 --region $REGION --output text create-subnet --cidr-block 10.0.1.0/24 --vpc-id $VPC_ID --query 'Subnet.SubnetId')
echo '\nBASTION_SUBNET_ID='$BASTION_SUBNET_ID

# Deploy the bastion subnet route table and a route to direct traffic to the internet gateway:
export BASTION_RT_ID=$(aws ec2 --region $REGION --output text create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId')
echo '\nBASTION_RT_ID='$BASTION_RT_ID

aws ec2 --region $REGION create-route --route-table-id $BASTION_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 --region $REGION associate-route-table --subnet-id $BASTION_SUBNET_ID --route-table-id $BASTION_RT_ID

# Modify the bastion’s subnet to assign public IPs by default:
aws ec2 --region $REGION modify-subnet-attribute --subnet-id $BASTION_SUBNET_ID --map-public-ip-on-launch

# --------------------- Create the Elastic IPs and networking interfaces ----------------------

# Create two carrier IPs, one for the API server and one for the inference server:
export INFERENCE_CIP_ALLOC_ID=$(aws ec2 --region $REGION --output text allocate-address --domain vpc --network-border-group $NBG --query 'AllocationId')
echo '\nINFERENCE_CIP_ALLOC_ID='$INFERENCE_CIP_ALLOC_ID

export API_CIP_ALLOC_ID=$(aws ec2 --region $REGION --output text allocate-address --domain vpc --network-border-group $NBG --query 'AllocationId')
echo '\nAPI_CIP_ALLOC_ID='$API_CIP_ALLOC_ID


# Create two elastic network interfaces (ENIs):
export INFERENCE_ENI_ID=$(aws ec2 --region $REGION --output text create-network-interface --subnet-id $WL_SUBNET_ID --groups $INFERENCE_SG_ID --query 'NetworkInterface.NetworkInterfaceId')
echo '\nINFERENCE_ENI_ID='$INFERENCE_ENI_ID

export API_ENI_ID=$(aws ec2 --region $REGION --output text create-network-interface --subnet-id $WL_SUBNET_ID --groups $API_SG_ID --query 'NetworkInterface.NetworkInterfaceId')
echo '\nAPI_ENI_ID='$API_ENI_ID

# Associate the carrier IPs with the ENIs:
aws ec2 --region $REGION associate-address --allocation-id $INFERENCE_CIP_ALLOC_ID --network-interface-id $INFERENCE_ENI_ID   
aws ec2 --region $REGION associate-address --allocation-id $API_CIP_ALLOC_ID --network-interface-id $API_ENI_ID

# -------------------------- Deploy the API and inference instances ---------------------------

# Deploy the API instance:
aws ec2 --region $REGION run-instances --instance-type t3.medium --network-interface '[{"DeviceIndex":0,"NetworkInterfaceId":"'$API_ENI_ID'"}]' --image-id $API_IMAGE_ID --key-name $KEY_NAME

# Deploy the inference instance:
aws ec2 --region $REGION run-instances --instance-type g4dn.2xlarge --network-interface '[{"DeviceIndex":0,"NetworkInterfaceId":"'$INFERENCE_ENI_ID'"}]' --image-id $INFERENCE_IMAGE_ID --key-name $KEY_NAME

# ------------------------------ Deploy the bastion / web server ------------------------------

# Issue the command below to create your bastion host
aws ec2 --region $REGION run-instances --instance-type t3.medium --associate-public-ip-address --subnet-id $BASTION_SUBNET_ID --image-id $BASTION_IMAGE_ID --security-group-ids $BASTION_SG_ID --key-name $KEY_NAME

# -------------------------- Configure the bastion host / web server --------------------------

