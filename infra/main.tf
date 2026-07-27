#############################################################
# Network
#############################################################

module "network" {
  source = "./modules/network"

  project_id   = var.project_id
  cluster_name = var.cluster_name
  region       = var.region
}

#############################################################
# IAM
#############################################################

module "iam" {
  source = "./modules/iam"

  project_id = var.project_id
}

#############################################################
# GKE Cluster
#############################################################


module "gke" {

  source = "./modules/gke"

  project_id   = var.project_id
  region       = var.region
  zone         = var.zone
  cluster_name = var.cluster_name

  vpc_id               = module.network.vpc_id
  subnet_id            = module.network.subnet_id
  machine_type         = var.machine_type
  node_service_account = module.iam.node_sa_email

}




#############################################################
# Cloud SQL
#############################################################

module "cloudsql" {
  source = "./modules/cloudsql"

  project_id = var.project_id
  region     = var.region

  instance_name = var.db_instance_name
  database_name = var.database_name
  database_user = var.database_user

  network_id = module.network.vpc_id

  depends_on = [
    module.network
  ]
}

#############################################################
# Secret Manager
#############################################################

module "secret_manager" {
  source = "./modules/secret-manager"

  project_id = var.project_id

  db_password = module.cloudsql.database_password

  depends_on = [
    module.cloudsql
  ]
}

#############################################################
# Artifact Registry
#############################################################

module "artifact_registry" {
  source = "./modules/artifact-registry"

  project_id = var.project_id
  region     = var.region
}

#############################################################
# Backup
#############################################################

module "backup" {
  source = "./modules/backup"

  providers = {
    google      = google
    google-beta = google-beta
  }

  project_id               = var.project_id
  region                   = var.region
  cloudsql_service_account = module.cloudsql.service_account_email

  depends_on = [
    module.cloudsql
  ]
}
