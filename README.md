Fraud Detection Using Machine Learning (Serverless on AWS)


This project implements a production-style fraud detection system using machine learning, serverless microservices, Infrastructure as Code, and CI/CD automation. The system is designed to be cost-efficient, scalable, and easy to deploy and destroy on demand, making it suitable for AWS Free Tier usage.


I. Architecture Overview

  a. High-level flow:

    1. Client sends a transaction request
    2. API Gateway routes the request to Lambda microservices
    3. Validation service validates and normalizes the transaction payload
    4. Scoring service loads ML model parameters from S3 and performs inference
    5. Fraud probability and decision are returned

  b. AWS Services Used

    1. AWS Lambda (Python 3.12)
    2. Amazon API Gateway (HTTP API)
    3. Amazon S3 (model artifact storage)
    4. Amazon CloudWatch Logs
    5. IAM (least-privilege roles)
    6. Terraform (Infrastructure as Code)
    7. GitHub Actions (CI/CD)


II. Microservices

  1. Transaction Validation Service

    Endpoint - (POST /validate-transaction)
      Responsibilities:
        Validate incoming JSON payload
        Enforce schema and data constraints
        Normalize transaction fields
        Reject malformed or invalid requests early


  2. Transaction Scoring Service

    Endpoint - (POST /score-transaction)
      Responsibilities:
        Load ML scoring parameters from S3 at runtime
        Perform fraud inference using a trained ML model
        Return probability, label, threshold, and model version
        Designed for cold-start safety and stateless execution


III. Machine Learning Pipeline

  1. Model trained locally using Python and scikit-learn
  2. Features engineered from transactional behavior
  3. Trained model parameters exported into JSON format
  4. JSON artifact uploaded to S3 during deployment
  5. Lambda dynamically loads the latest model parameters
This avoids container rebuilds and enables fast model updates.


IV. Infrastructure as Code (Terraform)

  1. All AWS resources are defined using Terraform:
  2. API Gateway routes and integrations
  3. Lambda functions and IAM roles
  4. S3 model artifact bucket
  5. CloudWatch log groups
Resources are created only when needed and can be destroyed safely.



V. CI/CD Pipeline (GitHub Actions)

  a. Pipeline includes:

    1. CI checks (linting)
    2. Manual deploy (Terraform apply + model upload)
    3. Smoke tests (bash-based API validation)
    4. Manual destroy (Terraform destroy)

  b. Key features:

    1. No always-on infrastructure
    2. Bash-driven automation
    3. Safe for AWS Free Tier usage



