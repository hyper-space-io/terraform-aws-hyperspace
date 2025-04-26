locals {
  tags                                       = jsondecode(var.tags)
  vpc_module                                 = jsondecode(var.vpc_module)
  s3_bucket_names                            = jsondecode(var.s3_buckets_names)
  s3_bucket_arns                             = jsondecode(var.s3_buckets_arns)
  iam_policies                               = jsondecode(var.iam_policies)
  local_iam_policies                         = jsondecode(var.local_iam_policies)
  availability_zones                         = jsondecode(var.availability_zones)
  worker_instance_type                       = jsondecode(var.worker_instance_type)
  argocd_endpoint_allowed_principals         = jsondecode(var.argocd_endpoint_allowed_principals)
  argocd_endpoint_additional_aws_regions     = jsondecode(var.argocd_endpoint_additional_aws_regions)
  argocd_endpoint_default_aws_regions        = ["eu-central-1", "us-east-1"]
  argocd_endpoint_default_allowed_principals = ["arn:aws:iam::${var.hyperspace_account_id}:root"]
  prometheus_endpoint_additional_cidr_blocks = jsondecode(var.prometheus_endpoint_additional_cidr_blocks)
  prometheus_remote_write_endpoint           = "https://prometheus.internal.devops-dev.hyper-space.xyz/api/v1/write"
  internal_ingress_class_name                = "nginx-internal"
  vcs_configuration                          = jsondecode(var.vcs_configuration)

  alb_values = <<EOT
  vpcId: ${local.vpc_module.vpc_id}
  region: ${var.aws_region}
  EOT

  #################
  ##### EKS #######
  #################
  cluster_name = "${var.project}-${var.environment}"

  default_node_pool_tags = {
    "k8s.io/cluster-autoscaler/enabled"               = "True"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "True"
  }

  additional_self_managed_node_pools = {
    # data-nodes service nodes
    eks-data-node-hyperspace = {
      name                     = "eks-data-node-${local.cluster_name}"
      iam_role_name            = "data-node-${local.cluster_name}"
      enable_monitoring        = true
      min_size                 = 0
      max_size                 = 20
      desired_size             = 0
      instance_type            = "f1.2xlarge"
      ami_id                   = "${data.aws_ami.fpga.id}"
      bootstrap_extra_args     = "--kubelet-extra-args '--node-labels=hyperspace.io/type=fpga --register-with-taints=fpga=true:NoSchedule'"
      post_bootstrap_user_data = <<-EOT
      #!/bin/bash -e
      mkdir /data
      vgcreate "data" /dev/nvme0n1
      COUNT=1
      lvcreate -l 100%VG -i $COUNT -n data data
      mkfs.xfs /dev/data/data
      mount /dev/mapper/data-data /data
      echo "/dev/mapper/data-data /data xfs defaults,noatime 1 1" >> /etc/fstab
      mkdir /data/private/
      EOT
      tags                     = merge(local.tags, { nodegroup = "fpga" })
      autoscaling_group_tags = merge(local.default_node_pool_tags, {
        "k8s.io/cluster-autoscaler/node-template/taint/fpga"              = "true:NoSchedule"
        "k8s.io/cluster-autoscaler/node-template/resources/hugepages-1Gi" = "100Gi"
      })
      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            encrypted   = true
            volume_size = 200
            volume_type = "gp3"
            iops        = 3000
            throughput  = 125
          }
        }
      }
    }
  }

  #################
  ##### Auth0 #####
  #################
  auth0_ingress_cidr_blocks = {
    us = [
      "174.129.105.183/32",
      "18.116.79.126/32",
      "18.117.64.128/32",
      "18.191.46.63/32",
      "18.218.26.94/32",
      "18.232.225.224/32",
      "18.233.90.226/32",
      "3.131.238.180/32",
      "3.131.55.63/32",
      "3.132.201.78/32",
      "3.133.18.220/32",
      "3.134.176.17/32",
      "3.19.44.88/32",
      "3.20.244.231/32",
      "3.21.254.195/32",
      "3.211.189.167/32",
      "34.211.191.214/32",
      "34.233.19.82/32",
      "34.233.190.223/32",
      "35.160.3.103/32",
      "35.162.47.8/32",
      "35.166.202.113/32",
      "35.167.74.121/32",
      "35.171.156.124/32",
      "35.82.131.220/32",
      "44.205.93.104/32",
      "44.218.235.21/32",
      "44.219.52.110/32",
      "52.12.243.90/32",
      "52.2.61.131/32",
      "52.204.128.250/32",
      "52.206.34.127/32",
      "52.43.255.209/32",
      "52.88.192.232/32",
      "52.89.116.72/32",
      "54.145.227.59/32",
      "54.157.101.160/32",
      "54.200.12.78/32",
      "54.209.32.202/32",
      "54.245.16.146/32",
      "54.68.157.8/32",
      "54.69.107.228/32"
    ],
    eu = [
      "18.197.9.11/32",
      "18.198.229.148/32",
      "3.125.185.137/32",
      "3.65.249.224/32",
      "3.67.233.131/32",
      "3.68.125.137/32",
      "3.72.27.152/32",
      "3.74.90.247/32",
      "34.246.118.27/32",
      "35.157.198.116/32",
      "35.157.221.52/32",
      "52.17.111.199/32",
      "52.19.3.147/32",
      "52.208.95.174/32",
      "52.210.121.45/32",
      "52.210.122.50/32",
      "52.28.184.187/32",
      "52.30.153.34/32",
      "52.57.230.214/32",
      "54.228.204.106/32",
      "54.228.86.224/32",
      "54.73.137.216/32",
      "54.75.208.179/32",
      "54.76.184.103/32"
    ]
  }

  ##################
  ##### VCS ########
  ##################

  # GitHub configuration
  github_config = {
    enabled     = local.vcs_configuration.github.enabled
    secret_name = local.vcs_configuration.github.secret_name
  }

  # GitLab configuration (for future implementation)
  gitlab_config = {
    enabled     = try(local.vcs_configuration.gitlab.enabled, false)
    ssh_key = {
      enabled     = try(local.vcs_configuration.gitlab.ssh_key.enabled, false)
      secret_name = try(local.vcs_configuration.gitlab.ssh_key.secret_name, "argocd/gitlab-ssh-key")
    }
    access_token = {
      enabled     = try(local.vcs_configuration.gitlab.access_token.enabled, false)
      secret_name = try(local.vcs_configuration.gitlab.access_token.secret_name, "argocd/gitlab-access-token")
    }
  }

  # GitHub connector (only if enabled)
  github_connector = try(local.vcs_configuration.github.enabled, false) ? {
    type = "github"
    id   = "github"
    name = "GitHub"
    config = {
      clientID     = try(jsondecode(data.aws_secretsmanager_secret_version.github_secret[0].secret_string).client_id, null)
      clientSecret = try(jsondecode(data.aws_secretsmanager_secret_version.github_secret[0].secret_string).client_secret, null)
      orgs = [{
        name = local.vcs_configuration.organization
      }]
    }
  } : null

  # Connector configuration
  # ADD SUPPORT FOR GITLAB CONNECTOR LATER 
  dex_connectors = local.github_connector

  # ArgoCD secret configuration
  argocd_secret_config = try(local.vcs_configuration.github.enabled, false) ? {
    extra = {
      "dex.github.clientSecret" = try(jsondecode(data.aws_secretsmanager_secret_version.github_secret[0].secret_string).client_secret, null)
    }
  } : {}

  # ArgoCD credential templates
  argocd_credential_templates = try(local.vcs_configuration.github.enabled, false) ? {
    "github-creds" = {
      url = "https://github.com/${local.vcs_configuration.organization}/"
      githubAppID             = try(jsondecode(data.aws_secretsmanager_secret_version.github_secret[0].secret_string).github_app_id, null)
      githubAppInstallationID = try(jsondecode(data.aws_secretsmanager_secret_version.github_secret[0].secret_string).github_installation_id, null)
      githubAppPrivateKey     = try(jsondecode(data.aws_secretsmanager_secret_version.github_secret[0].secret_string).private_key, null)
    }
  } : {}
}