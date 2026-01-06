data "aws_caller_identity" "current" {}

# GitHub OIDC provider (one per AWS account)
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub Actions OIDC thumbprint (stable, widely used)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Update these to match your GitHub org/user + repo name
variable "github_owner" {
  type        = string
  description = "GitHub org/user name (owner of the repo)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
}

resource "aws_iam_role" "github_actions_deploy_role" {
  name = "${local.name_prefix}-role-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        },
        StringLike = {
          # Only allow this repo (any branch). You can lock to main if you want.
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = local.tags
}

# Minimal-ish permissions for this project (Lambda, API GW v2, Logs, S3, IAM role/policy for lambdas)
resource "aws_iam_policy" "github_actions_deploy_policy" {
  name = "${local.name_prefix}-policy-github-actions-deploy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Terraform needs broad read/write for resources it manages.
      {
        Effect = "Allow",
        Action = [
          "lambda:*",
          "apigateway:*",
          "logs:*",
          "s3:*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:List*",
          "iam:Get*",
          "sts:GetCallerIdentity"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_attach" {
  role       = aws_iam_role.github_actions_deploy_role.name
  policy_arn = aws_iam_policy.github_actions_deploy_policy.arn
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_deploy_role.arn
}
