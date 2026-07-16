module "network" {
  source       = "./modules/network"
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
