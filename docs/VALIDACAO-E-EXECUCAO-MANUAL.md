# Validação local e execução manual na AWS — oficina-db-infra

[README](../README.md) · [Troubleshooting](TROUBLESHOOTING.md) · [AWS](EXECUCAO-LAB-AWS.md)

Para preparar o computador, consulte a [instalação das ferramentas](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/main/docs/INSTALACAO-FERRAMENTAS.md). Para executar fora do Academy/Vocareum, siga a [preparação de conta AWS comum](https://github.com/tc-organization-26/oficina-k8s-infra/blob/main/docs/CONTA-AWS-COMUM.md), incluindo as adaptações de IAM, Terraform e workflows.

Pré-requisitos: Git e Terraform >= 1.10 (as esteiras fixam 1.15.9). Comece na raiz do repositório.

## O que pode ser executado localmente

Este repositório não fornece um cluster Kubernetes ou PostgreSQL local. A validação abaixo confere o Terraform; `plan` e `apply`, mesmo executados no computador, provisionam AWS. Para desenvolver a aplicação com PostgreSQL local, utilize o [Docker Compose da API](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/main/docs/EXECUCAO-LOCAL.md), sem aplicar este Terraform.

## Validação sem credenciais AWS

A validação não exige conta AWS. O `init` baixa providers/módulos e precisa de internet se eles ainda não estiverem no cache.

```powershell
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

> **Observação:** os comandos AWS abaixo seguem a configuração atual do projeto. Confira as [adaptações educacionais e os pré-requisitos de IAM](EXECUCAO-LAB-AWS.md) antes de utilizá-los em outra conta.

## Credenciais para comandos locais que acessam a AWS

`plan`, `apply` e comandos `aws` acessam a conta real; a aplicação dos planos pode criar recursos cobrados. As credenciais do GitHub não configuram automaticamente o seu terminal.

Copie as credenciais da sessão AWS para as variáveis do terminal, sem salvá-las no repositório:

```powershell
$env:AWS_ACCESS_KEY_ID = "ACCESS_KEY_DA_SESSAO"
$env:AWS_SECRET_ACCESS_KEY = "SECRET_KEY_DA_SESSAO"
$env:AWS_SESSION_TOKEN = "SESSION_TOKEN_DA_SESSAO"
$env:AWS_DEFAULT_REGION = "us-east-1"
aws sts get-caller-identity
```

Confira a conta antes do plano. Use o mesmo `project_name`, ambiente, região, bucket e chave de state usados pelo CI/CD; o padrão Terraform `environment=dev` não equivale a `hom` nem a `prod`. Não use um state novo para recursos que já estão gerenciados por outro state.

## Aplicação manual na AWS

Execute primeiro bootstrap e rede/EKS. O plano consulta os parâmetros SSM da VPC, sub-redes e SG dos nós.

Informe o bucket real criado pelo bootstrap, sem copiar literalmente `SEU_BUCKET` ou `ACCOUNT_ID`. Execute na raiz. A chave identifica o mesmo state usado pela esteira:

```powershell
$oficinaEnv = "hom" # Use "prod" para produção.
$env:TF_VAR_environment = $oficinaEnv
$env:TF_VAR_aws_region = "us-east-1"

terraform init -reconfigure `
  -backend-config="bucket=SEU_BUCKET" `
  -backend-config="key=oficina/database/$oficinaEnv.tfstate" `
  -backend-config="region=us-east-1" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true"

terraform plan -lock-timeout=5m -out=tfplan
```

Revise o plano, confira se não há outra execução ativa e aplique o plano salvo:

```powershell
terraform apply -lock-timeout=5m tfplan
terraform output
```

Para produção, defina `$oficinaEnv = "prod"` antes do `terraform init`; o exemplo usa esse valor tanto em `TF_VAR_environment` quanto na chave do backend. Reinicialize o backend e gere um novo plano sempre que trocar de ambiente. Não aplique manualmente em paralelo ao Actions. Não versione credenciais, `terraform.tfvars`, pacote, planos ou state; esses arquivos podem conter informações sensíveis. Consulte a [validação e o destroy na AWS](EXECUCAO-LAB-AWS.md).
