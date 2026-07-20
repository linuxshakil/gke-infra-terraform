variable "namespace" {
  type = string
}

variable "deployment_name" {
  type = string
}

variable "min_replicas" {
  default = 2
}

variable "max_replicas" {
  default = 5
}

variable "cpu_utilization" {
  default = 70
}
