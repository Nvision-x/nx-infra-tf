# 🚀 Steps to Deploy

## 1. Clone the Repository

```bash
git clone https://github.com/Nvision-x/nx-infra-tf.git
cd nx-infra-tf/examples/full-deploy
```

## 2. Configure the Backend (Optional but Recommended)

Edit the `provider.tf` file and configure your remote backend (e.g., S3 + DynamoDB).

Example configuration:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "nx-stack/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "your-terraform-lock-table"
    encrypt        = true
  }
}
```

> **Note:** If you prefer to work with a local backend, comment out or remove the backend block.

## 3. Configure `terraform.tfvars`

Create your `terraform.tfvars` by copying the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars` and update it with your environment-specific values (VPC ID, Subnets, Cluster Name, etc.).

## 4. Initialize Terraform

```bash
terraform init
```

This will download all required Terraform providers and modules.

## 5. Apply Only the EKS Cluster First

```bash
terraform apply -target=module.nx
```

This creates the EKS cluster independently before applying addons or optional components.

## 6. Apply the Full Infrastructure

```bash
terraform apply
```

This completes the full Nx stack deployment, including addons, databases, OpenSearch, and optional NFS setup.

# 📋 Important Notes

- If PostgreSQL, OpenSearch, or NFS resources are already created externally, set the following variables to `false` before applying:

```hcl
enable_postgres   = false
enable_opensearch = false
enable_nfs        = false
enable_bastion    = false
```

- After the EKS cluster is created, you can import existing PostgreSQL and OpenSearch resources into Terraform state using `terraform import` commands by enabling enable_postgres and enable_opensearch.
```hcl
terraform import 'module.nx.module.postgresql[0].module.db_instance.aws_db_instance.this[0]' <postgres-instance-name>
terraform import 'module.nx.aws_security_group.db_sg[0]' <postgres-security-group-id>
terraform import 'module.nx.aws_db_subnet_group.private[0]' <postgres-subnet-group-name>

terraform import 'module.nx.module.opensearch[0].aws_opensearch_domain.this[0]' <opensearch-domain-name>
terraform import 'module.nx.aws_security_group.opensearch_sg[0]' <opensearch-security-group-id>
```
- Later, you can enable NFS creation by setting `enable_nfs = true` and reapplying Terraform.

# 🛡️ Prerequisites
- This must be executed on an EC2 instance/Github Runner which has access to the VPC where the resources will be deployed.
- Terraform v1.0 or higher
- AWS CLI 2 installed and configured
- IAM user or role with permissions to create:
  - EKS cluster and node groups
  - RDS PostgreSQL
  - EC2 instances
  - IAM roles and policies
  - Security groups

# 📦 Repository Structure

```plaintext
nx-infra-tf/
├── modules/
├── examples/
│   └── full-deploy/
│       ├── main.tf
│       ├── provider.tf
│       ├── terraform.tfvars.example
│       └── README.md (this file)
├── variables.tf
├── outputs.tf
└── README.md
```
