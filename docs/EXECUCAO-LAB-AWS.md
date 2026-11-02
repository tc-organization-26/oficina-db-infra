# Execução no laboratório AWS — oficina-db-infra

[README](../README.md) · [Validação local e execução manual](VALIDACAO-E-EXECUCAO-MANUAL.md)

Para preparar o computador, consulte a [instalação das ferramentas](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/main/docs/INSTALACAO-FERRAMENTAS.md). Para executar fora do Academy/Vocareum, siga a [preparação de conta AWS comum](https://github.com/tc-organization-26/oficina-k8s-infra/blob/main/docs/CONTA-AWS-COMUM.md), incluindo as adaptações de IAM, Terraform e workflows.

Guia de configuração, implantação e validação deste componente na AWS. Os comandos de verificação usam `hom`; para produção, troque os caminhos/nomes para `prod` e selecione `main`.

> **Observação — adaptações educacionais:** o código atual foi adaptado para AWS Academy/Vocareum: utiliza credenciais temporárias e reutiliza a `LabRole` no EKS, nos nós e nas Lambdas, sem criar roles IAM ou provider OIDC. O bootstrap procura essa role e o workflow EKS aplica um patch específico para as restrições do ambiente. Em uma conta AWS comum, prepare as roles e permissões necessárias e ajuste o bootstrap, o Terraform e os workflows antes de seguir este roteiro. A `LabRole` não é fornecida automaticamente em uma conta comum. Os nomes `LAB_ROLE_ARN`, `lab_role_arn` e dos scripts foram preservados porque correspondem ao código.

## Credenciais e ferramentas

Os quatro repositórios devem existir no GitHub e conter o código que será implantado. Configure os acessos do checklist antes de iniciar o componente correspondente.

Você pode acompanhar o deploy pela interface do GitHub, sem ferramentas locais. Para usar os exemplos do terminal, instale GitHub CLI e autentique com `gh auth login`. Para as verificações AWS, instale AWS CLI; para EKS, instale também kubectl. Configure as [credenciais no terminal](VALIDACAO-E-EXECUCAO-MANUAL.md#credenciais-para-comandos-locais-que-acessam-a-aws) antes de executar comandos `aws` ou `kubectl`.

Os exemplos usam PowerShell e a região `us-east-1`; ajuste a região se sua instalação usar outra.

## Checklist inicial

Antes da primeira implantação, confira a configuração abaixo. Os secrets AWS devem estar disponíveis já para o bootstrap; os demais itens devem estar prontos antes do deploy do componente correspondente.

| Conferir | Onde cadastrar | Configuração |
| --- | --- | --- |
| [ ] Credenciais AWS válidas | Organization secrets com acesso aos quatro repositórios, ou Repository secrets em cada um | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`; renove os três juntos quando a sessão expirar. Para o bootstrap, não deixe esses valores somente em Environment secrets. |
| [ ] Token de administração GitHub | Repository secret em `oficina-k8s-infra` | `GH_ADMIN_TOKEN`, com leitura dos quatro repositórios e permissão para administrar Actions Variables. |
| [ ] Chave de assinatura JWT | Environment secret em `oficina-auth-lambda` | `JWT_SECRET`, com pelo menos 32 bytes aleatórios, no Environment `homologacao` e, quando utilizar produção, em `producao`. A API lê essa chave do Secrets Manager. |
| [ ] Leitura da imagem GHCR | Environment secrets em `gestao-oficina-tc-1` | `GHCR_USERNAME` e `GHCR_TOKEN`, com `read:packages` e acesso ao pacote, nos Environments utilizados. A publicação usa o `GITHUB_TOKEN` automático. |
| [ ] Chaves Datadog | Environment secrets em `gestao-oficina-tc-1` | `DD_API_KEY` e `DD_APP_KEY` (permissões para dashboards, monitores, pipelines e métricas de logs), nos Environments utilizados. Não é necessário duplicá-las no repositório de autenticação. |
| [ ] Destino e região Datadog | Environment variables em `gestao-oficina-tc-1` | `DD_NOTIFICATION_TARGET` com um destino real, como `@voce@dominio.com`; `DD_SITE` (padrão `datadoghq.com`) e `DD_API_URL` (padrão `https://api.datadoghq.com/`) devem corresponder ao mesmo site. Configure `DD_SITE` correspondente em `oficina-auth-lambda` quando necessário. |
| [ ] Permissões de promoção | Settings → Actions → General nos quatro repositórios | Habilitar escrita do `GITHUB_TOKEN` e criação de Pull Requests, conforme a seção de branches. |

Para cadastrar Repository secrets/variables, use **Settings → Secrets and variables → Actions**. Para Environment secrets/variables, use **Settings → Environments → homologacao** ou **producao** no repositório indicado. Os secrets da organização ficam em **Organization settings → Secrets and variables → Actions**.

`AWS_REGION`, `TF_STATE_BUCKET` e `LAB_ROLE_ARN` são distribuídas pelo bootstrap. Confirme essas variables depois que ele concluir; `AWS_ROLE_ARN` é mantida apenas por compatibilidade. Secrets/variables de Environment devem corresponder ao ambiente utilizado. O deploy da API exige a configuração Datadog.

## Branches e ambientes

| Branch | Execução automática ou manual | Ambiente AWS | GitHub Environment |
| --- | --- | --- | --- |
| `fase-3` | Valida e abre/mantém PR para `homologacao`; não faz deploy | Nenhum deploy | — |
| `homologacao` | Valida, faz deploy e abre/mantém PR para `main` após sucesso | `hom` | `homologacao` |
| `main` | Valida e faz deploy | `prod` | `producao` |

Os merges são manuais. `workflow_dispatch` respeita a mesma condição de deploy: escolher `fase-3` apenas valida. Os workflows não têm gatilho `pull_request`; os checks rodam por push na branch de origem ou por execução manual.

Em **Settings → Actions → General → Workflow permissions**, habilite **Read and write permissions** e **Allow GitHub Actions to create and approve pull requests**. A promoção usa `GITHUB_TOKEN`, sem token adicional. O workflow pode criar `homologacao` a partir de `main` se ela ainda não existir. Proteja as branches de destino e revise os checks antes do merge.

### Primeiro deploy e reexecuções

Depois da validação em `fase-3`, faça o merge do PR para `homologacao` quando as dependências deste componente estiverem prontas. **O próprio merge gera um push em `homologacao` e já dispara a validação e o deploy em `hom`.** Acompanhe essa execução em Actions e aguarde seu sucesso antes de avançar para o próximo repositório.

**Não é necessário executar Run workflow depois de um merge bem-sucedido.** Use a execução manual como alternativa quando a branch já contiver o código desejado, ou para reexecutar o deploy após corrigir configuração/credenciais. Fazer merge em `main` dispara o deploy de produção da mesma forma.

## Ordem da primeira implantação

1. `oficina-k8s-infra`: executar `bootstrap.yml` para preparar o backend e as variables.
2. `oficina-k8s-infra`: fazer merge para `homologacao` e aguardar `terraform.yml` criar rede, EKS e entrada HTTP.
3. `oficina-db-infra`: fazer merge para `homologacao` e aguardar `terraform.yml` criar o RDS.
4. `oficina-auth-lambda`: fazer merge para `homologacao` e aguardar `cicd.yml` publicar funções, chave JWT e rotas.
5. `gestao-oficina-tc-1`: fazer merge para `homologacao` e aguardar `cicd.yml` publicar a API, aplicar Flyway e instalar observabilidade.
6. `oficina-auth-lambda`: reexecutar o deploy para habilitar Datadog com o secret compartilhado criado pela API.

Execute os passos em sequência e no mesmo ambiente. Se a branch já contiver o código desejado, a execução manual pode substituir o merge dos passos 2 a 5. As esteiras são independentes: uma não dispara a próxima. O passo 4 pode ser implantado antes das tabelas; o teste de login só deve ocorrer após o Flyway do passo 5.

## Configuração específica do banco

Conclua bootstrap e rede/EKS antes deste deploy. Confirme as variables `AWS_REGION` e `TF_STATE_BUCKET`. Este workflow não usa `LAB_ROLE_ARN` e não recebe senha do banco pelo GitHub: o RDS gera a credencial no Secrets Manager.

O plano lê a rede e o SG dos nós pelo SSM e publica a configuração do RDS sob `/oficina/ENV/database/`. Consulte no README as [dependências SSM](../README.md#dependência-obrigatória), as [variáveis Terraform](../README.md#variáveis-terraform) e os [parâmetros publicados](../README.md#parâmetros-publicados-no-ssm). Se um parâmetro de entrada não existir no ambiente correto, retorne à etapa de plataforma.

O state usa o [backend remoto](../README.md#backend-remoto) compartilhado, com chave por ambiente. O Terraform cria a instância; somente a API cria tabelas e dados iniciais via Flyway.

## Deploy deste repositório

Acompanhe em **Actions → CI/CD - RDS** a execução disparada pelo merge. Para a [alternativa manual ou reexecução](#primeiro-deploy-e-reexecuções), selecione **Run workflow → homologacao**; a branch deve conter o código desejado e as dependências devem estar prontas. Para produção, selecione `main`. Pelo terminal, use `terraform.yml`:

```powershell
gh workflow run terraform.yml --repo tc-organization-26/oficina-db-infra --ref homologacao
gh run list --repo tc-organization-26/oficina-db-infra --workflow terraform.yml --limit 3
gh run watch ID_DA_EXECUCAO --repo tc-organization-26/oficina-db-infra --exit-status
```

O dispatch é assíncrono. Use o ID retornado pela listagem para acompanhar a execução correta e aguarde sucesso antes da próxima etapa.

## Validar o banco

```powershell
aws rds describe-db-instances `
  --query "DBInstances[].{Nome:DBInstanceIdentifier,Status:DBInstanceStatus,Endpoint:Endpoint.Address}" `
  --output table
aws ssm get-parameters-by-path --path /oficina/hom/database --recursive --output table
```

Espere o RDS em `available`. Com o backend inicializado localmente, use `terraform output database_endpoint` e `terraform output database_port`. O endpoint é privado; teste conexão a partir de um workload autorizado no EKS/VPC. Não tente acessá-lo diretamente pela internet. Depois do primeiro startup da API, o readiness e os logs Flyway ajudam a verificar conexão e schema.

## Problemas comuns

Consulte o [troubleshooting deste repositório](TROUBLESHOOTING.md) para credenciais, branches, dependências e falhas do componente.

## Executando destroy

O RDS tem `deletion_protection=true` e snapshot final obrigatório. Para remoção intencional, confira backup, aplique `deletion_protection=false`, revise `terraform plan -destroy` e execute `terraform destroy` usando o mesmo backend/ambiente. Verifique o snapshot `oficina-ENV-postgres-final`; um snapshot anterior com esse nome exige tratamento antes de outra destruição. Remova a autenticação antes do banco e o banco antes da VPC. Snapshots preservados também podem manter custos.

Ordem geral: API e observabilidade → autenticação → RDS → EKS/rede → bucket de state. Renovar credenciais não remove recursos. Para repetir uma sessão, confirme conta, região e state antes de executar novamente.

## Outros componentes

Consulte os [repositórios e suas responsabilidades](../README.md#repositórios-da-solução).
