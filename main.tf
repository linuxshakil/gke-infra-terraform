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


#module "jenkins" {
# source     = "./modules/jenkins"
# project_id = var.project_id
#
# depends_on = [module.gke]
#}

module "jenkins_vm" {
  source     = "./modules/jenkins-vm"
  project_id = var.project_id
  region     = var.region
  vpc_id     = module.network.vpc_id
  subnet_id  = module.network.subnet_id
  ##
  depends_on = [module.network]
}
