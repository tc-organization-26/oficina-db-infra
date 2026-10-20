# Oficina - Banco de Dados Gerenciado

Provisiona Amazon RDS for PostgreSQL com Terraform, armazenamento criptografado, backups, credencial gerenciada pelo Secrets Manager e acesso privado a partir do EKS.

## Execucao

Implante primeiro `oficina-k8s-infra`, pois este projeto lê VPC, sub-redes e Security Group do Parameter Store.

Configure no GitHub `AWS_ROLE_ARN`, `AWS_REGION` e `TF_STATE_BUCKET`. Pull requests executam validação e plano; pushes em `homologacao`, `main` ou `master` aplicam automaticamente.

```text
EKS -> Security Group -> RDS PostgreSQL privado -> Secrets Manager
```
