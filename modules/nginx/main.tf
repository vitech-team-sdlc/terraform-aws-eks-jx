locals {
  default-ssl-certificate = var.certificate_type == "le_staging" ? "default-ssl-certificate: jx/tls-${var.domain}-s" : (var.certificate_type == "le_production" ? "default-ssl-certificate: jx/tls-${var.domain}-p" : (var.certificate_type == "custom" ? "default-ssl-certificate: default/tls-ingress-certificates-ca" : "" ))
}

resource "helm_release" "nginx-ingress" {
  count            = var.create_nginx && !var.is_jx2 ? 1 : 0
  name             = var.nginx_release_name
  chart            = "ingress-nginx"
  namespace        = var.nginx_namespace
  repository       = "https://kubernetes.github.io/ingress-nginx"
  version          = var.nginx_chart_version
  create_namespace = var.create_nginx_namespace
  values = [
    templatefile("${path.module}/${var.nginx_values_file}", {
        default-ssl-certificate = local.default-ssl-certificate
      }
    )
  ]
}
