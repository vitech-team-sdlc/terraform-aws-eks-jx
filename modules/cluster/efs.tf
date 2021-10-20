resource "aws_efs_file_system" "efs" {
  creation_token = "${var.cluster_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode = "bursting"
  encrypted = "true"
  tags = {
    Name = "${var.cluster_name}-efs"
  }
}

resource "aws_security_group" "ingress-efs" {
  name = "${var.cluster_name}-efs-sg"
  vpc_id = var.create_vpc ? module.vpc.vpc_id : var.vpc_id

  // NFS
  ingress {
    security_groups = [module.eks.cluster_security_group_id]
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
  }

  // Terraform removes the default rule
  egress {
    security_groups = [module.eks.cluster_security_group_id]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
}

// K8S PV
resource "kubernetes_persistent_volume" "efs-pv" {
  metadata {
    name = "efs"
  }
  spec {
    capacity = {
      storage = "20Gi"
    }
    storage_class_name = "efs-sc"
    access_modes = ["ReadWriteMany"]
    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = aws_efs_file_system.efs.id
      }
    }
  }
}

resource "kubernetes_storage_class" "efs-sc" {
  metadata {
    name = "efs-sc"
  }
  storage_provisioner = "efs.csi.aws.com"
}