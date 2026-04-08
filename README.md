# BR Financial Market Data Lake — Tech Challenge

Este projeto foi desenvolvido como proposta de solução ao Tech Challenge, especificamente ao desafio da 2ª Fase da Pós Tech em Machine Learning Engineering. O desafio consiste em extrair, processar e analisar dados de ações ou índices da [B3](https://www.b3.com.br/pt_br/institucional).

## Arquitetura

O diagrama abaixo é um esboço da arquitetura da solução implementada. Mais detalhes sobre essa arquitetura e sobre o funcionamento do Data Lake podem ser encontrados neste [vídeo](https://www.youtube.com/watch?v=15Hs9dbw-3I).

![Data Lake](/assets/tech_challenge-diagrama_arq-br_financial_market_data_lake.png)

## Deploy

Requisitos:
- [git](https://git-scm.com/)
- [AWS CLI](https://aws.amazon.com/cli/) (com credenciais configuradas)
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

Início rápido:
1. Clonar repositório: `git clone https://github.com/yuriperim/FIAP-tech_challenge-br_financial_market_data_lake.git br_financial_market_data_lake`
2. Entrar no diretório do projeto, na pasta `infra`: `cd br_financial_market_data_lake/infra`
3. Inicializar diretório de trabalho: `terraform init`
4. Criar plano de execução: `terraform plan`
5. Executar plano criando, atualizando, ou mesmo destruindo recursos na nuvem: `terraform apply -auto-approve` (flag `-auto-approve` opcional)

Obs.: para derrubar o data lake, executar `terraform destroy`

## Principais pastas e responsabilidades
- infra — arquivos Terraform para provisionamento de infraestrutura na AWS
- scripts — arquivos Python para os jobs Glue de extração e de transformação, e para a função Lambda; arquivo JSON com os tickers (códigos das ações)
