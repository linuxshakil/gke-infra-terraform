output "external_secrets_release" {

  value = module.external_secrets.release_name

}

output "external_secrets_namespace" {

  value = module.external_secrets.namespace

}
