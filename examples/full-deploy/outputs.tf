output "oidc_provider_url" {
  description = "The OpenID Connect identity provider (issuer URL)"
  value       = try(module.nx.oidc_provider_url, null)
}

output "private_key_pem" {
  description = "The private key in PEM format (from module)"
  value       = module.nx.private_key_pem
  sensitive   = true
}

output "bastion_private_key_pem" {
  description = "The bastion private key in PEM format (from module)"
  value       = module.nx.bastion_private_key_pem
  sensitive   = true
}


