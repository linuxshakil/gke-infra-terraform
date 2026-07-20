module "network" {
  source = "./modules/network"

  project_id   = var.project_id
  cluster_name = var.cluster_name
  region       = var.region
}


module "gke" {
  source       = "./modules/gke"
  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  vpc_id       = module.network.vpc_id
  subnet_id    = module.network.subnet_id
}
resource "google_artifact_registry_repository" "node_app_repo" {
  location      = var.region
  repository_id = "node-app-repo"
  format        = "DOCKER"
  project       = var.project_id
}


module "cloudsql" {

  source = "./modules/cloudsql"

  project_id = var.project_id

  region = var.region

  instance_name = "wordpress-db"

  database_name = "wordpress"

  database_user = "wordpress"

  network_id = module.network.vpc_id

  depends_on = [

    module.network

  ]

}

module "secret_manager" {

  source = "./modules/secret-manager"

  project_id = var.project_id

  db_password = module.cloudsql.database_password

  depends_on = [

    module.cloudsql

  ]

}


module "wordpress" {

  source = "./modules/wordpress"

  #project_id = var.project_id

  #region = var.region

  db_host = module.cloudsql.private_ip

  db_name = module.cloudsql.database_name

  db_user = module.cloudsql.database_user

  db_password = module.cloudsql.database_password

  domain = "myahad.online"

  #gcp_service_account = "wordpress-gsa@${var.project_id}.iam.gserviceaccount.com"

}

#module "hpa" {

# source = "./modules/hpa"

# namespace = module.wordpress.namespace

# deployment_name = module.wordpress.deployment_name

# depends_on = [
#module.wordpress
    # ]
    #}

#module "jenkins" {
# source     = "./modules/jenkins"
# project_id = var.project_id
#
# depends_on = [module.gke]
#}

#module "jenkins_vm" {
# source     = "./modules/jenkins-vm"
# project_id = var.project_id
# region     = var.region
# vpc_id     = module.network.vpc_id
# subnet_id  = module.network.subnet_id
##
# depends_on = [module.network]
#}
