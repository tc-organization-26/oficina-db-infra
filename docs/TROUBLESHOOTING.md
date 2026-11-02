# Troubleshooting — oficina-db-infra

[README](../README.md) · [Validação local e execução manual](VALIDACAO-E-EXECUCAO-MANUAL.md) · [Execução no laboratório AWS](EXECUCAO-LAB-AWS.md)

## Troubleshooting de outros repositórios da solução

- [Aplicação: Docker, Java, API, Pods e Datadog](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/TROUBLESHOOTING.md).
- [Plataforma: bootstrap, EKS, rede e entrada HTTP](https://github.com/tc-organization-26/oficina-k8s-infra/blob/HEAD/docs/TROUBLESHOOTING.md).
- [Autenticação: Python, Lambda, CPF e Authorizer](https://github.com/tc-organization-26/oficina-auth-lambda/blob/HEAD/docs/TROUBLESHOOTING.md).

Este guia parte do sintoma, indica o que conferir e orienta a correção. Execute os comandos na raiz deste repositório, salvo indicação diferente. Cada bloco é um procedimento de diagnóstico independente; os exemplos usam PowerShell.

Nos exemplos AWS, use uma sessão válida e defina:

```powershell
$oficinaEnv = "hom"
$oficinaRegion = "us-east-1"
$env:AWS_DEFAULT_REGION = $oficinaRegion
aws sts get-caller-identity
```

Para produção, altere o ambiente para `prod` e confira a conta antes de prosseguir. As credenciais do GitHub não configuram o terminal; o [guia AWS](EXECUCAO-LAB-AWS.md#credenciais-e-ferramentas) explica os pré-requisitos de acesso. Ao compartilhar evidências, informe ambiente, horário, URL/caminho, status HTTP, ID do workflow e mensagem de erro. Remova tokens, senhas e valores de secrets dos trechos compartilhados.

## Assuntos

- [Credenciais AWS e GitHub Actions](#credenciais-aws-e-github-actions)
- [Terraform e state S3](#terraform-e-state-s3)
- [Dependências e provisionamento RDS](#dependências-e-provisionamento-rds)
- [Conectividade e credencial gerenciada](#conectividade-e-credencial-gerenciada)
- [Schema, migrations e dados](#schema-migrations-e-dados)
- [Backup, restauração e destroy](#backup-restauração-e-destroy)

## Credenciais AWS e GitHub Actions

### ExpiredToken, InvalidClientTokenId ou assinatura inválida

Renove juntos `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` na organização (com acesso ao repositório) ou nos Repository secrets. Atualize também o terminal utilizado. Verifique espaços acidentais e relógio da máquina se houver erro de assinatura/tempo. Repita `aws sts get-caller-identity`; ele precisa identificar a conta esperada antes de um novo deploy.

Se o erro persistir no Actions, confira se um secret do Environment está sobrescrevendo o valor renovado da organização. Reinicie a execução após corrigir; não é necessário refazer o bootstrap só para renovar credenciais.

### ParameterNotFound, ResourceNotFound ou recursos do ambiente errado

Confirme `AWS_REGION`, o ambiente (`hom`/`prod`), o prefixo `/oficina/ENV` e a conclusão da etapa anterior. Plataforma, banco e autenticação usam `dev` como padrão Terraform; a observabilidade da API usa `hom`. Selecione explicitamente `hom` ou `prod` para integrar o ambiente implantado. A primeira instalação segue bootstrap → plataforma → banco → autenticação → API → reexecução da autenticação para Datadog.

```powershell
aws ssm get-parameters-by-path --path "/oficina/$oficinaEnv" --recursive --query "Parameters[].Name" --output table
```

Uma lista vazia pode indicar conta/região errada ou pré-requisito ainda ausente. `AccessDenied` significa falta de permissão, não prova que o recurso não existe.

### Deploy pulado, execução aguardando aprovação ou PR sem checks novos

`fase-3` valida; apenas `homologacao` e `main` fazem deploy. O merge para `homologacao` já dispara a implantação em `hom`; não execute outro deploy manual após um merge bem-sucedido. Abrir um PR não dispara uma execução adicional: os workflows atuais não têm gatilho `pull_request`.

Se o job aguardar aprovação, confira as regras do GitHub Environment `homologacao`/`producao`. Se aguardar outro workflow, confira a concorrência configurada. Os runners são `ubuntu-latest`; instruções antigas para instalar um runner Windows self-hosted não se aplicam.

### Workflow não aparece, ferramentas faltam ou execução usa código antigo

Confira se o arquivo está em `.github/workflows`, se a branch selecionada contém a versão esperada e se o workflow permite execução manual. Uma alteração local ainda não enviada ao GitHub não muda o Actions. Na interface, procure o nome do workflow; no CLI, use o nome do arquivo mostrado no README.

`command not found` em um runner indica que a etapa de setup não foi executada ou que foi usada outra branch/versão do workflow. Confira o log dessa etapa antes de instalar ferramentas por fora da esteira. Para uma execução pendente, confira disponibilidade do runner e limites de uso da organização.

### PR automático falha com Resource not accessible by integration ou 403

Confira permissões de escrita e criação de PRs em **Settings → Actions → General → Workflow permissions**, além das políticas da organização. A promoção usa `GITHUB_TOKEN`; `GH_ADMIN_TOKEN` é reservado ao bootstrap. Verifique se a execução de origem passou e se há commits a promover. PR já existente é reutilizado; falha de deploy impede a promoção seguinte.

### IAM nega CreateRole, CreateOpenIDConnectProvider, PassRole ou leitura de secrets

O fluxo educacional atual reutiliza LabRole e não cria roles/OIDC. Tentativas de criação podem indicar código de outra branch ou bootstrap legado. Leia a ação e o recurso negados no log e confira a role configurada; reutilizar LabRole não garante todas as permissões necessárias. A instituição precisa liberar a ação quando houver negação imposta pela conta. Não troque para credenciais de outra conta mantendo o mesmo state.

## Terraform e state S3

### Terraform ausente, pasta errada ou sintaxe inválida

Use Terraform compatível com o projeto (o CI fixa `1.15.9`, mínimo `1.10.0`). Confira `terraform version`. Os arquivos Terraform deste componente ficam na raiz. Em `terraform.tfvars`, use HCL com valores literais ou variáveis `TF_VAR_*`; expressões Spring como `${VAR:padrao}` não são válidas nesse arquivo. `TF_VAR_*` não substitui os argumentos do backend.

```powershell
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

`fmt -check` informa divergência de formato; aplique `fmt` nos arquivos que alterou e revise o diff. O `init -backend=false` valida sem acessar o state S3, mas ainda pode baixar providers/módulos. Ele não prepara a aplicação na AWS.

### Falha no download, checksum ou provider incompatível

Confira rede, proxy, certificados e as versões de Terraform/providers declaradas. Use o lockfile versionado; um erro de checksum pode indicar pacote corrompido, plataforma sem hash registrado ou mudança de dependências. Não apague o lockfile nem rode `init -upgrade` como correção automática: isso pode selecionar versões diferentes. Mudanças de provider devem ser intencionais, revisadas e validadas antes do plano.

### Bucket ausente, AccessDenied ou Backend configuration changed

Conclua o bootstrap e confirme o bucket em `TF_STATE_BUCKET`, conta e região. Uma resposta 403 de `head-bucket` não prova ausência do bucket. O backend precisa de acesso aos objetos do state e do lock. No terminal, informe o mesmo bucket e a mesma chave do CI/CD:

```powershell
$oficinaBucket = "BUCKET_DISTRIBUIDO_PELO_BOOTSTRAP"
$env:TF_VAR_environment = $oficinaEnv
$env:TF_VAR_aws_region = $oficinaRegion
aws s3api head-bucket --bucket $oficinaBucket
terraform init -reconfigure `
  -backend-config="bucket=$oficinaBucket" `
  -backend-config="key=oficina/database/$oficinaEnv.tfstate" `
  -backend-config="region=$oficinaRegion" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true"
```

`-reconfigure` seleciona a configuração; não transfere automaticamente os recursos de outro state. Se há uma migração real de backend, preserve backup e planeje a migração, em vez de apontar um state vazio para recursos existentes. Pedidos de `secret_suffix`, `KUBE_CONFIG_BASE64` ou backend Kubernetes indicam instruções antigas da fase 2.

### Error acquiring the state lock

Confira execuções ativas no Actions e terminais. Aguarde a operação que possui o lock; interromper o acompanhamento não significa que o processo parou. As esteiras serializam sua própria branch, mas um apply manual ainda pode concorrer.

Somente após confirmar que não há operação ativa e que o backend acima é o correto, remova um lock abandonado com o ID exibido no erro:

```powershell
terraform force-unlock ID_EXATO_MOSTRADO_NO_ERRO
```

Não use `-lock=false`, não reutilize um ID de exemplo e não apague o objeto `.tflock` como rotina. Consulte a [referência do force-unlock](https://developer.hashicorp.com/terraform/cli/commands/force-unlock).

### Apply interrompido, recurso já existente ou plano propõe recriação inesperada

Uma execução com falha pode ter criado parte dos recursos. Preserve state e logs, corrija a causa e gere um novo plano no mesmo backend; não reaplique um plano salvo antes de mudanças no ambiente. Se o plano tentar criar tudo novamente, confira a chave, workspace e conta. O projeto usa o workspace padrão e chaves distintas por ambiente.

Recursos existentes fora do state exigem avaliação de importação, não exclusão por tentativa. Revise substituições e destruições antes de aplicar. Não edite o state manualmente para esconder uma divergência.

## Dependências e provisionamento RDS

### Plan falha ao buscar VPC, sub-redes ou SG dos nós

Conclua a plataforma no mesmo `project_name`, ambiente e região. Este Terraform consome `/oficina/ENV/network/vpc-id`, `/oficina/ENV/network/private-subnet-ids` e `/oficina/ENV/eks/node-security-group-id`. Não substitua esses parâmetros por IDs de outra conta/VPC. O [contrato SSM](../README.md#dependência-obrigatória) lista as entradas.

### RDS não chega a available ou configuração não é aceita

```powershell
aws rds describe-db-instances --db-instance-identifier "oficina-$oficinaEnv-postgres" --query "DBInstances[].{Name:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:EngineVersion,Class:DBInstanceClass,Pending:PendingModifiedValues}" --output json
aws rds describe-events --source-type db-instance --source-identifier "oficina-$oficinaEnv-postgres" --duration 60 --output table
```

Os nomes usam `project_name=oficina`. Confira eventos, quotas, versão PostgreSQL disponível na região, classe compatível e espaço das sub-redes. O subnet group usa sub-redes privadas em duas AZs; isso não habilita Multi-AZ automaticamente (`multi_az=false` por padrão). Se a conta restringir classe, criptografia, KMS ou Secrets Manager, use uma configuração permitida e revise o plano.

### Alteração aplicada, mas versão/classe ainda aparece antiga

O código usa `apply_immediately=false`. Confira `PendingModifiedValues`, a janela de manutenção e o estado da instância. Algumas alterações são agendadas ou podem exigir reinício; não altere para aplicação imediata sem avaliar o impacto no ambiente. PostgreSQL major 16 não fixa a minor instalada e atualizações minor automáticas estão habilitadas.

## Conectividade e credencial gerenciada

### Endpoint não responde do computador ou timeout na aplicação

O RDS tem `publicly_accessible=false`; falhar ao conectar pela internet é esperado. Teste de um workload autorizado na mesma rede. `Test-NetConnection` no computador não comprova a conectividade dos Pods/Lambda com esse endpoint privado.

```powershell
aws ssm get-parameters-by-path --path "/oficina/$oficinaEnv/database" --recursive --query "Parameters[].Name" --output table
aws rds describe-db-instances --db-instance-identifier "oficina-$oficinaEnv-postgres" --query "DBInstances[].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port,Vpc:DBSubnetGroup.VpcId,SGs:VpcSecurityGroups[].VpcSecurityGroupId,Public:PubliclyAccessible}" --output json
```

Confira DNS do endpoint, porta 5432, rotas e SGs. O SG do banco permite o SG dos nós EKS; a regra do SG da Lambda é criada pelo repositório de autenticação. Se só a Lambda falhar, confira essa segunda regra; se só a API falhar, confira SG dos nós e configuração JDBC. Não abra 5432 para `0.0.0.0/0` como diagnóstico. A [documentação RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ConnectToPostgreSQLInstance.Troubleshooting.html) detalha as camadas de conexão.

### Password authentication failed, usuário ou database incorreto

O RDS gera a senha master e armazena `username`/`password` no Secrets Manager. Confira o ARN publicado em `/oficina/ENV/database/master-secret-arn` e o nome do database, sem imprimir o valor do secret. Use a metadata para conferir localização e versões:

```powershell
$oficinaDbSecretArn = aws ssm get-parameter --name "/oficina/$oficinaEnv/database/master-secret-arn" --query Parameter.Value --output text
aws secretsmanager describe-secret --secret-id $oficinaDbSecretArn --query "{Name:Name,LastChanged:LastChangedDate,Versions:VersionIdsToStages}" --output json
```

Não use a senha do `.env` local no RDS. Se a credencial gerenciada mudou, a API pode estar usando a cópia anterior no Secret Kubernetes: reexecute o deploy da aplicação após conferir a versão correta. A Lambda mantém credenciais em cache por instância de execução; uma instância aquecida pode continuar com o valor anterior. Coordene a atualização dos consumidores em vez de trocar a senha por um valor manual desconectado do secret.

### AccessDenied no secret ou KMS

Identifique quem fez a leitura: runner da API, role da Lambda ou operador local. Ter acesso ao endpoint/SG não concede permissão de ler Secrets Manager. Confira o ARN do ambiente correto e a ação negada. O ARN do secret marcado como sensível no output não é a senha; não exponha seu conteúdo em logs ao testar.

### TLS, certificate verify failed ou no pg_hba.conf entry

A Lambda usa TLS com validação de certificado. Confira o endpoint real, as configurações do cliente, certificados confiáveis e a mensagem completa no log. Não desabilite TLS como correção genérica. Diferencie rejeição de autenticação de falha de rede; `no pg_hba.conf entry` pode envolver a forma de conexão/SSL, além do usuário/database. Confira também parâmetros de SSL do RDS e compatibilidade do driver.

## Schema, migrations e dados

### Instância available, mas não há tabela cliente

Este repositório cria a instância, não as tabelas de negócio. Aguarde o primeiro startup da API com Flyway. O login CPF só deve ser testado depois desse passo. Confira os logs da API e, por conexão autorizada, `flyway_schema_history`; não rode um script de criação manual para compensar uma migration que falhou.

### Flyway, seed ou histórico de status incompatíveis

O schema pertence à API. Confira ambiente/JDBC, versões aplicadas e alterações em migrations já executadas no [guia da aplicação](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/HEAD/docs/TROUBLESHOOTING.md#postgresql-e-flyway). A V3 prepara o cliente de teste; a V4 não calcula tempos retroativos. Restaurar um banco antigo exige deixar o Flyway aplicar as migrations pendentes antes de testar os consumidores.

### Lentidão, conexões esgotadas ou armazenamento baixo

Confira eventos e métricas RDS (conexões, CPU, memória disponível, armazenamento e latência), além das exceções JDBC/pg8000. O aumento de Pods HPA ou concorrência Lambda pode aumentar conexões; diferencie limite de conexões, consulta lenta e timeout de rede. Verifique sessões/consultas por acesso autorizado antes de aumentar a instância.

O armazenamento cresce automaticamente até `max_allocated_storage` (100 GiB por padrão); esse teto não é espaço garantido ilimitado. Revise o plano ao alterar limites/classe e considere os efeitos nos consumidores. Não remova dados de negócio como tentativa de corrigir indisponibilidade.

## Backup, restauração e destroy

### Backup não aparece ou uma restauração não é usada pela API

Confira retenção configurada (7 dias por padrão), estado dos backups e snapshots da instância correta. Uma instância recém-criada pode ainda não ter o histórico esperado. Uma restauração cria outro recurso/endpoint: reconcilie Terraform/state, parâmetros SSM, credencial e consumidores antes de direcionar a API. Não suponha que restaurar snapshot atualiza automaticamente os parâmetros do projeto.

### Destroy é recusado por deletion protection

A proteção é habilitada por padrão. Para uma remoção intencional, preserve o backup necessário, aplique `deletion_protection=false` com o mesmo backend e depois revise o plano de destruição. Siga o [procedimento de destroy](EXECUCAO-LAB-AWS.md#executando-destroy). Desativar proteção no console sem reconciliar o código pode ser revertido por outro apply.

### Snapshot final já existe ou remoção da VPC falha

O nome final é `oficina-ENV-postgres-final`. Uma destruição posterior pode colidir com um snapshot preservado. Escolha conscientemente preservar/renomear a estratégia de snapshot no Terraform; não apague o backup anterior automaticamente. Remova autenticação e consumidores antes do RDS, e o RDS antes da VPC. Snapshots/armazenamento de backup podem permanecer após a remoção da instância.
