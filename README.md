# Oficina — Banco de Dados Gerenciado

Infraestrutura Terraform responsável pelo banco PostgreSQL gerenciado da plataforma Oficina. Este repositório cria uma instância Amazon RDS privada, sua configuração de rede, backups, criptografia e credencial administrada pelo AWS Secrets Manager.

Ele não contém migrations SQL nem código da aplicação. O schema de negócio é versionado pelo Flyway no repositório `gestao-oficina-tc-1`.

## Links de deploy e documentação

- [Deployments ativos](https://github.com/tc-organization-26/oficina-db-infra/deployments).
- [Pipeline Terraform](https://github.com/tc-organization-26/oficina-db-infra/actions/workflows/terraform.yml).
- Swagger/OpenAPI: não se aplica a este repositório, pois ele não expõe API. Consulte a [documentação da Oficina API](https://github.com/tc-organization-26/gestao-oficina-tc-1#links-de-deploy-e-documentação-da-api).

O RDS não possui link público de acesso: o endpoint é privado por definição e pode ser consultado com `terraform output -raw database_endpoint` ou no Parameter Store. O link acima registra os ambientes efetivamente implantados sem expor credenciais ou conectividade do banco.

## Tecnologias utilizadas

- Terraform e provider AWS;
- Amazon RDS for PostgreSQL;
- Amazon VPC e Security Groups;
- AWS Secrets Manager e Systems Manager Parameter Store;
- Amazon S3 para state remoto;
- GitHub Actions com autenticação OIDC.

## Dockerfile

Não se aplica. O banco é provisionado como serviço gerenciado Amazon RDS; este repositório não constrói nem executa imagens de contêiner.

## Responsabilidades deste repositório

- consumir a VPC, as sub-redes privadas e o Security Group do EKS publicados pelo repositório Kubernetes;
- criar o DB Subnet Group;
- criar um Security Group exclusivo para o PostgreSQL;
- permitir acesso à porta `5432` somente a partir dos nós do EKS;
- criar a instância RDS PostgreSQL sem endpoint público;
- habilitar criptografia de armazenamento;
- habilitar backups e atualização automática de versão minor;
- permitir crescimento automático do armazenamento;
- delegar a senha do usuário master ao AWS Secrets Manager;
- publicar endpoint, porta, database e ARN do secret no Parameter Store.

## Posição na arquitetura

```text
Pods da Oficina API no EKS
  -> Security Group dos nós
     -> Security Group do banco :5432
        -> RDS PostgreSQL em sub-redes privadas
           -> senha gerenciada pelo Secrets Manager
```

O banco não usa Deployment, StatefulSet ou PVC no Kubernetes. O RDS é o banco gerenciado exigido pela arquitetura.

## Dependência obrigatória

Execute primeiro `oficina-k8s-infra`. Este Terraform lê os seguintes parâmetros do AWS Systems Manager Parameter Store:

```text
/oficina/ENV/network/vpc-id
/oficina/ENV/network/private-subnet-ids
/oficina/ENV/eks/node-security-group-id
```

Se esses parâmetros não existirem para o ambiente selecionado, o `terraform plan` falhará antes de criar o banco.

## Recursos criados

| Recurso | Finalidade |
| --- | --- |
| `aws_db_subnet_group` | Posiciona o RDS nas sub-redes privadas |
| `aws_security_group` | Isola a comunicação com o PostgreSQL |
| `aws_vpc_security_group_ingress_rule` | Libera `5432/TCP` apenas para o Security Group do EKS |
| `aws_db_instance` | Instância PostgreSQL gerenciada |
| `aws_ssm_parameter` | Publica dados não secretos para os consumidores |

Principais características da instância:

- engine PostgreSQL 16 por padrão;
- armazenamento `gp3` criptografado;
- 20 GiB iniciais e autoscaling até 100 GiB por padrão;
- endpoint privado;
- senha master gerenciada automaticamente;
- retenção de backup de sete dias;
- snapshot final obrigatório na destruição;
- proteção contra exclusão habilitada por padrão.

## Variáveis Terraform

| Variável | Padrão | Descrição |
| --- | --- | --- |
| `aws_region` | `us-east-1` | Região AWS |
| `project_name` | `oficina` | Prefixo dos recursos e parâmetros |
| `environment` | `dev` | Ambiente usado nos nomes e caminhos SSM |
| `database_name` | `oficina_db` | Nome lógico do banco |
| `master_username` | `oficina_admin` | Usuário administrador |
| `engine_version` | `16` | Versão principal do PostgreSQL |
| `instance_class` | `db.t3.micro` | Classe da instância |
| `allocated_storage` | `20` | Armazenamento inicial em GiB |
| `max_allocated_storage` | `100` | Limite do autoscaling de armazenamento |
| `multi_az` | `false` | Habilita standby em outra AZ |
| `backup_retention_period` | `7` | Retenção de backups em dias |
| `deletion_protection` | `true` | Impede exclusão acidental |

O arquivo `terraform.tfvars.example` mostra uma configuração mínima para desenvolvimento ou laboratório.

Exemplo com maior disponibilidade:

```hcl
aws_region             = "us-east-1"
project_name           = "oficina"
environment            = "prod"
instance_class         = "db.t3.small"
multi_az               = true
backup_retention_period = 14
deletion_protection    = true
```

## Outputs

| Output | Conteúdo |
| --- | --- |
| `database_endpoint` | DNS privado da instância |
| `database_port` | Porta do PostgreSQL |
| `database_name` | Nome lógico do banco |
| `master_secret_arn` | ARN sensível da credencial gerenciada |

## Parâmetros publicados no SSM

Após o apply são disponibilizados:

```text
/oficina/ENV/database/endpoint
/oficina/ENV/database/port
/oficina/ENV/database/name
/oficina/ENV/database/security-group-id
/oficina/ENV/database/master-secret-arn
```

O workflow da aplicação usa esses parâmetros para montar a URL JDBC e localizar o secret com `username` e `password`.

## Backend remoto

O state fica no bucket criado pelo bootstrap do repositório `oficina-k8s-infra`.

| Ambiente | Chave do state |
| --- | --- |
| Homologação | `oficina/database/hom.tfstate` |
| Produção | `oficina/database/prod.tfstate` |

O backend usa criptografia e locking nativo por `.tflock`.

## Validação local

Sem acessar a AWS:

```powershell
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

## Planejamento e aplicação manual

Exemplo para homologação:

```powershell
$env:TF_VAR_environment = "hom"
$env:TF_VAR_aws_region = "us-east-1"

terraform init -reconfigure `
  -backend-config="bucket=SEU_BUCKET" `
  -backend-config="key=oficina/database/hom.tfstate" `
  -backend-config="region=us-east-1" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true"

terraform plan -out=tfplan
terraform apply tfplan
```

As credenciais AWS devem possuir acesso ao backend S3, RDS, EC2 Security Groups, SSM e Secrets Manager.

## CI/CD

O workflow `.github/workflows/terraform.yml` autentica na AWS por OIDC.

| Evento | Comportamento |
| --- | --- |
| Pull request | `fmt`, `validate` e `plan` para PRs do próprio repositório |
| Push em `homologacao` | Aplica o ambiente `hom` |
| Push em `main` ou `master` | Aplica o ambiente `prod` |
| `workflow_dispatch` | Execução manual na branch selecionada |

Variables esperadas, normalmente configuradas pelo bootstrap:

- `AWS_ROLE_ARN`
- `AWS_REGION`
- `TF_STATE_BUCKET`

Este repositório não precisa receber senha do banco como secret do GitHub: o RDS gera e mantém a senha no Secrets Manager.

## Migrations e inicialização

O Terraform não executa migrations. Quando a aplicação inicia, o Flyway lê os scripts do repositório `gestao-oficina-tc-1` e aplica as versões pendentes no RDS.

Configurações esperadas na aplicação:

```text
SPRING_JPA_HIBERNATE_DDL_AUTO=none
SPRING_FLYWAY_BASELINE_ON_MIGRATE=true
SPRING_FLYWAY_BASELINE_VERSION=0
SPRING_FLYWAY_VALIDATE_ON_MIGRATE=true
```

## Verificação após o apply

```powershell
terraform output database_endpoint
terraform output database_port
aws ssm get-parameters-by-path --path /oficina/hom/database --recursive
```

Para produção, substitua `hom` por `prod`.

O endpoint não aceita conexão direta da internet. A validação de conectividade deve ser feita a partir de um workload autorizado na VPC/EKS.

## Destruição e proteção de dados

Com `deletion_protection = true`, o RDS não pode ser destruído. Para uma remoção intencional:

1. faça backup ou confirme que os dados podem ser descartados;
2. altere `deletion_protection` para `false` e aplique;
3. execute `terraform destroy`;
4. confirme a criação do snapshot final.

O snapshot final usa o identificador `oficina-ENV-postgres-final`. Uma nova destruição com o mesmo nome exige tratar o snapshot anterior.

## Estrutura

```text
.
├── .github/workflows/terraform.yml
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── terraform.tfvars.example
```
