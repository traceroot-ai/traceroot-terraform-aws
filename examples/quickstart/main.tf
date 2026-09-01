# Minimal example: deploy TraceRoot on AWS.
#
#   terraform init
#   terraform apply -var domain=traceroot.example.com
#
# This example consumes the module from the repository root, so it also serves
# as the module's smoke test in CI.

module "traceroot" {
  source = "../.."

  environment = "example"
  name        = "traceroot-example"
  aws_region  = "us-east-1"
  vpc_cidr    = "10.0.0.0/16"

  domain    = var.domain
  image_tag = var.image_tag
}

variable "domain" {
  description = "Public hostname for the deployment. Empty uses the ALB URL."
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Container image tag to deploy, e.g. sha-1a321eb."
  type        = string
}

output "cluster_name" {
  value = module.traceroot.cluster_name
}
