resource "helm_release" "jx-git-operator" {
  count            = var.is_jx2 ? 0 : 1
  name             = "jx-git-operator"
  chart            = "jx-git-operator"
  namespace        = "jx-git-operator"
  repository       = "https://jenkins-x-charts.github.io/repo"
  version          = "0.0.194"
  create_namespace = true

  values = var.jx_git_operator_values

  set {
    name  = "bootServiceAccount.enabled"
    value = true
  }
  set {
    name  = "env.NO_RESOURCE_APPLY"
    value = true
  }
  set {
    name  = "url"
    value = var.jx_git_url
  }
  set {
    name  = "username"
    value = var.jx_bot_username
  }
  set_sensitive {
    name  = "password"
    value = var.jx_bot_token
  }

  dynamic "set" {
    for_each = toset(var.boot_secrets)
    content {
      name  = set.value["name"]
      value = set.value["value"]
      type  = set.value["type"]
    }
  }

  depends_on = [
    null_resource.kubeconfig
  ]
}

// ----------------------------------------------------------------------------
// Cluster Autoscaler
// ----------------------------------------------------------------------------

resource "helm_release" "cluster-autoscaler" {
  count = var.enable_k8s_deployment_cluster_autoscaler ? 1 : 0
  depends_on = [
    module.eks
  ]

  name             = "cluster-autoscaler"
  namespace        = "kube-system"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = "9.10.9"
  create_namespace = false

  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role_cluster_autoscaler.this_iam_role_arn
    type  = "string"
  }
  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "autoDiscovery.enabled"
    value = "true"
  }
  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name = "extraArgs.skip-nodes-with-local-storage"
    value = "false"
  }
  set {
    name = "extraArgs.expander"
    value = "least-waste"
  }
  set {
    name = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }
  set {
    name = "extraArgs.scale-down-unneeded-time"
    value = "3m"
  }
  set {
    name = "extraArgs.scale-down-utilization-threshold"
    value = "0.75"
  }

  dynamic "set" {
    for_each = toset(var.boot_k8s_deployment_cluster_autoscaler_params)
    content {
      name  = set.value["name"]
      value = set.value["value"]
      type  = set.value["type"]
    }
  }
}