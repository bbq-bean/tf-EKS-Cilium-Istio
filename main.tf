terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }  
  }
}

provider "aws" {
  region = var.aws_region
}


resource "aws_iam_role" "eks-iam-role" {
 name = "${var.cluster_name}-tf-iam-role"
 path = "/"
 assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Principal": {
    "Service": "eks.amazonaws.com"
   },
   "Action": "sts:AssumeRole"
  }
 ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
 role    = aws_iam_role.eks-iam-role.name
}
resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly-EKS" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
 role    = aws_iam_role.eks-iam-role.name
}

resource "aws_eks_cluster" "Cilium-Istio-EKS-cluster" {
 name = var.cluster_name
 role_arn = aws_iam_role.eks-iam-role.arn

 vpc_config {
  subnet_ids = [var.subnet_id_1, var.subnet_id_2]
 }

 depends_on = [
  aws_iam_role.eks-iam-role
 ]
}

resource "aws_iam_role" "workernodes" {
  name = "${var.cluster_name}-Role"
 
  assume_role_policy = jsonencode({
   Statement = [{
    Action = "sts:AssumeRole"
    Effect = "Allow"
    Principal = {
     Service = "ec2.amazonaws.com"
    }
   }]
   Version = "2012-10-17"
  })
 }
 
 resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role    = aws_iam_role.workernodes.name
 }
 
 resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role    = aws_iam_role.workernodes.name
 }
 
 resource "aws_iam_role_policy_attachment" "EC2InstanceProfileForImageBuilderECRContainerBuilds" {
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
  role    = aws_iam_role.workernodes.name
 }
 
 resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role    = aws_iam_role.workernodes.name
 }

  resource "aws_eks_node_group" "worker-node-group-1" {
  cluster_name  = var.cluster_name
  node_group_name = "${var.cluster_name}-ng-1"
  node_role_arn  = aws_iam_role.workernodes.arn
  subnet_ids   = [var.subnet_id_1, var.subnet_id_2]
  instance_types = ["t3.medium"]
 
  scaling_config {
   desired_size = 3
   max_size   = 3
   min_size   = 3
  }
 
  depends_on = [
   aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
   aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
   aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
   aws_eks_cluster.Cilium-Istio-EKS-cluster
  ]
 }

#######################
# Cilium with Wireguard
#######################

 provider "helm" {
  kubernetes {
    # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster
    host                   = aws_eks_cluster.Cilium-Istio-EKS-cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.Cilium-Istio-EKS-cluster.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}

resource "helm_release" "cilium" {
  name             = "cilium"
  chart            = "cilium"
  version          = "1.13.2"
  repository       = "https://helm.cilium.io/"
  description      = "Cilium Add-on"
  namespace        = "kube-system"
  create_namespace = false

  values = [
    <<-EOT
      cni:
        chainingMode: aws-cni
      enableIPv4Masquerade: false
      tunnel: disabled
      endpointRoutes:
        enabled: true
      l7Proxy: false
      encryption:
        enabled: true
        type: wireguard
    EOT
  ]

  depends_on = [
    aws_eks_cluster.Cilium-Istio-EKS-cluster
  ]
}

########
# Istio
########

locals {
  istio_charts_url = "https://istio-release.storage.googleapis.com/charts"
}

resource "helm_release" "istio-base" {
  repository       = local.istio_charts_url
  chart            = "base"
  name             = "istio-base"
  namespace        = var.istio-namespace
  version          = "1.18.1"
  create_namespace = true
}

resource "helm_release" "istiod" {
  repository       = local.istio_charts_url
  chart            = "istiod"
  name             = "istiod"
  namespace        = var.istio-namespace
  create_namespace = true
  version          = "1.18.1"
  depends_on       = [helm_release.istio-base]
}

resource "kubernetes_namespace" "istio-ingress" {
  metadata {
    labels = {
      istio-injection = "enabled"
    }

    name = "istio-ingress"
  }
}

resource "helm_release" "istio-ingress" {
  repository = local.istio_charts_url
  chart      = "gateway"
  name       = "istio-ingress"
  namespace  = "istio-ingress"
  version    = "1.18.1"
  depends_on = [helm_release.istiod]
}
