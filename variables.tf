variable "cluster_name" {
  type = string
  default = "Cilium-Istio-EKS-cluster-5"
}

variable "aws_region" {
    type = string
    default = "us-west-1"
}

variable "istio-namespace" {
    type = string
    default = "istio-enabled"
}

variable "subnet_id_1" {
  type = string
  # comment these out to get tf to prompt for subnet IDs
  default = "subnet-0213b611b1e74b753"
}

variable "subnet_id_2" {
  type = string
  # comment these out to get tf to prompt for subnet IDs
  default = "subnet-0beedef5eb2933cda"
}
