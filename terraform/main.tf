#
# Terraform for deploying the compute and network resources needed for a k8s cluster
#
# Semi HA deployment (3 masters, but all in same subnet/az)
# - VPC with public and private subnets
# - cluster nodes all in private subnet
# - jumpbox and nat gateway in public subnet
# - inbound to cluster subnet only 22 (from jump box) and 6443 (from elb)


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile_name
  region = "us-east-2"
  default_tags {
    tags = {
      Environment = var.project_name
    }
  }  
}

variable "project_name" {
  nullable = false
  description = "The name to use as a prefix for aws resource names.  All AWS resources will be named project_name-xyz where xyz indicates the purpose of the resource"
}

variable "aws_profile_name" {
  nullable = false
  description = "That name of the aws profile to be use when access AWS APIs"
}

variable "ec2_keypair_name" {
  nullable = false
  description = "The name of the AWS Ec2 keypair to use to access ec2 instaces"
}

variable "remote_access_address" {
  description = "The IP address of the (remote) server that is allowed to access the nodes (as a /32 CIDR block)"
}

variable "node_vpc_cidr_block" {
  default = "10.2.0.0/16"
  description = "This is the CIDR block for the VPC where the cluster will live"
}

variable "cluster_cidr_block" {
  default = "10.200.0.0/16"
  description = "The CIDR block to be used for Cluster IP addresses"
}

variable "controller_instance_count" {
  nullable = true
  default = 3
  description = "The number of controller nodes"
}

variable "worker_instance_count" {
  nullable = true
  default = 3
  description = "The number of worker nodes"  
}

locals {
  public_subnet_cidr_block = cidrsubnet(var.node_vpc_cidr_block,8,1)
  private_subnet_cidr_block = cidrsubnet(var.node_vpc_cidr_block,8,2)
}

data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu_jammy" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  owners = ["099720109477"]  # amazon
}


module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = var.node_vpc_cidr_block
  public_subnet_cidr_block = local.public_subnet_cidr_block
  resource_name = var.project_name
  jumpbox_ami_id = data.aws_ami.ubuntu_jammy.id
  instance_keypair_name = var.ec2_keypair_name
  remote_access_cidr_block = var.remote_access_address
  create_nat_gateway = true

}

module "cluster" {
  source = "./modules/cluster"

  vpc_id = module.vpc.vpc_id
  nat_gateway_id = module.vpc.nat_gateway_id
  private_subnet_cidr_block = local.private_subnet_cidr_block
  resource_name = var.project_name
  node_ami_id = data.aws_ami.ubuntu_jammy.id
  instance_keypair_name = var.ec2_keypair_name
  cluster_cidr_block = var.cluster_cidr_block
  controller_instance_count = var.controller_instance_count
  worker_instance_count = var.worker_instance_count

}


resource "aws_lb" "cluster-api" {
  name               = "${var.project_name}-cluster-api"
  internal           = false
  load_balancer_type = "network"
  subnets            = [module.vpc.public_subnet_id]
}

resource "aws_lb_target_group" "cluster-api" {
  name        = "${var.project_name}-cluster-api"
  port        = 6443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_lb_target_group_attachment" "cluster-api" {
  count = length(module.cluster.controller_ips)

  target_group_arn = aws_lb_target_group.cluster-api.arn
  target_id        = module.cluster.controller_ips[count.index]
  port             = 6443
}

resource "aws_lb_listener" "cluster-api" {
  load_balancer_arn = aws_lb.cluster-api.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cluster-api.arn
  }
}

# Create target goupr and listener for rancher's registration server
resource "aws_lb_target_group" "rancher-server" {
  name        = "${var.project_name}-rancher-server"
  port        = 9345
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_lb_target_group_attachment" "rancher-server" {
  count = length(module.cluster.controller_ips)

  target_group_arn = aws_lb_target_group.rancher-server.arn
  target_id        = module.cluster.controller_ips[count.index]
  port             = 9345
}

resource "aws_lb_listener" "rancher-server" {
  load_balancer_arn = aws_lb.cluster-api.arn
  port              = "9345"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rancher-server.arn
  }
}
