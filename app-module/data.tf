#######################
#### Terraform Cloud ##
#######################

data "terraform_remote_state" "infra" {
  backend = "remote"

  config = {
    organization = var.organization
    workspaces = {
      name = var.infra_workspace_name
    }
  }
}

#######################
######## EKS ##########
#######################

data "kubernetes_storage_class" "name" {
  metadata { name = "gp2" }
  depends_on = [module.eks]
}

data "kubernetes_ingress_v1" "external_ingress" {
  metadata {
    name      = "external-ingress"
    namespace = "ingress"
  }
  depends_on = [null_resource.wait_for_external_ingress, module.eks, kubernetes_ingress_v1.nginx_ingress]
}

data "kubernetes_ingress_v1" "internal_ingress" {
  metadata {
    name      = "internal-ingress"
    namespace = "ingress"
  }
  depends_on = [null_resource.wait_for_internal_ingress, module.eks, kubernetes_ingress_v1.nginx_ingress]
}

data "aws_eks_cluster_auth" "eks" {
  name       = local.cluster_name
  depends_on = [module.eks]
}

data "aws_ami" "fpga" {
  owners     = ["${var.hyperspace_account_id}"]
  name_regex = "eks-1\\.31-fpga-prod"
}

#######################
### Load Balancer #####
#######################

data "aws_lb" "argocd_privatelink_nlb" {
  count = var.create_eks ? 1 : 0
  tags = {
    "elbv2.k8s.aws/cluster"    = module.eks.cluster_name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "argocd/argocd-server"
  }

  depends_on = [helm_release.argocd]
}

data "aws_lb" "internal_alb" {
  count = var.create_eks ? 1 : 0
  tags = {
    "elbv2.k8s.aws/cluster"    = module.eks.cluster_name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "ingress/internal-ingress"
  }

  depends_on = [kubernetes_ingress_v1.nginx_ingress["internal"]]
}

data "aws_lb" "external_alb" {
  count = var.create_eks && var.create_public_zone ? 1 : 0
  tags = {
    "elbv2.k8s.aws/cluster"    = module.eks.cluster_name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "ingress/external-ingress"
  }

  depends_on = [kubernetes_ingress_v1.nginx_ingress["external"]]
}