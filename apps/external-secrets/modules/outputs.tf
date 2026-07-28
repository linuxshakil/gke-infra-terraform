output "release_name" {

  value = helm_release.external_secrets.name

}

output "namespace" {

  value = helm_release.external_secrets.namespace

}
