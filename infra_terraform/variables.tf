# Project identifier used as a prefix for naming all AWS resources
variable "project_name" {
  type        = string
  description = "Project name prefix used for resource naming"
  default     = "fraudml"
}

# Deployment environment name
variable "environment" {
  type        = string
  description = "Environment name used for resource naming"
  default     = "dev"
}

# AWS region where all resources will be provisioned
variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ca-central-1"
}

# Number of days to retain CloudWatch logs before automatic deletion
variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 7
}
