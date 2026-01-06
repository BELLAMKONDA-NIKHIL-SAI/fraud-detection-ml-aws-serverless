variable "project_name" {
  type        = string
  description = "Project name prefix used for resource naming"
  default     = "fraudml"
}

variable "environment" {
  type        = string
  description = "Environment name used for resource naming"
  default     = "dev"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ca-central-1"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 7
}
