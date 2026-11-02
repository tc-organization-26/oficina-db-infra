# Oficina — Banco de dados

Terraform do RDS PostgreSQL privado, rede do banco, backups, criptografia e credencial gerenciada no Secrets Manager. Depende da rede publicada por oficina-k8s-infra. As tabelas são criadas pelo Flyway da API, não por este Terraform.

## Contexto e objetivo

Clientes, veículos, peças e ordens de serviço precisam manter seus vínculos ao longo de diagnóstico, aprovação, execução e entrega. A perda desse histórico compromete o atendimento, o controle do estoque e a rastreabilidade do orçamento e do pagamento.

Este componente entrega a persistência PostgreSQL gerenciada e privada para a solução. A API grava os dados e executa migrations; a Lambda de login consulta o cliente ativo por CPF. O banco permanece fora do ciclo de vida dos Pods, com armazenamento criptografado, backups e controles de acesso pela rede.

## Navegação

Os guias abaixo complementam este README com instruções de execução, configuração e diagnóstico.

**Guias e documentos complementares**

- [Instalação das ferramentas](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/INSTALACAO-FERRAMENTAS.md) — instalar ferramentas e conferir o ambiente.
- [Conta AWS comum](https://github.com/tc-organization-26/oficina-k8s-infra/blob/HEAD/docs/CONTA-AWS-COMUM.md) — preparar IAM, OIDC e adaptar a execução fora do Academy.
- [Validação local e execução manual](docs/VALIDACAO-E-EXECUCAO-MANUAL.md) — validação e execução pelo terminal.
- [Execução no laboratório AWS](docs/EXECUCAO-LAB-AWS.md) — checklist GitHub, dependências, deploy e encerramento.
- [Tecnologias e versões](docs/VERSOES.md) — tecnologias, ferramentas, versões e fontes.
- [Troubleshooting](docs/TROUBLESHOOTING.md) — diagnóstico por assunto e recuperação.

**Seções deste README**

- [Valor para o projeto](#valor-para-o-projeto)
- [Execução e deploy](#execução-e-deploy)
- [Arquitetura](#arquitetura)
- [Dados e fluxo de atendimento](#dados-e-fluxo-de-atendimento)
- [Disponibilidade e recuperação](#disponibilidade-e-recuperação)
- [Caminho da implantação](#caminho-da-implantação)
- [Variáveis Terraform](#variáveis-terraform)
- [Validação integrada](#validação-integrada)
- [Troubleshooting](#troubleshooting)

## Valor para o projeto

- persistência centralizada para clientes, veículos, serviços, estoque, orçamentos e OS;
- integridade referencial e transações usadas pela aplicação nas operações do domínio;
- acesso privado por Security Groups da API e da Lambda de login;
- credencial master gerenciada pelo RDS e armazenada no Secrets Manager;
- backups automáticos, proteção contra exclusão e snapshot final;
- endpoint e contratos publicados no SSM para implantações reproduzíveis.

## Responsabilidades deste repositório

- consumir a rede privada e o Security Group dos nós EKS publicados pela plataforma;
- provisionar subnet group, Security Group e RDS PostgreSQL privado;
- habilitar armazenamento criptografado, backups e crescimento automático do armazenamento;
- manter proteção contra exclusão e snapshot final para remoção intencional;
- delegar a geração e manutenção da senha master ao Secrets Manager;
- publicar endpoint, porta, nome do banco, Security Group e ARN da credencial no SSM.

## Repositórios da solução

| Repositório | Responsabilidade |
| --- | --- |
| [gestao-oficina-tc-1](https://github.com/tc-organization-26/gestao-oficina-tc-1#readme) | API Java, migrations, Docker Compose e deploy da aplicação |
| [oficina-k8s-infra](https://github.com/tc-organization-26/oficina-k8s-infra#readme) | Bootstrap, rede, EKS, escalabilidade e entrada HTTP |
| [oficina-db-infra](https://github.com/tc-organization-26/oficina-db-infra#readme) | RDS PostgreSQL privado, backups e credencial gerenciada |
| [oficina-auth-lambda](https://github.com/tc-organization-26/oficina-auth-lambda#readme) | Login por CPF, JWT e rotas protegidas do Gateway |

## Dependência obrigatória

Execute primeiro `oficina-k8s-infra`. Este Terraform lê os seguintes parâmetros do AWS Systems Manager Parameter Store:

```text
/oficina/ENV/network/vpc-id
/oficina/ENV/network/private-subnet-ids
/oficina/ENV/eks/node-security-group-id
```

Se esses parâmetros não existirem para o ambiente selecionado, o `terraform plan` falhará antes de criar o banco.

## Execução e deploy

### Validação local e execução manual

Consulte o [guia de validação local e execução manual](docs/VALIDACAO-E-EXECUCAO-MANUAL.md) para validar o Terraform e executar plan/apply pelo terminal com o backend correto. A validação não exige credenciais AWS, mas o init pode baixar providers.

Este repositório não cria PostgreSQL local. Para desenvolvimento, use o Compose da aplicação. Executar Terraform no computador continua provisionando RDS na AWS.

### Deploy e execução no laboratório AWS

Prepare o [checklist de acessos e configurações](docs/EXECUCAO-LAB-AWS.md#checklist-inicial) e conclua as dependências na [ordem de implantação](docs/EXECUCAO-LAB-AWS.md#ordem-da-primeira-implantação). Faça o merge para `homologacao` para disparar o deploy em `hom` e aguarde a conclusão. Para produção, use `main` após validar homologação. **Run workflow é uma alternativa ou reexecução**, não um passo obrigatório após o merge.

> O código contém adaptações educacionais de IAM e credenciais. Confira a observação do guia AWS antes de utilizá-lo em outra conta.

Conclua primeiro bootstrap e plataforma Kubernetes/rede no mesmo ambiente. O workflow valida, planeja e aplica o banco, sem executar SQL de negócio. Autenticação e API usam os dados publicados no SSM; a API cria as tabelas quando o Flyway inicia.

## Arquitetura

```mermaid
flowchart LR
    rede["Rede e sub-redes · oficina-k8s-infra"] -.->|Parâmetros SSM| terraform["Terraform · oficina-db-infra"]
    subgraph vpc["VPC · sub-redes privadas"]
        api["Oficina API no EKS"] -->|SG dos nós · TCP 5432| sg["Security Group do banco"]
        login["Lambda de login"] -->|SG da Lambda · regra criada em oficina-auth-lambda| sg
        sg --> rds[("RDS PostgreSQL · armazenamento criptografado")]
        subnet["DB Subnet Group"] -.-> rds
    end
    terraform -.->|Provisiona| rds
    terraform -.->|Provisiona| sg
    terraform -.->|Provisiona| subnet
    rds -.-> secrets["Secrets Manager · senha master gerenciada"]
    rds -.-> backup["Backups automáticos e snapshot final"]
    terraform -.-> ssm["SSM · endpoint, porta, nome, SG e ARN do secret"]
```

Consulte os [recursos principais](#recursos-principais) deste componente. A [arquitetura integrada da aplicação](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/ARQUITETURA-SOLUCAO.md) reúne os quatro projetos e suas sequências.

## Arquitetura provisionada

A API no EKS e a Lambda de login acessam o mesmo RDS privado por regras de Security Group distintas. O Secrets Manager mantém a credencial gerenciada. A API executa o Flyway; a Lambda consulta `cliente` para autenticação. A [visão de componentes](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/ARQUITETURA-SOLUCAO.md#diagrama-de-componentes-da-aplicação) mostra essas conexões.

O banco é um serviço gerenciado RDS; não utiliza contêiner, Dockerfile ou PVC Kubernetes.

## Dados e fluxo de atendimento

| Etapa da oficina | Participação da persistência |
| --- | --- |
| Identificação | Mantém cliente, CPF/CNPJ e veículos vinculados; a Lambda consulta cliente ativo no login |
| Abertura da OS | Registra ordem, cliente, veículo e orçamento inicial |
| Diagnóstico e orçamento | Mantém diagnóstico, itens de serviço, peças e estado do orçamento |
| Aprovação e execução | Persiste decisão e transições da OS; a API controla as regras de avanço e revisão |
| Estoque | Mantém quantidades e dados usados pelas operações de inclusão e baixa da API |
| Pagamento e entrega | Persiste confirmação interna de pagamento e datas/status do atendimento |
| Acompanhamento | Disponibiliza dados para consulta individual, histórico de status e tempo médio de execução |

As tabelas e as regras não são criadas pelo Terraform deste componente. O [modelo relacional](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/modelo-relacional/README.md) documenta schema, relações e migrations, e o [fluxo de atendimento](https://github.com/tc-organization-26/gestao-oficina-tc-1#fluxo-de-atendimento) descreve o uso pela oficina.

## Disponibilidade e recuperação

O padrão `multi_az=false` cria a instância sem standby Multi-AZ. O subnet group abrange sub-redes de duas zonas, mas isso não ativa redundância do banco. HPA e Cluster Autoscaler da API também não escalam a capacidade de processamento do RDS.

O armazenamento começa em 20 GiB e pode crescer até 100 GiB por padrão. Esse crescimento não substitui o dimensionamento da classe da instância, das conexões e das consultas. Para maior disponibilidade, avalie `multi_az=true` e a classe adequada ao ambiente, conforme o [exemplo de configuração](#variáveis-terraform).

Backups automáticos têm retenção padrão de sete dias. A proteção contra exclusão fica habilitada e a remoção intencional exige tratar o snapshot final, seguindo o [guia de encerramento](docs/EXECUCAO-LAB-AWS.md#encerramento). Backups oferecem recuperação de dados; não equivalem a failover. O [troubleshooting](docs/TROUBLESHOOTING.md) orienta diagnóstico e recuperação, que devem ser validados para o ambiente utilizado.

## Caminho da implantação

```text
Bootstrap e plataforma prontos no mesmo ambiente
  → ler VPC, sub-redes privadas e Security Group do EKS pelo SSM
  → Terraform plan/apply do subnet group, SG e RDS
  → publicar endpoint, porta, nome, SG e ARN da credencial no SSM
  → autenticação acrescentar acesso da Lambda e publicar login/Authorizer
  → API iniciar, executar Flyway e criar as tabelas e dados iniciais
  → validar login e operações de negócio
```

O sucesso do apply comprova a criação da infraestrutura; tabelas e login dependem do startup da API. As esteiras são independentes e devem ser executadas em sequência conforme o [guia AWS](docs/EXECUCAO-LAB-AWS.md).

## Recursos principais

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
- `multi_az=false` por padrão; sub-redes em duas zonas não habilitam automaticamente uma instância standby;
- senha master gerenciada automaticamente;
- retenção de backup de sete dias;
- snapshot final obrigatório na destruição;
- proteção contra exclusão habilitada por padrão.

## Acesso à API

Este repositório provisiona infraestrutura e não expõe uma API de negócio própria. A documentação e as requisições da aplicação consumidora estão disponíveis em:

- [Swagger local da Oficina API](http://localhost:8081/swagger-ui/index.html), após iniciar a aplicação.
- [Collection Insomnia da Oficina API](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/src/main/docs/insomnia/collection.yaml).
- [Collection Insomnia do login por CPF](https://github.com/tc-organization-26/oficina-auth-lambda/blob/HEAD/docs/insomnia/collection.json).

## Estrutura do repositório

| Arquivo ou diretório | Responsabilidade |
| --- | --- |
| [main.tf](main.tf) | Rede via SSM, subnet group, SG, instância e publicação dos dados do banco |
| [variables.tf](variables.tf) | Região, ambiente, engine, classe, armazenamento, disponibilidade, backup e proteção |
| [outputs.tf](outputs.tf) | Endpoint, porta, nome e ARN sensível da credencial |
| [versions.tf](versions.tf) e [.terraform.lock.hcl](.terraform.lock.hcl) | Compatibilidade Terraform e resolução do provider AWS |
| [terraform.tfvars.example](terraform.tfvars.example) | Exemplo inicial para execução pelo terminal |
| [.github/workflows/terraform.yml](.github/workflows/terraform.yml) | Validação, plan/apply e promoção |
| [docs/](docs) | Execução, versões e diagnóstico |

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

O arquivo `terraform.tfvars.example` mostra uma configuração inicial; ajuste os valores ao ambiente desejado.

Exemplo com maior disponibilidade:

```hcl
aws_region              = "us-east-1"
project_name            = "oficina"
environment             = "prod"
instance_class          = "db.t3.small"
multi_az                = true
backup_retention_period = 14
deletion_protection     = true
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

## Migrations e inicialização

O Terraform não executa migrations. Quando a aplicação inicia, o Flyway lê os scripts do repositório `gestao-oficina-tc-1` e aplica as versões pendentes no RDS.

As [variáveis e migrations da API](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/README.md#banco-e-migrations) documentam a configuração do Flyway. O primeiro startup precisa terminar antes de usar o login por CPF.

## Validação após o deploy

Confirme a instância em `available` e os parâmetros do ambiente no SSM, conforme o [roteiro de validação](docs/EXECUCAO-LAB-AWS.md#validar-o-banco). Os outputs são `database_endpoint`, `database_port`, `database_name` e `master_secret_arn`.

Teste a conexão a partir de um workload autorizado na VPC/EKS. Depois do startup da API, o readiness verifica também o banco. Uma instância disponível ainda pode estar sem tabelas se o Flyway não tiver concluído.

## Validação integrada

1. Confirme a instância disponível, os parâmetros SSM e o ARN do secret conforme a [validação do banco](docs/EXECUCAO-LAB-AWS.md#validar-o-banco).
2. Implante a API e confirme a conclusão das migrations Flyway e o readiness com `status=UP`.
3. Teste o login por CPF pela Lambda após o seed de cliente ativo.
4. Execute o [roteiro de validação do atendimento](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/VALIDACAO-FLUXO.md), consultando a OS criada e sua evolução até a entrega.
5. Para validar persistência após um novo rollout da API, consulte pelo ID uma ordem criada anteriormente; recriar Pods não deve apagar os dados do RDS.

Mantenha os testes de recuperação e remoção em ambiente apropriado e use o mesmo state do componente. O RDS não precisa receber acesso público para validar as operações da aplicação.

## Observabilidade

Eventos e métricas RDS ajudam a investigar disponibilidade, conexões, CPU e armazenamento. API e Lambda registram falhas PostgreSQL nos próprios logs/traces; a configuração Datadog pertence à aplicação. Consulte o [diagnóstico de conectividade e credenciais](docs/TROUBLESHOOTING.md#conectividade-e-credencial-gerenciada) e o [guia de observabilidade da API](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/OBSERVABILIDADE.md).

## Encerramento

`deletion_protection=true` impede a remoção da instância e `skip_final_snapshot=false` exige snapshot final. O identificador é `oficina-ENV-postgres-final`; um snapshot existente com o mesmo nome precisa ser tratado antes de outra destruição.

O [procedimento de encerramento](docs/EXECUCAO-LAB-AWS.md#encerramento) reúne a ordem de remoção, a desativação intencional da proteção e a conferência dos backups.

Remova autenticação e consumidores antes do RDS, e o banco antes da VPC. Snapshots preservados podem permanecer após a instância.

## Workflow

- [Workflow deste componente](.github/workflows/terraform.yml).
- [Histórico de execuções](https://github.com/tc-organization-26/oficina-db-infra/actions/workflows/terraform.yml).

### Fluxo de branches

`fase-3` valida e abre PR para `homologacao`; `homologacao` faz deploy em `hom` e abre PR para `main`; `main` faz deploy em `prod`. Os merges são manuais. Executar manualmente em `fase-3` também só valida. Consulte [branches e ambientes](docs/EXECUCAO-LAB-AWS.md#branches-e-ambientes).

## Troubleshooting

Consulte o [guia de diagnóstico deste componente](docs/TROUBLESHOOTING.md) para sintomas, comandos de verificação e correções por assunto. O guia também referencia os demais componentes quando a falha atravessa rede, banco, autenticação ou aplicação.