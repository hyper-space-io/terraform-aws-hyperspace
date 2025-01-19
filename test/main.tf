module "infra" {
  source = "git@github.com:Hyperspace-terraform-module/Infra-module.git?ref=setup-cluster-tools"
  dex_connectors = jsonencode([
  {
    type = "github"
    id   = "github"
    name = "GitHub"
    config = {
      clientID     = "9572f7c8b59a07404dc9"
      clientSecret = "8074b2a44adb588cf1202e27afe756ccc5cb029d"
      orgs         = "hyper-space-io"
    }
  }
  ])
  domain_name = "hyper-space.xyz"
  environment = "dev-idan"
  flow_log_group_class = "INFREQUENT_ACCESS"
  worker_instance_type = ["m5n.large"]
}
