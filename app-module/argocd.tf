resource "helm_release" "argocd" {
  count            = var.create_eks ? 1 : 0
  chart            = "argo-cd"
  namespace        = "argocd"
  name             = "argocd"
  version          = "7.7.11"
  depends_on       = [helm_release.nginx-ingress]
  create_namespace = true
  cleanup_on_fail  = true
  repository       = "https://argoproj.github.io/argo-helm"

  values = [
    yamlencode({
      global = {
        domain = "argocd.${local.internal_domain_name}"
      }
      dex = {
        enabled = true
      }
      redis = {
      }
      configs = {
        rbac = {
          "policy.default" = "${var.argocd_rbac_policy_default}"
          "policy.csv"     = try(join("\n", var.argocd_rbac_policy_rules), "")
        }
        cm = {
          "exec.enabled"           = "false"
          "timeout.reconciliation" = "5s"
          "accounts.hyperspace"    = "login"
          "dex.config" = yamlencode({
            connectors = [
              for connector in jsondecode(var.dex_connectors) : {
                type   = connector.type
                id     = connector.id
                name   = connector.name
                config = connector.config
              }
            ]
          })
        }
      }
      server = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-internal"               = "true"
            "service.beta.kubernetes.io/aws-load-balancer-type"                   = "nlb-ip"
            "service.beta.kubernetes.io/aws-load-balancer-scheme"                 = "internal"
            "service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy" = "ELBSecurityPolicy-TLS13-1-2-2021-06"
          }
        }
        autoscaling = {
          enabled     = true
          minReplicas = "1"
        }
        extraArgs = ["--insecure"]
        ingress = {
          enabled          = true
          ingressClassName = "nginx-internal"
          hosts = [
            "argocd.${local.internal_domain_name}"
          ]
          https = false
        }
      }
      applicationSet = {
        replicas = 2
      }
      repoServer = {
        autoscaling = {
          enabled     = true
          minReplicas = "1"
        }
      }
    })
  ]
}

# Execute ArgoCD CLI setup and password update
resource "null_resource" "argocd_setup" {
  count = var.create_eks ? 1 : 0

  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Installing ArgoCD CLI..."
      VERSION=$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
      curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$VERSION/argocd-linux-amd64
      sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
      rm argocd-linux-amd64

      echo "Getting ArgoCD admin password..."
      ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

      echo "Logging in to ArgoCD..."
      argocd login argocd.${local.internal_domain_name} --username admin --password $ARGOCD_PASSWORD --insecure

      echo "Updating hyperspace user password..."
      argocd account update-password \
        --account hyperspace \
        --current-password $ARGOCD_PASSWORD \
        --new-password hyperspace

      echo "Setup completed successfully!"
    EOT
  }
}

