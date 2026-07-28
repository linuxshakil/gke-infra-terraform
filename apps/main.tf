############################################################
# Read Infrastructure Remote State
############################################################

data "terraform_remote_state" "infra" {

  backend = "gcs"

  config = {

    bucket = "gke-prod-demo-001-tf-state"

    prefix = "gke/prod"

  }

}

############################################################
# External Secrets Operator
############################################################

module "external_secrets" {

  source = "./modules/external-secrets"

  project_id = var.project_id

}

############################################################
# WordPress
############################################################

module "wordpress" {
  source = "./modules/wordpress"

  ##########################################################
  # Cloud SQL
  ##########################################################

  db_host = data.terraform_remote_state.infra.outputs.cloudsql_private_ip

  db_name = data.terraform_remote_state.infra.outputs.database_name

  db_user = data.terraform_remote_state.infra.outputs.database_user

  db_password = data.terraform_remote_state.infra.outputs.database_password

  ##########################################################
  # Domain
  ##########################################################

  domain = "myahad.online"

  ##########################################################
  # Workload Identity
  ##########################################################

  gcp_service_account = data.terraform_remote_state.infra.outputs.node_service_account

  ##########################################################

  depends_on = [

    module.external_secrets

  ]

}
