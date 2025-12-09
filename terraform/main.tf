terraform {
  backend "s3" {
    bucket = "ka-cci-terraform-state"
    key    = "ka-cci/default/terraform.tfstate"
    region = "ap-southeast-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.15.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

# Configure params here
locals {
  cluster_name   = "ka-cci"
  region         = "ap-southeast-1"
  email          = "kurtis.assad@circleci.com"
  critical_until = "2026-12-30"

  # Need to get this from route53
  hosted_zones = ["arn:aws:route53:::hostedzone/Z09353691DH93X3LBRCKB"]
}

# Derived params
locals {
  cost_center_tags = {
    cost_center       = "sm"
    Team              = "customer_engineering"
    asset_criticality = "false"
    iac               = "true"
    critical_until    = local.critical_until
    owner             = local.email
    Terraform         = "true"
  }

  public_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

provider "aws" {
  region = local.region
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.0"

  name = "${local.cluster_name}-eks-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["${local.region}a", "${local.region}b", "${local.region}c"]
  public_subnets = local.public_subnets

  enable_nat_gateway = false
  single_nat_gateway = false

  map_public_ip_on_launch = true

  tags = local.cost_center_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.8.0"

  name               = local.cluster_name
  kubernetes_version = "1.33"

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  security_group_additional_rules = {
    egress_all = {
      description = "Control plane all egress"
      protocol    = "all"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  node_security_group_additional_rules = {
    egress_all = {
      description = "Node all egress"
      protocol    = "all"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }

    ingress_self_all = {
      description = "Node to node"
      protocol    = "all"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    ingress_from_nomad = {
      description              = "Allow Nomad clients to connect to Nomad server running in Kubernetes"
      protocol                 = "tcp"
      from_port                = 4646
      to_port                  = 4648
      type                     = "ingress"
      source_security_group_id = module.nomad_clients.nomad_sg_id
    }

  }

  // Remove automatic SG tag on cluster SG. If not done, ingress will get confused when syncing LB
  node_security_group_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = null,
  }

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute              = true
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    ka_x86_nodes = {
      associate_public_ip_address = true
      ami_type                    = "AL2023_x86_64_STANDARD"
      instance_types              = ["t3.2xlarge"]
      capacity_type               = "SPOT"

      subnet_ids = module.vpc.public_subnets

      attach_cluster_primary_security_group = true

      desired_size = 5
      min_size     = 5
      max_size     = 5

      tags = local.cost_center_tags
    }
  }

  tags = local.cost_center_tags
}
