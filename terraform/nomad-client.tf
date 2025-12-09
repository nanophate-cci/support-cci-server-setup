module "nomad_clients" {
  source = "git::https://github.com/kurtassad/server-terraform.git//nomad-aws"

  aws_region = local.region

  nodes = 1

  subnet = module.vpc.public_subnets[0]
  vpc_id = module.vpc.vpc_id

  nomad_server_hostname = "circleci.aws.cci.nanophate.com"

  # VPC magic, DNS server is always on VPC CIDR base + 2
  dns_server    = cidrhost(module.vpc.vpc_cidr_block, 2)
  blocked_cidrs = []

  instance_tags = merge(
    {
      "vendor" = "circleci"
      "team"   = "sre"
    },
    local.cost_center_tags
  )
  nomad_auto_scaler = false

  enable_irsa = {}

  ssh_key  = file("./naoya-cci-server-setup-nomad.pub")
  basename = local.cluster_name

  enable_imdsv2 = "required"

  client_public_ip = true

  # Use local CA and client certificates
  ca_certificate     = file("../secrets/nomad-certs/nomad-ca.pem")
  client_certificate = file("../secrets/nomad-certs/nomad-client-cert.pem")
  client_key         = file("../secrets/nomad-certs/nomad-client-key.pem")
}
