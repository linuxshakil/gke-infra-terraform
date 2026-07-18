locals {

  wordpress_values = templatefile(
    "${path.module}/values.yaml.tpl",
    {
      db_host = var.db_host
      db_name = var.db_name
      db_user = var.db_user
      domain  = var.domain
    }
  )

}
