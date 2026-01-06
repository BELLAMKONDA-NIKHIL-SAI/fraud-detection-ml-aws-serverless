Fraud Detection Using Machine Learning (Serverless on AWS)

This project implements a production-style fraud detection system using machine learning, serverless microservices, Infrastructure as Code, and CI/CD automation.
The system is designed to be cost-efficient, scalable, and easy to deploy and destroy on demand, making it suitable for AWS Free Tier usage.



Architecture Overview

High-level flow:

Client sends a transaction request
API Gateway routes the request to Lambda microservices
Validation service validates and normalizes the transaction payload
Scoring service loads ML model parameters from S3 and performs inference
Fraud probability and decision are returned


AWS Services Used

AWS Lambda (Python 3.12)
Amazon API Gateway (HTTP API)
Amazon S3 (model artifact storage)
Amazon CloudWatch Logs
IAM (least-privilege roles)
Terraform (Infrastructure as Code)
GitHub Actions (CI/CD)


Microservices

1. Transaction Validation Service

Endpoint:
POST /validate-transaction
Responsibilities
Validate incoming JSON payload
Enforce schema and data constraints
Normalize transaction fields
Reject malformed or invalid requests early


2. Transaction Scoring Service

Endpoint:
POST /score-transaction
Responsibilities
Load ML scoring parameters from S3 at runtime
Perform fraud inference using a trained ML model
Return probability, label, threshold, and model version
Designed for cold-start safety and stateless execution


Machine Learning Pipeline

Model trained locally using Python and scikit-learn
Features engineered from transactional behavior
Trained model parameters exported into JSON format
JSON artifact uploaded to S3 during deployment
Lambda dynamically loads the latest model parameters
This avoids container rebuilds and enables fast model updates.


Infrastructure as Code (Terraform)

All AWS resources are defined using Terraform:
API Gateway routes and integrations
Lambda functions and IAM roles
S3 model artifact bucket
CloudWatch log groups

Resources are created only when needed and can be destroyed safely.



CI/CD Pipeline (GitHub Actions)


Pipelines included:

CI checks (linting)
Manual deploy (Terraform apply + model upload)
Smoke tests (bash-based API validation)
Manual destroy (Terraform destroy)


Key features:

No always-on infrastructure
Bash-driven automation
Safe for AWS Free Tier usage
