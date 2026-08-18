provider "google" {
  project = var.project_id
  region  = var.region
  zone    = local.zone
}
