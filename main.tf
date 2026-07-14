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
