##############
# VPC
##############

module "vpc" {
  source                                          = "terraform-aws-modules/vpc/aws"
  version                                         = "~>5.13.0"
  name                                            = "${var.project}-${var.environment}-vpc"
  cidr                                            = var.vpc_cidr
  azs                                             = length(var.availability_zones) == 0 ? local.availability_zones : var.availability_zones
  private_subnets                                 = local.private_subnets
  public_subnets                                  = local.public_subnets
  create_database_subnet_group                    = false
  enable_nat_gateway                              = var.enable_nat_gateway
  single_nat_gateway                              = var.single_nat_gateway
  one_nat_gateway_per_az                          = !var.single_nat_gateway
  map_public_ip_on_launch                         = true
  enable_dns_hostnames                            = true
  manage_default_security_group                   = true
  enable_flow_log                                 = var.create_vpc_flow_logs
  vpc_flow_log_tags                               = var.create_vpc_flow_logs ? var.tags : null
  flow_log_destination_type                       = "cloud-watch-logs"
  create_flow_log_cloudwatch_log_group            = var.create_vpc_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_logs_retention
  flow_log_cloudwatch_log_group_class             = var.flow_log_group_class
  create_flow_log_cloudwatch_iam_role             = var.create_vpc_flow_logs
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "Type"                   = "public"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "Type"                            = "private"
  }
  tags = var.tags
}

module "endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnets
  create_security_group      = true
  security_group_name_prefix = var.project
  security_group_description = "VPC endpoint security group"

  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = {
    s3 = {
      service             = "s3"
      private_dns_enabled = true
      dns_options = {
        private_dns_only_for_inbound_resolver_endpoint = false
      }
      tags = merge(var.tags, {
        Name = "Hyperspace S3 Endpoint"
      })
    }
  }
  tags = var.tags
}

##############
# Route53
##############

resource "aws_route53_zone" "internal_domain" {
  count = var.domain_name != "" ? 1 : 0
  name  = local.internal_domain_name
}

resource "aws_route53_record" "internal_domain_ns" {
  count = local.create_records

  zone_id = var.existing_zone_id
  name    = local.internal_domain_name
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.internal_domain.0.name_servers
}

resource "aws_route53_record" "wildcard" {
  count   = local.create_records
  zone_id = var.existing_zone_id
  name    = "*"
  type    = "CNAME"
  ttl     = "300"
  records = [data.kubernetes_ingress_v1.ingress.status.0.load_balancer.0.ingress.0.hostname]
  depends_on = [
    helm_release.nginx-ingress
  ]
}

resource "aws_route53_record" "internal_wildcard" {
  count   = local.create_records
  zone_id = aws_route53_zone.internal_domain.0.zone_id
  name    = "*"
  type    = "CNAME"
  ttl     = "300"
  records = [data.kubernetes_ingress_v1.internal_ingress.status.0.load_balancer.0.ingress.0.hostname]
  depends_on = [
    helm_release.nginx-ingress
  ]
}