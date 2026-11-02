# Tecnologias e versões — oficina-db-infra

[README](../README.md) · [Validação local e execução manual](VALIDACAO-E-EXECUCAO-MANUAL.md) · [Execução na AWS](EXECUCAO-AWS.md)

| Tecnologia | Versão / referência | Uso |
| --- | --- | --- |
| Terraform | 1.15.9 no CI; mínimo 1.10.0 | Provisionamento do banco |
| Provider AWS | 6.69.1 no lock | Constraint `~> 6.0` |
| RDS PostgreSQL | 16 por padrão | Atualizações minor automáticas habilitadas |
| AWS CLI | 2.36.34 | Ferramenta de referência para operação |
| VPC, Security Groups, Secrets Manager, SSM e S3 | Serviços gerenciados | Rede, credencial, descoberta e state |
| GitHub Actions | Serviço gerenciado | Versões das actions no workflow |

As versões fixadas no código e nos lockfiles prevalecem. As tabelas distinguem versões fixadas, faixas aceitas, valores padrão e ferramentas de referência.

## Fontes das versões

- [versions.tf](../versions.tf), [lockfile](../.terraform.lock.hcl) e [workflow](../.github/workflows/terraform.yml): Terraform e provider AWS.
- [variables.tf](../variables.tf): PostgreSQL major 16 por padrão.
- [main.tf](../main.tf): `auto_minor_version_upgrade=true`; a versão minor efetivamente instalada deve ser consultada no RDS, não inferida da versão major declarada.

As ferramentas de ambiente seguem as versões adotadas da [fase-2 da API](https://github.com/tc-organization-26/gestao-oficina-tc-1/blob/fase-2/docs/EXECUCAO.md#tecnologias-e-versões-usadas-ou-definidas-no-projeto): Docker Desktop `4.77.0`, Docker Engine `29.5.3`, Docker Compose `5.1.4`, AWS CLI `2.36.34`, kubectl `1.34.1`, Git `2.54.0.windows.1` e Insomnia `13.1.0`, conforme a ferramenta necessária para cada componente. Isso não significa que todas sejam exigidas em todos os repositórios.

Uma versão no lockfile identifica a resolução versionada; a constraint no Terraform define a faixa aceita. Uma versão major de imagem ou runtime não fixa seu patch. Serviços como GitHub Actions, GHCR, S3 e Secrets Manager não possuem uma versão de produto fixada pelo projeto.
