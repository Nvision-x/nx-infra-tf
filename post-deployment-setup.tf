# The SSH-based post-deployment provisioners (bastion port-22 wait + snapshot
# repository registration over remote-exec) were removed: the bastion no
# longer accepts inbound SSH. Reach it with SSM Session Manager or Tailscale
# and run the registration commands from the opensearch_snapshot_commands
# output. A variable flagged true now only drops those null_resources from state.

output "bastion_kubectl_setup" {
  description = "Kubectl configuration status for bastion host"
  value = var.enable_bastion ? (<<-EOT
    The bastion accepts no inbound SSH. Open a shell with SSM Session Manager:
      aws ssm start-session --region ${var.region} --target ${aws_instance.bastion_ec2[0].id}

    Then configure kubectl for EKS cluster ${module.eks.cluster_name}:
      aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}
EOT
  ) : null
}

# Output snapshot repository commands for manual execution
output "opensearch_snapshot_commands" {
  description = "Commands to manage OpenSearch snapshots (run from bastion host)"
  value = var.enable_opensearch ? (<<-EOT
    # Open a shell on the bastion host (no inbound SSH; SSM Session Manager):
    aws ssm start-session --region ${var.region} --target ${var.enable_bastion ? aws_instance.bastion_ec2[0].id : "<BASTION_INSTANCE_ID>"}

    # One-time snapshot repository registration (previously done by the
    # post-deployment provisioner):
    curl -X PUT "https://${module.opensearch[0].domain_endpoint}/_plugins/_security/api/rolesmapping/manage_snapshots" \
      -u "${var.master_user_name}:<PASSWORD>" -k -H 'Content-Type: application/json' \
      -d '{"backend_roles": ["${var.bastion_eks_admin_role_arn}", "${var.snapshot_role_arn}"], "hosts": [], "users": []}'
    awscurl --service es --region ${var.region} -XPUT -H 'Content-Type: application/json' \
      -d '{"type": "s3", "settings": {"bucket": "${aws_s3_bucket.nvisionx_buckets["os-backup"].id}", "region": "${var.region}", "role_arn": "${var.snapshot_role_arn}"}}' \
      "https://${module.opensearch[0].domain_endpoint}/_snapshot/${var.snapshot_repository_name}"
    
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