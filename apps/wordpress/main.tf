data "terraform_remote_state" "infra" {

  backend = "gcs"

  config = {

    bucket = "gke-prod-demo-001-tf-state"

    prefix = "gke/prod"

  }

}

module "wordpress" {

  source = "./modules"

  db_host = data.terraform_remote_state.infra.outputs.cloudsql_private_ip

  db_name = data.terraform_remote_state.infra.outputs.database_name

  db_user = data.terraform_remote_state.infra.outputs.database_user

  db_password = data.terraform_remote_state.infra.outputs.database_password

  domain = "myahad.online"

  #gcp_service_account = data.terraform_remote_state.infra.outputs.node_service_account
  gcp_service_account = data.terraform_remote_state.infra.outputs.wordpress_gsa_email

}
