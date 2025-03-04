# Jenkins X EKS Module

This repository contains a Terraform module for creating an EKS cluster and all the necessary infrastructure to install Jenkins X via `jx boot`.

The module makes use of the [Terraform EKS cluster Module](https://github.com/terraform-aws-modules/terraform-aws-eks).

<!-- TOC -->

- [Jenkins X EKS Module](#jenkins-x-eks-module)
  - [What is a Terraform module](#what-is-a-terraform-module)
  - [How do you use this module](#how-do-you-use-this-module)
    - [Prerequisites](#prerequisites)
    - [Cluster provisioning](#cluster-provisioning)
      - [AWS_REGION](#aws_region)
    - [Cluster Autoscaling](#cluster-autoscaling)
    - [Long Term Storage](#long-term-storage)
    - [Secrets Management](#secrets-management)
    - [NGINX](#nginx)
    - [ExternalDNS](#externaldns)
    - [cert-manager](#cert-manager)
    - [Customer's CA certificates](#customers-ca-certificates)
    - [Velero Backups](#velero-backups)
      - [Enabling backups on pre-existing clusters](#enabling-backups-on-pre-existing-clusters)
    - [Production cluster considerations](#production-cluster-considerations)
    - [Configuring a Terraform backend](#configuring-a-terraform-backend)
    - [Using Spot Instances](#using-spot-instances)
    - [Worker Group Launch Templates](#worker-group-launch-templates)
      - [Enabling Worker Group Launch Templates](#enabling-worker-group-launch-templates)
      - [Transitioning from Worker Groups to Worker Groups Launch Templates](#transitioning-from-worker-groups-to-worker-groups-launch-templates)
    - [EKS node groups](#eks-node-groups)
      - [Custom EKS node groups](#custom-eks-node-groups)
    - [AWS Auth](#aws-auth)
      - [`map_users`](#map_users)
      - [`map_roles`](#map_roles)
      - [`map_accounts`](#map_accounts)
    - [Using SSH Key Pair](#using-ssh-key-pair)
    - [Using different EBS Volume type and size](#using-different-ebs-volume-type-and-size)
      - [Resizing a disk on existing nodes](#resizing-a-disk-on-existing-nodes)
    - [Support for JX3](#support-for-jx3)
    - [Existing VPC](#existing-vpc)
    - [Existing EKS cluster](#existing-eks-cluster)
    - [Examples](#examples)
    - [Module configuration](#module-configuration)
      - [Providers](#providers)
      - [Modules](#modules)
      - [Requirements](#requirements)
      - [Inputs](#inputs)
      - [Outputs](#outputs)
  - [FAQ: Frequently Asked Questions](#faq-frequently-asked-questions)
    - [IAM Roles for Service Accounts](#iam-roles-for-service-accounts)
  - [Development](#development)
    - [Releasing](#releasing)
  - [How can I contribute](#how-can-i-contribute)

<!-- /TOC -->

## What is a Terraform module

A Terraform module refers to a self-contained package of Terraform configurations that are managed as a group.
For more information about modules refer to the Terraform [documentation](https://www.terraform.io/docs/modules/index.html).

## How do you use this module

### Prerequisites

This Terraform module allows you to create an [EKS](https://aws.amazon.com/eks/) cluster ready for the installation of Jenkins X.
You need the following binaries locally installed and configured on your _PATH_:

- `terraform` (=> 0.12.17, < 2.0.0)
- `kubectl` (>=1.10)
- `aws-cli`
- `aws-iam-authenticator`
- `wget`

### Cluster provisioning

A default Jenkins X ready cluster can be provisioned by creating a _main.tf_ file in an empty directory with the following content:

```terraform
module "eks-jx" {
  source = "jenkins-x/eks-jx/aws"
}

output "jx_requirements" {
  value = module.eks-jx.jx_requirements
}

output "vault_user_id" {
  value       = module.eks-jx.vault_user_id
  description = "The Vault IAM user id"
}

output "vault_user_secret" {
  value       = module.eks-jx.vault_user_secret
  description = "The Vault IAM user secret"
}

```

All s3 buckets created by the module use Server-Side Encryption with Amazon S3-Managed Encryption Keys
(SSE-S3) by default.
You can set the value of `use_kms_s3` to true to use server-side encryption with AWS KMS (SSE-KMS).
If you don't specify the value of `s3_kms_arn`, then the default aws managed cmk is used (aws/s3)

:warning: **Note**: Using AWS KMS with customer managed keys has cost
[considerations](https://aws.amazon.com/blogs/storage/changing-your-amazon-s3-encryption-from-s3-managed-encryption-sse-s3-to-aws-key-management-service-sse-kms/).

Due to the Vault issue [7450](https://github.com/hashicorp/vault/issues/7450), this Terraform module needs for now to create a new IAM user for installing Vault.
It also creates an IAM access key whose id and secret are defined in the output above.
You need the id and secret for running [`jx boot`](#running-jx-boot).

The _jx_requirements_ output is a helper for creating the initial input for `jx boot`.

If you do not want Terraform to create a new IAM user or you do not have permissions to create one, you need to provide the name of an existing IAM user.

```terraform
module "eks-jx" {
  source     = "jenkins-x/eks-jx/aws"
  vault_user = "<your_vault_iam_username>"
}
```

You should have your [AWS CLI configured correctly](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html).

#### AWS_REGION

In addition, you should make sure to specify the region via the AWS_REGION environment variable. e.g.
`export AWS_REGION=us-east-1` and the region variable (make sure the region variable matches the environment variable)

The IAM user does not need any permissions attached to it.
For more information, refer to [Configuring Vault for EKS](https://jenkins-x.io/docs/install-setup/installing/boot/clouds/amazon/#configuring-vault-for-eks) in the Jenkins X documentation.

Once you have your initial configuration, you can apply it by running:

```sh
terraform init
terraform apply
```

This creates an EKS cluster with all possible configuration options defaulted.

You then need to export the environment variables _VAULT_AWS_ACCESS_KEY_ID_ and _VAULT_AWS_SECRET_ACCESS_KEY_.

```sh
export VAULT_AWS_ACCESS_KEY_ID=$(terraform output vault_user_id)
export VAULT_AWS_SECRET_ACCESS_KEY=$(terraform output vault_user_secret)
```

If you specified _vault_user_ you need to provide the access key id and secret for the specified user.

:warning: **Note**: This example is for getting up and running quickly.
It is not intended for a production cluster.
Refer to [Production cluster considerations](#production-cluster-considerations) for things to consider when creating a production cluster.

### Cluster Autoscaling

This does not automatically install cluster-autoscaler, it installs all of the prerequisite policies and roles required to install autoscaler.
The actual autoscaler installation varies depending on what version of kubernetes you are using.

To install cluster autoscaler, first you will need the ARN of the cluster-autoscaler role.

You can create the following output along side your module definition to find this:

```terraform
output "cluster_autoscaler_iam_role_arn" {
  value = module.eks-jx.cluster_autoscaler_iam_role.this_iam_role_arn
}
```

With the ARN, you may now install the cluster autoscaler using Helm.

Create the file `cluster-autoscaler-values.yaml` with the following content:

```yaml
awsRegion: us-east-1

rbac:
  serviceAccount:
    name: cluster-autoscaler
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::12345678910:role/tf-your-cluster-name-cluster-autoscaler"

autoDiscovery:
  clusterName: your-cluster-name

image:
  repository: us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler
  tag: v1.19.1
```

Notice the image tag is `v1.19.1` - this tag goes with clusters running Kubernetes 1.19.
If you are running 1.20, 1.21, etc, you will need to find the image tag that matches your cluster version.
To see available tags, visit [this GCR registry](https://console.cloud.google.com/gcr/images/k8s-artifacts-prod/US/autoscaling/cluster-autoscaler?gcrImageListsize=30)

Next, you'll need to fetch the chart, apply your values using `helm template` and then apply the resulting Kubernetes object to your cluster.

```
helm fetch stable/cluster-autoscaler --untar
```

And then

```
helm template --name cluster-autoscaler --namespace kube-system ./cluster-autoscaler -f ./cluster-autoscaler-values.yaml | kubectl apply -n kube-system -f -
```

### Long Term Storage

You can choose to create S3 buckets for [long term storage](https://jenkins-x.io/docs/install-setup/installing/boot/storage/) of Jenkins X build artefacts with `enable_logs_storage`, `enable_reports_storage` and `enable_repository_storage`.

During `terraform apply` the enabledS3 buckets are created, and the _jx_requirements_ output will contain the following section:

```yaml
storage:
  logs:
    enabled: ${enable_logs_storage}
    url: s3://${logs_storage_bucket}
  reports:
    enabled: ${enable_reports_storage}
    url: s3://${reports_storage_bucket}
  repository:
    enabled: ${enable_repository_storage}
    url: s3://${repository_storage_bucket}
```

If you just want to experiment with Jenkins X, you can set the variable _force_destroy_ to true.
This allows you to remove all generated buckets when running terraform destroy.

:warning: **Note**: If you set `force_destroy` to false, and run a `terraform destroy`, it will fail. In that case empty the s3 buckets from the aws s3 console, and re run `terraform destroy`.

### Secrets Management

Vault is the default tool used by Jenkins X for managing secrets.
Part of this module's responsibilities is the creation of all resources required to run the [Vault Operator](https://github.com/banzaicloud/bank-vaults).
These resources are An S3 Bucket, a DynamoDB Table and a KMS Key.

You can also configure an existing Vault instance for use with Jenkins X.
In this case

- provide the Vault URL via the _vault_url_ input variable
- set the `boot_secrets` in `main.tf` to this value:
```bash
boot_secrets = [
    {
      name  = "jxBootJobEnvVarSecrets.EXTERNAL_VAULT"
      value = "true"
      type  = "string"
    },
    {
      name  = "jxBootJobEnvVarSecrets.VAULT_ADDR"
      value = "https://enter-your-vault-url:8200"
      type  = "string"
    }
  ]
```
- follow the Jenkins X documentation around the installation of an [external Vault](https://jenkins-x.io/v3/admin/setup/secrets/vault/#external-vault) instance.

To use AWS Secrets Manager instead of vault, set `use_vault` variable to false, and `use_asm` variable to true. You will also need a role that grants access to AWS Secrets Manager, this will be created for you by setting `create_asm_role` variable to true.

### NGINX

The module can install the nginx chart by setting `create_nginx` flag to `true`.
Example can be found [here](./example/jx3).
You can specify a nginx_values.yaml file or the module will use the default one stored [here](./modules/nginx/nginx_values.yaml).
If you are using terraform to create nginx resources, do not use the chart specified in the versionstream.
Remove the entry in the [`helmfile.yaml`](https://github.com/DexaiRobotics/jx3-eks-vault/blob/master/helmfile.yaml) referencing the nginx chart

```
path: helmfiles/nginx/helmfile.yaml
```

### ExternalDNS

You can enable [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) with the `enable_external_dns` variable. This modifies the generated _jx-requirements.yml_ file to enable External DNS when running `jx boot`.

If `enable_external_dns` is _true_, additional configuration is required.

If you want to use a domain with an already existing Route 53 Hosted Zone, you can provide it through the `apex_domain` variable:

This domain will be configured in the _jx_requirements_ output in the following section:

```yaml
ingress:
  domain: ${domain}
  ignoreLoadBalancer: true
  externalDNS: ${enable_external_dns}
```

If you want to use a subdomain and have this module create and configure a new Hosted Zone with DNS delegation, you can provide the following variables:

`subdomain`: This subdomain is added to the apex domain and configured in the resulting _jx-requirements.yml_ file.

`create_and_configure_subdomain`: This flag instructs the script to create a new `Route53 Hosted Zone` for your subdomain and configure DNS delegation with the apex domain.

By providing these variables, the script creates a new `Route 53` HostedZone that looks like `<subdomain>.<apex_domain>`, then it delegates the resolving of DNS to the apex domain.
This is done by creating a `NS` RecordSet in the apex domain's Hosted Zone with the subdomain's HostedZone nameservers.

This ensures that the newly created HostedZone for the subdomain is instantly resolvable instead of having to wait for DNS propagation.

### cert-manager

You can enable [cert-manager](https://github.com/jetstack/cert-manager) to use TLS for your cluster through LetsEncrypt with the `enable_tls` variable.

[LetsEncrypt](https://letsencrypt.org/) has two environments, `staging` and `production`.

If you use staging, you will receive self-signed certificates, but you are not rate-limited, if you use the `production` environment, you receive certificates signed by LetsEncrypt, but you can be rate limited.

You can choose to use the `production` environment with the `production_letsencrypt` variable:

You need to provide a valid email to register your domain in LetsEncrypt with `tls_email`.

### Customer's CA certificates

Customer has got signed certificates from CA and want to use it instead of LetsEncrypt certificates. Terraform creates k8s `tls-ingress-certificates-ca` secret with `tls_key` and `tls_cert` in `default` namespace.
User should define:

```
enable_external_dns = true
apex_domain         = "office.com"
subdomain           = "subdomain"
enable_tls          = true
tls_email           = "custome@office.com"

// Signed Certificate must match the domain: *.subdomain.office.com
tls_cert            = "/opt/CA/cert.crt"
tls_key             = "LS0tLS1C....BLRVktLS0tLQo="
```

### Velero Backups

This module can set up the resources required for running backups with Velero on your cluster by setting the flag `enable_backup` to `true`.

#### Enabling backups on pre-existing clusters

If your cluster is pre-existing and already contains a namespace named `velero`, then enabling backups will initially fail with an error that you are trying to create a namespace which already exists.

```
Error: namespaces "velero" already exists
```

If you get this error, consider it a warning - you may then adjust accordingly by importing that namespace to be managed by Terraform, deleting the previously existing ns if it wasn't actually in use, or setting `enable_backup` back to `false` to continue managing Velero in the previous manner.

The recommended way is to import the namespace and then run another Terraform plan and apply:

```
terraform import module.eks-jx.module.backup.kubernetes_namespace.velero_namespace velero
```
### Production cluster considerations

The configuration, as seen in [Cluster provisioning](#cluster-provisioning), is not suited for creating and maintaining a production Jenkins X cluster.
The following is a list of considerations for a production use case.

- Specify the version attribute of the module, for example:

  ```terraform
  module "eks-jx" {
    source  = "jenkins-x/eks-jx/aws"
    version = "1.0.0"
    # insert your configuration
  }

  output "jx_requirements" {
    value = module.eks-jx.jx_requirements
  }
  ```

  Specifying the version ensures that you are using a fixed version and that version upgrades cannot occur unintended.

- Keep the Terraform configuration under version control by creating a dedicated repository for your cluster configuration or by adding it to an already existing infrastructure repository.

- Setup a Terraform backend to securely store and share the state of your cluster. For more information refer to [Configuring a Terraform backend](#configuring-a-terraform-backend).

- Disable public API for the EKS cluster.
  If that is not not possible, restrict access to it by specifying the cidr blocks which can access it.

### Configuring a Terraform backend

A "[backend](https://www.terraform.io/docs/backends/index.html)" in Terraform determines how state is loaded and how an operation such as _apply_ is executed.
By default, Terraform uses the _local_ backend, which keeps the state of the created resources on the local file system.
This is problematic since sensitive information will be stored on disk and it is not possible to share state across a team.
When working with AWS a good choice for your Terraform backend is the [_s3_ backend](https://www.terraform.io/docs/backends/types/s3.html) which stores the Terraform state in an AWS S3 bucket.
The [examples](./examples) directory of this repository contains configuration examples for using the _s3_ backed.

To use the _s3_ backend, you will need to create the bucket upfront.
You need the S3 bucket as well as a Dynamo table for state locks.
You can use [terraform-aws-tfstate-backend](https://github.com/cloudposse/terraform-aws-tfstate-backend) to create these required resources.

### Using Spot Instances

You can save up to 90% of cost when you use Spot Instances. You just need to make sure your applications are resilient. You can set the ceiling `spot_price` of what you want to pay then set `enable_spot_instances` to `true`.

:warning: **Note**: If the price of the instance reaches this point it will be terminated.

### Worker Group Launch Templates

Worker Groups, the default worker node groups for this module, are based on an older AWS tool called "Launch Configurations" which have some limitations around Spot instances and delegating a percentage of a pool of workers to on-demand or spot instances, as well as issues when autoscaling is enabled.

The issue with autoscaling with the default worker group is that it is prone to autoscaling using Nodes from only a single AZ.
AWS has a "AZRebalance" job that can run to help with this, but it is aggressive in removing nodes.

All of these issues can be resolved by using Worker Group Launch Templates instead, configured with a template for each Availability Zone.
Using an ASG for each AZ bypasses the autoscaling issues in AWS.
Furthermore, we are also able to specify several types of machines that are suitable for spot instances rather than just one.
Using only one often results in Spot instances not being able to be provisioned, and this greatly reduces the occurence of this happening, as well as allowing for lower spot prices.

#### Enabling Worker Group Launch Templates

To use the Worker Group Launch Template, set the variable `enable_worker_groups_launch_template` to `true`, and define an array of instance types allowed.

When using autoscaling with Launch Templates per AZ, the min and max number of nodes is per zone.
These values can be adjusted by using the variables `lt_desired_nodes_per_subnet`, `lt_min_nodes_per_subnet`, and `lt_max_nodes_per_subnet`

```terraform
module "eks-jx" {
  source  = "jenkins-x/eks-jx/aws"
  enable_worker_groups_launch_template = true
  allowed_spot_instance_types          = ["m5.large", "m5a.large", "m5d.large", "m5ad.large", "t3.large", "t3a.large"]
  lt_desired_nodes_per_subnet          = 2
  lt_min_nodes_per_subnet              = 2
  lt_max_nodes_per_subnet              = 3
}
```

#### Transitioning from Worker Groups to Worker Groups Launch Templates

In order to prevent any interruption to service, you'll first want to enable Worker Group Launch Templates.

Once you've verified that you are able to see the new Nodes created by the Launch Templates by running `kubectl get nodes`, then you can remove the older Worker Group.

To remove the older worker group, it's recommended to first scale down to zero nodes, one at a time, by adjusting the min/max node capacity.
Once you've scaled down to zero nodes for the original worker group, and your workloads have been scheduled on nodes created by the launch templates you can set `enable_worker_group` to `false`.

module "eks-jx" {
source = "jenkins-x/eks-jx/aws"
enable_worker_group = false
enable_worker_groups_launch_template = true
allowed_spot_instance_types = ["m5.large", "m5a.large", "m5d.large", "m5ad.large", "t3.large", "t3a.large"]
lt_desired_nodes_per_subnet = 2
lt_min_nodes_per_subnet = 2
lt_max_nodes_per_subnet = 3
}

### EKS node groups

This module provisions self-managed worker nodes by default.

If you want AWS to manage the provisioning and lifecycle of worker nodes for EKS, you can opt for [managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html).

They have the added benefit of running the latest Amazon EKS-optimized AMIs and gracefully drain nodes before termination to ensure that your applications stay available.

In order to provision EKS node groups create a _main.tf_ with the following content:

```terraform
module "eks-jx" {
  source  = "jenkins-x/eks-jx/aws"
  enable_worker_group = false
}

output "jx_requirements" {
  value = module.eks-jx.jx_requirements
}

output "vault_user_id" {
  value       = module.eks-jx.vault_user_id
  description = "The Vault IAM user id"
}

output "vault_user_secret" {
  value       = module.eks-jx.vault_user_secret
  description = "The Vault IAM user secret"
}
```

**Note**: EKS node groups now support using [spot instances](https://aws.amazon.com/blogs/containers/amazon-eks-now-supports-provisioning-and-managing-ec2-spot-instances-in-managed-node-groups/) and [launch templates](https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html) (will be set accordingly with the use of the `enable_spot_instances` variable)

#### Custom EKS node groups

A single node group will be created by default when using EKS node groups. Supply values for the `node_groups_managed` variable to override this behaviour:

```terraform
module "eks-jx" {
  source  = "jenkins-x/eks-jx/aws"
  enable_worker_group = false
  node_groups_managed = {
    node-group-name = {
      ami_type                = "AL2_x86_64"
      disk_size               = 50
      desired_capacity        = 3
      max_capacity            = 5
      min_capacity            = 3
      instance_types          = [ "m5.large" ]
      launce_template_id      = null
      launch_template_version = null

      k8s_labels = {
        purpose = "application"
      }
    },
    second-node-group-name = {
      # ...
    },
    # ...
  }
}
```

One can use launch templates with node groups by specifying the template id and version in the parameters.

```terraform
resource "aws_launch_template" "foo" {
  name = "foo"
  # ...
}

module "eks-jx" {
  source  = "jenkins-x/eks-jx/aws"
  enable_worker_group = false
  node_groups_managed = {
    node-group-name = {
      ami_type                = "AL2_x86_64"
      disk_size               = 50
      desired_capacity        = 3
      max_capacity            = 5
      min_capacity            = 3
      instance_types          = [ "m5.large" ]
      launce_template_id      = aws_launch_template.foo.id
      launch_template_version = aws_launch_template.foo.latest_version

      k8s_labels = {
        purpose = "application"
      }
    },
    second-node-group-name = {
      # ...
    },
    # ...
  }
}
```

:warning: **Note**: EKS node groups are supported in kubernetes v1.14+ and platform version eks.3

### AWS Auth

When running EKS, authentication for the cluster is controlled by a `configmap` called `aws-auth`. By default, that should look something like this:

```
apiVersion: v1
data:
  mapAccounts: |
    []
  mapRoles: |
    - "groups":
      - "system:bootstrappers"
      - "system:nodes"
      "rolearn": "arn:aws:iam::777777777777:role/project-eks-12345"
      "username": "system:node:{{EC2PrivateDNSName}}"
  mapUsers: |
    []
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
```

When using this Terraform module, this AWS Auth configmap is generated for you via the EKS module that is used internally. Additional users, roles, and accounts may be mapped into this config map by providing the variables `map_users`, `map_roles` or `map_accounts` respectively.

#### `map_users`

To add an additional AWS IAM user named "patrick", you can create an `aws_iam_user` resource, and then use the `map_users` variable to allow Patrick to access EKS:

```
resource "aws_iam_user" "patrick" {
  name = "patrick"
}

module "eks-jx" {
  source  = "jenkins-x/eks-jx/aws"
  map_users = [
    {
      userarn  = aws_iam_user.patrick.arn
      username = aws_iam_user.patrick.name
      groups   = ["system:masters"]
    }
  ]
}
```

#### `map_roles`

To map additional roles to the AWS Auth ConfigMap, use `map_roles`:

```terraform
module "eks-jx" {
  source  = "jenkins-x/eks-jx/aws"
  map_roles = [
    {
      rolearn  = "arn:aws:iam::66666666666:role/role1"
      username = "role1"
      groups   = ["system:masters"]
    },
  ]
}
```

#### `map_accounts`

To map additional accounts to the AWS Auth ConfigMap, use `map_accounts`:

```terraform
module "eks-jx" {
  source  = "jenkins-x/eks-jx/aws"
  map_accounts = [
    "777777777777",
    "888888888888",
  ]
}
```

### Using SSH Key Pair

Import a key pair or use an existing one and take note of the name.
Set `key_name` and set `enable_key_name` to `true`.

### Using different EBS Volume type and size

Set `volume_type` to either `standard`, `gp2` or `io1` and `volume_size` to the desired size in GB. If chosing `io1` set desired `iops`.

#### Resizing a disk on existing nodes

The existing nodes needs to be terminated and replaced with new ones if disk is needed to be resized.
You need to execute the following command before `terraform apply` in order to replace the Auto Scaling Launch Configuration.

`terraform taint module.eks-jx.module.cluster.module.eks.aws_launch_configuration.workers[0]`

### Support for JX3

Creation of namespaces and service accounts using terraform is no longer required for JX3.
To keep compatibility with JX2, a flag `is_jx2` was introduced, in [v1.6.0](https://github.com/jenkins-x/terraform-aws-eks-jx/releases/tag/v1.6.0).

### Existing VPC

If you want to create the cluster in an existing VPC you can specify `create_vpc` to false and
specify where to create the clsuter with `vpc_id` and `subnets`.

### Existing EKS cluster

It is very common to have another module used to create EKS clusters for all your AWS accounts, in that case, you can
set `create_eks` and `create_vpc` to false and `cluster_name` to the id/name of the EKS cluster where jx components
need to be installed in.
This will prevent creating a new vpc and eks cluster for jx.
There are also flags to control the creation of IAM roles.
See [this](./examples/existing-cluster) for a complete example.

### Examples

You can find examples for different configurations in the [examples folder](./examples).

Each example generates a valid _jx-requirements.yml_ file that can be used to boot a Jenkins X cluster.

### Module configuration

<!-- BEGIN_TF_DOCS # Autogenerated do not edit! -->

#### Providers

| Name                                                      | Version |
| --------------------------------------------------------- | ------- |
| <a name="provider_aws"></a> [aws](#provider_aws)          | 3.64.2  |
| <a name="provider_random"></a> [random](#provider_random) | 3.1.0   |

#### Modules

| Name                                                     | Source            | Version |
| -------------------------------------------------------- | ----------------- | ------- |
| <a name="module_backup"></a> [backup](#module_backup)    | ./modules/backup  | n/a     |
| <a name="module_cluster"></a> [cluster](#module_cluster) | ./modules/cluster | n/a     |
| <a name="module_dns"></a> [dns](#module_dns)             | ./modules/dns     | n/a     |
| <a name="module_health"></a> [health](#module_health)    | ./modules/health  | n/a     |
| <a name="module_nginx"></a> [nginx](#module_nginx)       | ./modules/nginx   | n/a     |
| <a name="module_vault"></a> [vault](#module_vault)       | ./modules/vault   | n/a     |

#### Requirements

| Name                                                                        | Version             |
| --------------------------------------------------------------------------- | ------------------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform)    | >= 0.12.17, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement_aws)                      | >= 2.53.0, < 4.0    |
| <a name="requirement_helm"></a> [helm](#requirement_helm)                   | ~> 2.0              |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement_kubernetes) | ~> 2.0              |
| <a name="requirement_local"></a> [local](#requirement_local)                | ~> 2.0              |
| <a name="requirement_null"></a> [null](#requirement_null)                   | ~> 3.0              |
| <a name="requirement_random"></a> [random](#requirement_random)             | ~> 3.0              |
| <a name="requirement_template"></a> [template](#requirement_template)       | ~> 2.0              |

#### Inputs

| Name                                                                                                                                             | Description                                                                                                                                                                                                                       | Type                                                                                                  | Default                                                                   | Required |
| ------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | :------: |
| <a name="input_additional_tekton_role_policy_arns"></a> [additional_tekton_role_policy_arns](#input_additional_tekton_role_policy_arns)          | Additional Policy ARNs to attach to Tekton IRSA Role                                                                                                                                                                              | `list(string)`                                                                                        | `[]`                                                                      |    no    |
| <a name="input_allowed_spot_instance_types"></a> [allowed_spot_instance_types](#input_allowed_spot_instance_types)                               | Allowed machine types for spot instances (must be same size)                                                                                                                                                                      | `any`                                                                                                 | `[]`                                                                      |    no    |
| <a name="input_apex_domain"></a> [apex_domain](#input_apex_domain)                                                                               | The main domain to either use directly or to configure a subdomain from                                                                                                                                                           | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_boot_secrets"></a> [boot_secrets](#input_boot_secrets)                                                                            | n/a                                                                                                                                                                                                                               | <pre>list(object({<br> name = string<br> value = string<br> type = string<br> }))</pre>               | `[]`                                                                      |    no    |
| <a name="input_cluster_encryption_config"></a> [cluster_encryption_config](#input_cluster_encryption_config)                                     | Configuration block with encryption configuration for the cluster.                                                                                                                                                                | <pre>list(object({<br> provider_key_arn = string<br> resources = list(string)<br> }))</pre>           | `[]`                                                                      |    no    |
| <a name="input_cluster_endpoint_private_access"></a> [cluster_endpoint_private_access](#input_cluster_endpoint_private_access)                   | Indicates whether or not the Amazon EKS private API server endpoint is enabled.                                                                                                                                                   | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_cluster_endpoint_private_access_cidrs"></a> [cluster_endpoint_private_access_cidrs](#input_cluster_endpoint_private_access_cidrs) | List of CIDR blocks which can access the Amazon EKS private API server endpoint, when public access is disabled.                                                                                                                  | `list(string)`                                                                                        | <pre>[<br> "0.0.0.0/0"<br>]</pre>                                         |    no    |
| <a name="input_cluster_endpoint_public_access"></a> [cluster_endpoint_public_access](#input_cluster_endpoint_public_access)                      | Indicates whether or not the Amazon EKS public API server endpoint is enabled.                                                                                                                                                    | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster_endpoint_public_access_cidrs](#input_cluster_endpoint_public_access_cidrs)    | List of CIDR blocks which can access the Amazon EKS public API server endpoint.                                                                                                                                                   | `list(string)`                                                                                        | <pre>[<br> "0.0.0.0/0"<br>]</pre>                                         |    no    |
| <a name="input_cluster_in_private_subnet"></a> [cluster_in_private_subnet](#input_cluster_in_private_subnet)                                     | Flag to enable installation of cluster on private subnets                                                                                                                                                                         | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_cluster_name"></a> [cluster_name](#input_cluster_name)                                                                            | Variable to provide your desired name for the cluster. The script will create a random name if this is empty                                                                                                                      | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_cluster_version"></a> [cluster_version](#input_cluster_version)                                                                   | Kubernetes version to use for the EKS cluster.                                                                                                                                                                                    | `string`                                                                                              | n/a                                                                       |   yes    |
| <a name="input_create_and_configure_subdomain"></a> [create_and_configure_subdomain](#input_create_and_configure_subdomain)                      | Flag to create an NS record set for the subdomain in the apex domain's Hosted Zone                                                                                                                                                | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_create_asm_role"></a> [create_asm_role](#input_create_asm_role)                                                                   | Flag to control AWS Secrets Manager iam roles creation                                                                                                                                                                            | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_create_autoscaler_role"></a> [create_autoscaler_role](#input_create_autoscaler_role)                                              | Flag to control cluster autoscaler iam role creation                                                                                                                                                                              | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_bucketrepo_role"></a> [create_bucketrepo_role](#input_create_bucketrepo_role)                                              | Flag to control bucketrepo role                                                                                                                                                                                                   | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_cm_role"></a> [create_cm_role](#input_create_cm_role)                                                                      | Flag to control cert manager iam role creation                                                                                                                                                                                    | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_cmcainjector_role"></a> [create_cmcainjector_role](#input_create_cmcainjector_role)                                        | Flag to control cert manager ca-injector iam role creation                                                                                                                                                                        | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_ctrlb_role"></a> [create_ctrlb_role](#input_create_ctrlb_role)                                                             | Flag to control controller build iam role creation                                                                                                                                                                                | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_eks"></a> [create_eks](#input_create_eks)                                                                                  | Controls if EKS cluster and associated resources should be created or not. If you have an existing eks cluster for jx, set it to false                                                                                            | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_exdns_role"></a> [create_exdns_role](#input_create_exdns_role)                                                             | Flag to control external dns iam role creation                                                                                                                                                                                    | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_nginx"></a> [create_nginx](#input_create_nginx)                                                                            | Decides whether we want to create nginx resources using terraform or not                                                                                                                                                          | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_create_nginx_namespace"></a> [create_nginx_namespace](#input_create_nginx_namespace)                                              | Boolean to control nginx namespace creation                                                                                                                                                                                       | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_pipeline_vis_role"></a> [create_pipeline_vis_role](#input_create_pipeline_vis_role)                                        | Flag to control pipeline visualizer role                                                                                                                                                                                          | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_ssm_role"></a> [create_ssm_role](#input_create_ssm_role)                                                                   | Flag to control AWS Parameter Store iam roles creation                                                                                                                                                                            | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_create_tekton_role"></a> [create_tekton_role](#input_create_tekton_role)                                                          | Flag to control tekton iam role creation                                                                                                                                                                                          | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_velero_role"></a> [create_velero_role](#input_create_velero_role)                                                          | Flag to control velero iam role creation                                                                                                                                                                                          | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_create_vpc"></a> [create_vpc](#input_create_vpc)                                                                                  | Controls if VPC and related resources should be created. If you have an existing vpc for jx, set it to false                                                                                                                      | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_desired_node_count"></a> [desired_node_count](#input_desired_node_count)                                                          | The number of worker nodes to use for the cluster                                                                                                                                                                                 | `number`                                                                                              | `3`                                                                       |    no    |
| <a name="input_enable_backup"></a> [enable_backup](#input_enable_backup)                                                                         | Whether or not Velero backups should be enabled                                                                                                                                                                                   | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_enable_external_dns"></a> [enable_external_dns](#input_enable_external_dns)                                                       | Flag to enable or disable External DNS in the final `jx-requirements.yml` file                                                                                                                                                    | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_enable_key_name"></a> [enable_key_name](#input_enable_key_name)                                                                   | Flag to enable ssh key pair name                                                                                                                                                                                                  | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_enable_key_rotation"></a> [enable_key_rotation](#input_enable_key_rotation)                                                       | Flag to enable kms key rotation                                                                                                                                                                                                   | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_enable_logs_storage"></a> [enable_logs_storage](#input_enable_logs_storage)                                                       | Flag to enable or disable long term storage for logs                                                                                                                                                                              | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_enable_nat_gateway"></a> [enable_nat_gateway](#input_enable_nat_gateway)                                                          | Should be true if you want to provision NAT Gateways for each of your private networks                                                                                                                                            | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_enable_reports_storage"></a> [enable_reports_storage](#input_enable_reports_storage)                                              | Flag to enable or disable long term storage for reports                                                                                                                                                                           | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_enable_repository_storage"></a> [enable_repository_storage](#input_enable_repository_storage)                                     | Flag to enable or disable the repository bucket storage                                                                                                                                                                           | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_enable_spot_instances"></a> [enable_spot_instances](#input_enable_spot_instances)                                                 | Flag to enable spot instances                                                                                                                                                                                                     | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_enable_tls"></a> [enable_tls](#input_enable_tls)                                                                                  | Flag to enable TLS in the final `jx-requirements.yml` file                                                                                                                                                                        | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_enable_worker_group"></a> [enable_worker_group](#input_enable_worker_group)                                                       | Flag to enable worker group. Setting this to false will provision a node group instead                                                                                                                                            | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_enable_worker_groups_launch_template"></a> [enable_worker_groups_launch_template](#input_enable_worker_groups_launch_template)    | Flag to enable Worker Group Launch Templates                                                                                                                                                                                      | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_encrypt_volume_self"></a> [encrypt_volume_self](#input_encrypt_volume_self)                                                       | Encrypt the ebs and root volume for the self managed worker nodes. This is only valid for the worker group launch template                                                                                                        | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_force_destroy"></a> [force_destroy](#input_force_destroy)                                                                         | Flag to determine whether storage buckets get forcefully destroyed. If set to false, empty the bucket first in the aws s3 console, else terraform destroy will fail with BucketNotEmpty error                                     | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_force_destroy_subdomain"></a> [force_destroy_subdomain](#input_force_destroy_subdomain)                                           | Flag to determine whether subdomain zone get forcefully destroyed. If set to false, empty the sub domain first in the aws Route 53 console, else terraform destroy will fail with HostedZoneNotEmpty error                        | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_ignoreLoadBalancer"></a> [ignoreLoadBalancer](#input_ignoreLoadBalancer)                                                          | Flag to specify if jx boot will ignore loadbalancer DNS to resolve to an IP                                                                                                                                                       | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_install_kuberhealthy"></a> [install_kuberhealthy](#input_install_kuberhealthy)                                                    | Flag to specify if kuberhealthy operator should be installed                                                                                                                                                                      | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_iops"></a> [iops](#input_iops)                                                                                                    | The IOPS value                                                                                                                                                                                                                    | `number`                                                                                              | `0`                                                                       |    no    |
| <a name="input_is_jx2"></a> [is_jx2](#input_is_jx2)                                                                                              | Flag to specify if jx2 related resources need to be created                                                                                                                                                                       | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_jx_bot_token"></a> [jx_bot_token](#input_jx_bot_token)                                                                            | Bot token used to interact with the Jenkins X cluster git repository                                                                                                                                                              | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_jx_bot_username"></a> [jx_bot_username](#input_jx_bot_username)                                                                   | Bot username used to interact with the Jenkins X cluster git repository                                                                                                                                                           | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_jx_git_operator_values"></a> [jx_git_operator_values](#input_jx_git_operator_values)                                              | Extra values for jx-git-operator chart as a list of yaml formated strings                                                                                                                                                         | `list(string)`                                                                                        | `[]`                                                                      |    no    |
| <a name="input_jx_git_url"></a> [jx_git_url](#input_jx_git_url)                                                                                  | URL for the Jenkins X cluster git repository                                                                                                                                                                                      | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_key_name"></a> [key_name](#input_key_name)                                                                                        | The ssh key pair name                                                                                                                                                                                                             | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_local-exec-interpreter"></a> [local-exec-interpreter](#input_local-exec-interpreter)                                              | If provided, this is a list of interpreter arguments used to execute the command                                                                                                                                                  | `list(string)`                                                                                        | <pre>[<br> "/bin/bash",<br> "-c"<br>]</pre>                               |    no    |
| <a name="input_lt_desired_nodes_per_subnet"></a> [lt_desired_nodes_per_subnet](#input_lt_desired_nodes_per_subnet)                               | The number of worker nodes in each Subnet (AZ) if using Launch Templates                                                                                                                                                          | `number`                                                                                              | `1`                                                                       |    no    |
| <a name="input_lt_max_nodes_per_subnet"></a> [lt_max_nodes_per_subnet](#input_lt_max_nodes_per_subnet)                                           | The maximum number of worker nodes in each Subnet (AZ) if using Launch Templates                                                                                                                                                  | `number`                                                                                              | `2`                                                                       |    no    |
| <a name="input_lt_min_nodes_per_subnet"></a> [lt_min_nodes_per_subnet](#input_lt_min_nodes_per_subnet)                                           | The minimum number of worker nodes in each Subnet (AZ) if using Launch Templates                                                                                                                                                  | `number`                                                                                              | `1`                                                                       |    no    |
| <a name="input_manage_apex_domain"></a> [manage_apex_domain](#input_manage_apex_domain)                                                          | Flag to control if apex domain should be managed/updated by this module. Set this to false,if your apex domain is managed in a different AWS account or different provider                                                        | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_manage_subdomain"></a> [manage_subdomain](#input_manage_subdomain)                                                                | Flag to control subdomain creation/management                                                                                                                                                                                     | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_map_accounts"></a> [map_accounts](#input_map_accounts)                                                                            | Additional AWS account numbers to add to the aws-auth configmap.                                                                                                                                                                  | `list(string)`                                                                                        | `[]`                                                                      |    no    |
| <a name="input_map_roles"></a> [map_roles](#input_map_roles)                                                                                     | Additional IAM roles to add to the aws-auth configmap.                                                                                                                                                                            | <pre>list(object({<br> rolearn = string<br> username = string<br> groups = list(string)<br> }))</pre> | `[]`                                                                      |    no    |
| <a name="input_map_users"></a> [map_users](#input_map_users)                                                                                     | Additional IAM users to add to the aws-auth configmap.                                                                                                                                                                            | <pre>list(object({<br> userarn = string<br> username = string<br> groups = list(string)<br> }))</pre> | `[]`                                                                      |    no    |
| <a name="input_max_node_count"></a> [max_node_count](#input_max_node_count)                                                                      | The maximum number of worker nodes to use for the cluster                                                                                                                                                                         | `number`                                                                                              | `5`                                                                       |    no    |
| <a name="input_min_node_count"></a> [min_node_count](#input_min_node_count)                                                                      | The minimum number of worker nodes to use for the cluster                                                                                                                                                                         | `number`                                                                                              | `3`                                                                       |    no    |
| <a name="input_nginx_chart_version"></a> [nginx_chart_version](#input_nginx_chart_version)                                                       | nginx chart version                                                                                                                                                                                                               | `string`                                                                                              | n/a                                                                       |   yes    |
| <a name="input_nginx_namespace"></a> [nginx_namespace](#input_nginx_namespace)                                                                   | Name of the nginx namespace                                                                                                                                                                                                       | `string`                                                                                              | `"nginx"`                                                                 |    no    |
| <a name="input_nginx_release_name"></a> [nginx_release_name](#input_nginx_release_name)                                                          | Name of the nginx release name                                                                                                                                                                                                    | `string`                                                                                              | `"nginx-ingress"`                                                         |    no    |
| <a name="input_nginx_values_file"></a> [nginx_values_file](#input_nginx_values_file)                                                             | Name of the values file which holds the helm chart values                                                                                                                                                                         | `string`                                                                                              | `"nginx_values.yaml"`                                                     |    no    |
| <a name="input_node_group_ami"></a> [node_group_ami](#input_node_group_ami)                                                                      | ami type for the node group worker intances                                                                                                                                                                                       | `string`                                                                                              | `"AL2_x86_64"`                                                            |    no    |
| <a name="input_node_group_disk_size"></a> [node_group_disk_size](#input_node_group_disk_size)                                                    | node group worker disk size                                                                                                                                                                                                       | `string`                                                                                              | `"50"`                                                                    |    no    |
| <a name="input_node_groups_managed"></a> [node_groups_managed](#input_node_groups_managed)                                                       | List of managed node groups to be created and their respective settings                                                                                                                                                           | `any`                                                                                                 | <pre>{<br> "eks-jx-node-group": {}<br>}</pre>                             |    no    |
| <a name="input_node_machine_type"></a> [node_machine_type](#input_node_machine_type)                                                             | The instance type to use for the cluster's worker nodes                                                                                                                                                                           | `string`                                                                                              | `"m5.large"`                                                              |    no    |
| <a name="input_private_subnets"></a> [private_subnets](#input_private_subnets)                                                                   | The private subnet CIDR block to use in the created VPC                                                                                                                                                                           | `list(string)`                                                                                        | <pre>[<br> "10.0.4.0/24",<br> "10.0.5.0/24",<br> "10.0.6.0/24"<br>]</pre> |    no    |
| <a name="input_production_letsencrypt"></a> [production_letsencrypt](#input_production_letsencrypt)                                              | Flag to use the production environment of letsencrypt in the `jx-requirements.yml` file                                                                                                                                           | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_profile"></a> [profile](#input_profile)                                                                                           | The AWS Profile used to provision the EKS Cluster                                                                                                                                                                                 | `string`                                                                                              | `null`                                                                    |    no    |
| <a name="input_public_subnets"></a> [public_subnets](#input_public_subnets)                                                                      | The public subnet CIDR block to use in the created VPC                                                                                                                                                                            | `list(string)`                                                                                        | <pre>[<br> "10.0.1.0/24",<br> "10.0.2.0/24",<br> "10.0.3.0/24"<br>]</pre> |    no    |
| <a name="input_region"></a> [region](#input_region)                                                                                              | The region to create the resources into                                                                                                                                                                                           | `string`                                                                                              | `"us-east-1"`                                                             |    no    |
| <a name="input_registry"></a> [registry](#input_registry)                                                                                        | Registry used to store images                                                                                                                                                                                                     | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_s3_kms_arn"></a> [s3_kms_arn](#input_s3_kms_arn)                                                                                  | ARN of the kms key used for encrypting s3 buckets                                                                                                                                                                                 | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_single_nat_gateway"></a> [single_nat_gateway](#input_single_nat_gateway)                                                          | Should be true if you want to provision a single shared NAT Gateway across all of your private networks                                                                                                                           | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_spot_price"></a> [spot_price](#input_spot_price)                                                                                  | The spot price ceiling for spot instances                                                                                                                                                                                         | `string`                                                                                              | `"0.1"`                                                                   |    no    |
| <a name="input_subdomain"></a> [subdomain](#input_subdomain)                                                                                     | The subdomain to be added to the apex domain. If subdomain is set, it will be appended to the apex domain in `jx-requirements-eks.yml` file                                                                                       | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_subnets"></a> [subnets](#input_subnets)                                                                                           | The subnet ids to create EKS cluster in if create_vpc is false                                                                                                                                                                    | `list(string)`                                                                                        | `[]`                                                                      |    no    |
| <a name="input_tls_cert"></a> [tls_cert](#input_tls_cert)                                                                                        | TLS certificate encrypted with Base64                                                                                                                                                                                             | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_tls_email"></a> [tls_email](#input_tls_email)                                                                                     | The email to register the LetsEncrypt certificate with. Added to the `jx-requirements.yml` file                                                                                                                                   | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_tls_key"></a> [tls_key](#input_tls_key)                                                                                           | TLS key encrypted with Base64                                                                                                                                                                                                     | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_use_asm"></a> [use_asm](#input_use_asm)                                                                                           | Flag to specify if AWS Secrets manager is being used                                                                                                                                                                              | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_use_kms_s3"></a> [use_kms_s3](#input_use_kms_s3)                                                                                  | Flag to determine whether kms should be used for encrypting s3 buckets                                                                                                                                                            | `bool`                                                                                                | `false`                                                                   |    no    |
| <a name="input_use_vault"></a> [use_vault](#input_use_vault)                                                                                     | Flag to control vault resource creation                                                                                                                                                                                           | `bool`                                                                                                | `true`                                                                    |    no    |
| <a name="input_vault_url"></a> [vault_url](#input_vault_url)                                                                                     | URL to an external Vault instance in case Jenkins X does not create its own system Vault                                                                                                                                          | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_vault_user"></a> [vault_user](#input_vault_user)                                                                                  | The AWS IAM Username whose credentials will be used to authenticate the Vault pods against AWS                                                                                                                                    | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_velero_namespace"></a> [velero_namespace](#input_velero_namespace)                                                                | Kubernetes namespace for Velero                                                                                                                                                                                                   | `string`                                                                                              | `"velero"`                                                                |    no    |
| <a name="input_velero_schedule"></a> [velero_schedule](#input_velero_schedule)                                                                   | The Velero backup schedule in cron notation to be set in the Velero Schedule CRD (see [default-backup.yaml](https://github.com/jenkins-x/jenkins-x-boot-config/blob/master/systems/velero-backups/templates/default-backup.yaml)) | `string`                                                                                              | `"0 * * * *"`                                                             |    no    |
| <a name="input_velero_ttl"></a> [velero_ttl](#input_velero_ttl)                                                                                  | The the lifetime of a velero backup to be set in the Velero Schedule CRD (see [default-backup.yaml](https://github.com/jenkins-x/jenkins-x-boot-config/blob/master/systems/velero-backups/templates/default-backup))              | `string`                                                                                              | `"720h0m0s"`                                                              |    no    |
| <a name="input_velero_username"></a> [velero_username](#input_velero_username)                                                                   | The username to be assigned to the Velero IAM user                                                                                                                                                                                | `string`                                                                                              | `"velero"`                                                                |    no    |
| <a name="input_volume_size"></a> [volume_size](#input_volume_size)                                                                               | The volume size in GB                                                                                                                                                                                                             | `number`                                                                                              | `50`                                                                      |    no    |
| <a name="input_volume_type"></a> [volume_type](#input_volume_type)                                                                               | The volume type to use. Can be standard, gp2 or io1                                                                                                                                                                               | `string`                                                                                              | `"gp2"`                                                                   |    no    |
| <a name="input_vpc_cidr_block"></a> [vpc_cidr_block](#input_vpc_cidr_block)                                                                      | The vpc CIDR block                                                                                                                                                                                                                | `string`                                                                                              | `"10.0.0.0/16"`                                                           |    no    |
| <a name="input_vpc_id"></a> [vpc_id](#input_vpc_id)                                                                                              | The VPC to create EKS cluster in if create_vpc is false                                                                                                                                                                           | `string`                                                                                              | `""`                                                                      |    no    |
| <a name="input_vpc_name"></a> [vpc_name](#input_vpc_name)                                                                                        | The name of the VPC to be created for the cluster                                                                                                                                                                                 | `string`                                                                                              | `"tf-vpc-eks"`                                                            |    no    |

#### Outputs

| Name                                                                                                                 | Description                                                                                                                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| <a name="output_backup_bucket_url"></a> [backup_bucket_url](#output_backup_bucket_url)                               | The bucket where backups from velero will be stored                                                                                                                                                         |
| <a name="output_cert_manager_iam_role"></a> [cert_manager_iam_role](#output_cert_manager_iam_role)                   | The IAM Role that the Cert Manager pod will assume to authenticate                                                                                                                                          |
| <a name="output_cluster_asm_iam_role"></a> [cluster_asm_iam_role](#output_cluster_asm_iam_role)                      | The IAM Role that the External Secrets pod will assume to authenticate (Secrets Manager)                                                                                                                    |
| <a name="output_cluster_autoscaler_iam_role"></a> [cluster_autoscaler_iam_role](#output_cluster_autoscaler_iam_role) | The IAM Role that the Jenkins X UI pod will assume to authenticate                                                                                                                                          |
| <a name="output_cluster_name"></a> [cluster_name](#output_cluster_name)                                              | The name of the created cluster                                                                                                                                                                             |
| <a name="output_cluster_oidc_issuer_url"></a> [cluster_oidc_issuer_url](#output_cluster_oidc_issuer_url)             | The Cluster OIDC Issuer URL                                                                                                                                                                                 |
| <a name="output_cluster_ssm_iam_role"></a> [cluster_ssm_iam_role](#output_cluster_ssm_iam_role)                      | The IAM Role that the External Secrets pod will assume to authenticate (Parameter Store)                                                                                                                    |
| <a name="output_cm_cainjector_iam_role"></a> [cm_cainjector_iam_role](#output_cm_cainjector_iam_role)                | The IAM Role that the CM CA Injector pod will assume to authenticate                                                                                                                                        |
| <a name="output_connect"></a> [connect](#output_connect)                                                             | "The cluster connection string to use once Terraform apply finishes,<br>this command is already executed as part of the apply, you may have to provide the region and<br>profile as environment variables " |
| <a name="output_controllerbuild_iam_role"></a> [controllerbuild_iam_role](#output_controllerbuild_iam_role)          | The IAM Role that the ControllerBuild pod will assume to authenticate                                                                                                                                       |
| <a name="output_eks_module"></a> [eks_module](#output_eks_module)                                                    | The output of the terraform-aws-modules/eks/aws module for use in terraform                                                                                                                                 |
| <a name="output_external_dns_iam_role"></a> [external_dns_iam_role](#output_external_dns_iam_role)                   | The IAM Role that the External DNS pod will assume to authenticate                                                                                                                                          |
| <a name="output_jx_requirements"></a> [jx_requirements](#output_jx_requirements)                                     | The jx-requirements rendered output                                                                                                                                                                         |
| <a name="output_lts_logs_bucket"></a> [lts_logs_bucket](#output_lts_logs_bucket)                                     | The bucket where logs from builds will be stored                                                                                                                                                            |
| <a name="output_lts_reports_bucket"></a> [lts_reports_bucket](#output_lts_reports_bucket)                            | The bucket where test reports will be stored                                                                                                                                                                |
| <a name="output_lts_repository_bucket"></a> [lts_repository_bucket](#output_lts_repository_bucket)                   | The bucket that will serve as artifacts repository                                                                                                                                                          |
| <a name="output_pipeline_viz_iam_role"></a> [pipeline_viz_iam_role](#output_pipeline_viz_iam_role)                   | The IAM Role that the pipeline visualizer pod will assume to authenticate                                                                                                                                   |
| <a name="output_subdomain_nameservers"></a> [subdomain_nameservers](#output_subdomain_nameservers)                   | ---------------------------------------------------------------------------- DNS ----------------------------------------------------------------------------                                               |
| <a name="output_tekton_bot_iam_role"></a> [tekton_bot_iam_role](#output_tekton_bot_iam_role)                         | The IAM Role that the build pods will assume to authenticate                                                                                                                                                |
| <a name="output_vault_dynamodb_table"></a> [vault_dynamodb_table](#output_vault_dynamodb_table)                      | The Vault DynamoDB table                                                                                                                                                                                    |
| <a name="output_vault_kms_unseal"></a> [vault_kms_unseal](#output_vault_kms_unseal)                                  | The Vault KMS Key for encryption                                                                                                                                                                            |
| <a name="output_vault_unseal_bucket"></a> [vault_unseal_bucket](#output_vault_unseal_bucket)                         | The Vault storage bucket                                                                                                                                                                                    |
| <a name="output_vault_user_id"></a> [vault_user_id](#output_vault_user_id)                                           | The Vault IAM user id                                                                                                                                                                                       |
| <a name="output_vault_user_secret"></a> [vault_user_secret](#output_vault_user_secret)                               | The Vault IAM user secret                                                                                                                                                                                   |
| <a name="output_vpc_id"></a> [vpc_id](#output_vpc_id)                                                                | The ID of the VPC                                                                                                                                                                                           |

<!-- BEGIN_TF_DOCS -->

## FAQ: Frequently Asked Questions

### IAM Roles for Service Accounts

This module sets up a series of IAM Policies and Roles. These roles will be annotated into a few Kubernetes Service accounts.
This allows us to make use of [IAM Roles for Sercive Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) to set fine-grained permissions on a pod per pod basis.
There is no way to provide your own roles or define other Service Accounts by variables, but you can always modify the `modules/cluster/irsa.tf` Terraform file.

## Development

### Releasing

At the moment, there is no release pipeline defined in [jenkins-x.yml](./jenkins-x.yml).
A Terraform release does not require building an artifact; only a tag needs to be created and pushed.
To make this task easier and there is a helper script `release.sh` which simplifies this process and creates the changelog as well:

```sh
./scripts/release.sh
```

This can be executed on demand whenever a release is required.
For the script to work, the environment variable _$GH_TOKEN_ must be exported and reference a valid GitHub API token.

## How can I contribute

Contributions are very welcome! Check out the [Contribution Guidelines](./CONTRIBUTING.md) for instructions.
