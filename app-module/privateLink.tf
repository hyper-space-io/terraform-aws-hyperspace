resource "null_resource" "argocd_privatelink_nlb_active" {
  count = var.create_eks && var.enable_argocd ? 1 : 0
  provisioner "local-exec" {
    command = <<EOF
      until STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns ${data.aws_lb.argocd_privatelink_nlb[0].arn} --query 'LoadBalancers[0].State.Code' --output text) && [ "$STATE" = "active" ]; do
        echo "Waiting for NLB to become active... Current state: $STATE"
        sleep 10
      done
      echo "NLB is now active"
    EOF
  }

  triggers = {
    nlb_arn = data.aws_lb.argocd_privatelink_nlb[0].arn
  }
}

resource "aws_vpc_endpoint_service" "argocd_server" {
  count                      = var.create_eks && var.enable_argocd ? 1 : 0
  acceptance_required        = false
  network_load_balancer_arns = [data.aws_lb.argocd_privatelink_nlb[0].arn]
  allowed_principals         = distinct(concat(local.argocd_endpoint_allowed_principals, local.argocd_endpoint_default_allowed_principals))
  supported_regions          = distinct(concat([var.aws_region], local.argocd_endpoint_additional_aws_regions, local.argocd_endpoint_default_aws_regions))
  private_dns_name           = "argocd.${var.project}.${local.internal_domain_name}"

  tags = merge(local.tags, {
    Name = "ArgoCD Endpoint Service - ${var.project}-${var.environment}"
  })

  depends_on = [data.aws_lb.argocd_privatelink_nlb[0]]
}