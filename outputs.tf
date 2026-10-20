output "database_endpoint" { value = aws_db_instance.postgres.address }
output "database_port" { value = aws_db_instance.postgres.port }
output "database_name" { value = var.database_name }
output "master_secret_arn" {
  value     = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive = true
}

