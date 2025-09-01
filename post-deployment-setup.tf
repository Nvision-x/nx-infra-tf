# Wait for bastion to be ready and verify connectivity
resource "null_resource" "bastion_ready_check" {
  count = var.enable_bastion ? 1 : 0
  
  depends_on = [
    aws_instance.bastion_ec2[0],
    aws_eks_access_entry.bastion_access[0],
    aws_eks_access_policy_association.bastion_access[0]
  ]

  triggers = {
    bastion_instance_id = aws_instance.bastion_ec2[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for bastion host to be ready..."
      for i in {1..30}; do
        nc -zv ${aws_instance.bastion_ec2[0].public_ip} 22 2>/dev/null && break || {
          echo "Attempt $i: Bastion not ready, waiting 10 seconds..."
          sleep 10
        }
      done
      echo "Bastion host is ready for connections"
    EOT
  }
}

# Register snapshot repository via bastion host
resource "null_resource" "register_snapshot_repository" {
  count = var.enable_opensearch && var.enable_bastion ? 1 : 0
  
  depends_on = [
    module.opensearch[0],
    aws_instance.bastion_ec2[0],
    aws_eks_access_entry.bastion_access[0],
    aws_eks_access_policy_association.bastion_access[0],
    null_resource.bastion_ready_check[0]
  ]

  triggers = {
    opensearch_endpoint = module.opensearch[0].domain_endpoint
    snapshot_role_arn   = var.snapshot_role_arn
    bastion_instance_id = aws_instance.bastion_ec2[0].id
  }

  connection {
    type        = "ssh"
    user        = var.bastion_user_name
    private_key = var.bastion_existing_pem != "" ? file(var.bastion_existing_pem) : tls_private_key.bastion_ec2_key[0].private_key_pem
    host        = aws_instance.bastion_ec2[0].public_ip
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "# Wait for cloud-init to complete",
      "cloud-init status --wait || true",
      "sleep 30",
      "# Install required tools with retries",
      "if ! command -v kubectl &> /dev/null; then",
      "  echo 'Installing kubectl...'",
      "  for i in {1..3}; do",
      "    curl -sLO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && break || sleep 10",
      "  done",
      "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl",
      "fi",
      "if ! command -v helm &> /dev/null; then",
      "  echo 'Installing Helm...'",
      "  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash",
      "fi",
      "echo 'Installing Python packages...'",
      "sudo yum install -y python3 python3-pip &>/dev/null || true",
      "pip3 install --user awscurl &>/dev/null || pip3 install --user --upgrade awscurl",
      "echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc",
      "source ~/.bashrc",
      "# Configure kubectl access to EKS cluster with retries",
      "echo 'Configuring kubectl for EKS cluster...'",
      "for i in {1..5}; do",
      "  aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} && break || {",
      "    echo \"Attempt $i failed. Waiting 30 seconds before retry...\"",
      "    sleep 30",
      "  }",
      "done",
      "echo 'Testing kubectl access...'",
      "for i in {1..3}; do",
      "  kubectl get nodes &>/dev/null && { echo 'kubectl configured successfully'; break; } || {",
      "    echo \"kubectl test attempt $i failed, retrying...\"",
      "    sleep 10",
      "  }",
      "done",
      "",
      "# Create and run registration script",
      "cat > /tmp/register_snapshot.sh << 'SCRIPT_EOF'",
      "#!/bin/bash",
      "set -e",
      "export PATH=$PATH:$HOME/.local/bin",
      "",
      "# Ensure awscurl is available",
      "if ! command -v awscurl &> /dev/null; then",
      "  echo 'awscurl not found in PATH, attempting to install...'",
      "  pip3 install --user awscurl",
      "  export PATH=$PATH:$HOME/.local/bin",
      "fi",
      "",
      "# Wait for OpenSearch domain to be ready",
      "echo 'Waiting for OpenSearch domain to be ready...'",
      "for i in {1..20}; do",
      "  curl -sk \"https://${module.opensearch[0].domain_endpoint}/_cluster/health\" -u \"${var.master_user_name}:${jsondecode(data.aws_secretsmanager_secret_version.opensearch[0].secret_string).password}\" && break || {",
      "    echo \"Attempt $i: OpenSearch not ready yet, waiting 30 seconds...\"",
      "    sleep 30",
      "  }",
      "done",
      "",
      "OS_ENDPOINT='${module.opensearch[0].domain_endpoint}'",
      "OS_USER='${var.master_user_name}'",
      "OS_PASS='${jsondecode(data.aws_secretsmanager_secret_version.opensearch[0].secret_string).password}'",
      "S3_BUCKET='${aws_s3_bucket.nvisionx_buckets["nvisionx-os-backup"].id}'",
      "SNAPSHOT_ROLE_ARN='${var.snapshot_role_arn}'",
      "BASTION_ROLE_ARN='${var.bastion_eks_admin_role_arn}'",
      "REGION='${var.region}'",
      "",
      "# Map roles to manage_snapshots",
      "curl -s -X PUT \"https://$OS_ENDPOINT/_plugins/_security/api/rolesmapping/manage_snapshots\" \\",
      "  -u \"$OS_USER:$OS_PASS\" \\",
      "  -H 'Content-Type: application/json' \\",
      "  -d \"{\\\"backend_roles\\\": [\\\"$BASTION_ROLE_ARN\\\", \\\"$SNAPSHOT_ROLE_ARN\\\"], \\\"hosts\\\": [], \\\"users\\\": []}\" -k &>/dev/null",
      "",
      "# Create repository config",
      "cat > /tmp/repo.json << EOF",
      "{\\\"type\\\": \\\"s3\\\", \\\"settings\\\": {\\\"bucket\\\": \\\"$S3_BUCKET\\\", \\\"region\\\": \\\"$REGION\\\", \\\"role_arn\\\": \\\"$SNAPSHOT_ROLE_ARN\\\"}}",
      "EOF",
      "",
      "# Register repository with retries",
      "echo 'Registering snapshot repository...'",
      "for i in {1..3}; do",
      "  RESPONSE=$(awscurl --service es --region $REGION -XPUT -H 'Content-Type: application/json' --data @/tmp/repo.json \"https://$OS_ENDPOINT/_snapshot/${var.snapshot_repository_name}\" 2>&1)",
      "  if echo \"$RESPONSE\" | grep -q '\\\"acknowledged\\\":true'; then",
      "    echo 'Snapshot repository registered successfully'",
      "    break",
      "  else",
      "    echo \"Attempt $i failed: $RESPONSE\"",
      "    if [ $i -lt 3 ]; then",
      "      echo 'Retrying in 30 seconds...'",
      "      sleep 30",
      "    else",
      "      echo 'Failed to register snapshot repository after 3 attempts'",
      "      exit 1",
      "    fi",
      "  fi",
      "done",
      "rm -f /tmp/repo.json",
      "SCRIPT_EOF",
      "",
      "chmod +x /tmp/register_snapshot.sh",
      "/tmp/register_snapshot.sh",
      "rm -f /tmp/register_snapshot.sh"
    ]
  }
}

output "bastion_kubectl_setup" {
  description = "Kubectl configuration status for bastion host"
  value = var.enable_bastion ? (<<-EOT
    The bastion host has been configured with:
    - AWS CLI v2
    - kubectl (configured for EKS cluster: ${module.eks.cluster_name})
    - Helm 3
    - awscurl (for OpenSearch API calls)
    
    The kubeconfig has been automatically configured to access the EKS cluster.
    You can SSH to the bastion and immediately use kubectl commands.
EOT
  ) : null
}

# Output snapshot repository commands for manual execution
output "opensearch_snapshot_commands" {
  description = "Commands to manage OpenSearch snapshots (run from bastion host)"
  value = var.enable_opensearch ? (<<-EOT
    # SSH to bastion host:
    ssh -i ${var.bastion_existing_pem != "" ? var.bastion_existing_pem : "<RETRIEVE_PRIVATE_KEY_FROM_SECRETS_MANAGER>"} ${var.bastion_user_name}@${var.enable_bastion ? aws_instance.bastion_ec2[0].public_ip : "<BASTION_IP>"}
    
    # Install awscurl if not already installed:
    pip3 install awscurl
    
    # ========== SNAPSHOT OPERATIONS ==========
    
    # Method 1: Using AWS SigV4 authentication (recommended for IAM-based access):
    # Create a snapshot:
    awscurl --service es --region ${var.region} \
      -XPUT "https://${module.opensearch[0].domain_endpoint}/_snapshot/${var.snapshot_repository_name}/snapshot_$(date +%Y%m%d_%H%M%S)?wait_for_completion=false"
    
    # List all snapshots:
    awscurl --service es --region ${var.region} \
      -XGET "https://${module.opensearch[0].domain_endpoint}/_snapshot/${var.snapshot_repository_name}/_all"
    
    # Method 2: Using basic authentication (username/password):
    # Note: Replace <PASSWORD> with your actual OpenSearch password
    
    # Create a snapshot:
    curl -X PUT "https://${module.opensearch[0].domain_endpoint}/_snapshot/${var.snapshot_repository_name}/snapshot_$(date +%Y%m%d_%H%M%S)?wait_for_completion=false" \
      -u "${var.master_user_name}:<PASSWORD>" -k
    
    # List all snapshots:
    curl -X GET "https://${module.opensearch[0].domain_endpoint}/_snapshot/${var.snapshot_repository_name}/_all" \
      -u "${var.master_user_name}:<PASSWORD>" -k | python3 -m json.tool
    
    # Restore a snapshot:
    curl -X POST "https://${module.opensearch[0].domain_endpoint}/_snapshot/${var.snapshot_repository_name}/<SNAPSHOT_NAME>/_restore" \
      -u "${var.master_user_name}:<PASSWORD>" -k
    
    # Check snapshot status:
    curl -X GET "https://${module.opensearch[0].domain_endpoint}/_snapshot/${var.snapshot_repository_name}/<SNAPSHOT_NAME>/_status" \
      -u "${var.master_user_name}:<PASSWORD>" -k | python3 -m json.tool
    
    # Delete a snapshot:
    curl -X DELETE "https://${module.opensearch[0].domain_endpoint}/_snapshot/${var.snapshot_repository_name}/<SNAPSHOT_NAME>" \
      -u "${var.master_user_name}:<PASSWORD>" -k
    
    # Kubectl commands (already configured):
    kubectl get nodes
    kubectl get pods --all-namespaces
    kubectl get services --all-namespaces
    kubectl describe cluster
    
    # Helm commands:
    helm list --all-namespaces
    helm repo list
EOT
  ) : null
}