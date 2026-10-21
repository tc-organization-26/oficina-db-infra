# RDS PostgreSQL no AWS Lab

Este repositório é o terceiro passo da implantação completa, depois do bootstrap e da infraestrutura EKS/rede.

## Arquitetura

```text
Oficina API no EKS
    |
    | TCP 5432, autorizado pelo Security Group do cluster
    v
RDS PostgreSQL privado
    +-- subnets privadas da VPC
    +-- armazenamento gp3 criptografado
    +-- senha master gerenciada pelo Secrets Manager
    +-- backups automáticos
    +-- parâmetros de descoberta publicados no SSM
```

O banco não possui endpoint público. O Flyway da aplicação executa as migrations na inicialização.

## Pré-requisitos

Antes do deploy:

1. execute `bootstrap.yml` do `oficina-k8s-infra`;
2. conclua o `terraform.yml` do `oficina-k8s-infra`;
3. confirme as variables `AWS_REGION` e `TF_STATE_BUCKET` neste repositório.

Os Organization secrets necessários são:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
```

Configure-os com acesso aos quatro repositórios. Eles são temporários e precisam ser atualizados quando a sessão do Lab expirar.

## Promoção automática entre branches

O workflow usa o `GITHUB_TOKEN` fornecido automaticamente pelo GitHub. Em **Settings → Actions → General → Workflow permissions**, selecione **Read and write permissions** e habilite **Allow GitHub Actions to create and approve pull requests**. Não é necessário cadastrar outro secret.

O fluxo de promoção é:

```text
push em fase-3
  -> abre ou atualiza PR de fase-3 para homologacao
  -> merge manual após os checks
  -> abre ou atualiza PR de homologacao para main
  -> merge manual após os checks
```

Se `homologacao` ainda não existir, o workflow a cria a partir de `main`. Proteja `homologacao` e `main` contra push direto e exija Pull Request para merge.

## Execução

Pelo GitHub: **Actions → CI/CD - RDS → Run workflow**, selecionando `fase-3` para homologação.

Pelo terminal:

```powershell
gh workflow run terraform.yml `
  --repo tc-organization-26/oficina-db-infra `
  --ref fase-3

gh run list `
  --repo tc-organization-26/oficina-db-infra `
  --workflow terraform.yml `
  --limit 3

gh run watch ID `
  --repo tc-organization-26/oficina-db-infra `
  --exit-status
```

Branches `fase-3` e `homologacao` usam `hom`; `main` e `master` usam `prod`. O state fica em:

```text
s3://TF_STATE_BUCKET/oficina/database/hom.tfstate
s3://TF_STATE_BUCKET/oficina/database/prod.tfstate
```

## Recursos e integração

O Terraform cria o DB subnet group, security group, instância RDS e parâmetros SSM. A senha não é gravada no GitHub: o RDS a mantém no Secrets Manager.

Parâmetros publicados:

```text
/oficina/ENV/database/endpoint
/oficina/ENV/database/port
/oficina/ENV/database/name
/oficina/ENV/database/security-group-id
/oficina/ENV/database/master-secret-arn
```

## Validação

```powershell
aws rds describe-db-instances `
  --query "DBInstances[].{Nome:DBInstanceIdentifier,Status:DBInstanceStatus,Endpoint:Endpoint.Address}" `
  --output table

aws ssm get-parameters-by-path `
  --path /oficina/hom/database `
  --recursive `
  --output table
```

O status esperado do RDS é `available`. A conectividade deve ser testada a partir do EKS, pois o endpoint é privado.

## Segurança e encerramento

Não revele o conteúdo do secret master nos logs. Para destruir o ambiente, remova a proteção contra exclusão de forma intencional, aplique a mudança e só então execute o destroy. Destrua o RDS antes da VPC do repositório Kubernetes.
