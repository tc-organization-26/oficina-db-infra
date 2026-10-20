variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "project_name" {
  type    = string
  default = "oficina"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "database_name" {
  type    = string
  default = "oficina_db"
}
variable "master_username" {
  type    = string
  default = "oficina_admin"
}
variable "engine_version" {
  type    = string
  default = "16"
}
variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "allocated_storage" {
  type    = number
  default = 20
}
variable "max_allocated_storage" {
  type    = number
  default = 100
}
variable "multi_az" {
  type    = bool
  default = false
}
variable "backup_retention_period" {
  type    = number
  default = 7
}
variable "deletion_protection" {
  type    = bool
  default = true
}
