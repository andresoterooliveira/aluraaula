# App Rota: requisitos do Módulo do Gestor (V1)

Fonte: reunião "App - Rota" de 28/09/2026 (Edison Carvalho, André Sotero, Rodrigo Anjos), anotações e transcrição do Gemini.
Status: **rascunho para validação do cliente** (desenvolvimento iterativo e incremental; o módulo do gestor é a primeira entrega).

## 1. Contexto

- Hoje a geração de rotas por região leva cerca de 2 horas, com erros recorrentes e ajuste manual.
- Operação de referência: 27 representantes cobrindo cerca de 5.000 municípios; planejamento de 12 semanas com 2 visitas por dia.
- Cada município (ou bairro, conforme o segmento) deve ter um único responsável. O que não tem responsável aparece como "sem vendedor".
- O sistema terá no mínimo dois perfis: **Gestor** (parametriza a operação) e **Representante** (executa as visitas no app).
- O app será móvel (Android e iOS) por depender de GPS; o protótipo desta fase é HTML com dados fictícios.

## 2. Requisitos funcionais

| ID | Requisito | Origem |
|---|---|---|
| RF01 | Cadastrar, editar, ativar e inativar funcionários (nome, CPF, e-mail/login, telefone, perfil, cargo, CEP de partida). | 00:33:35 |
| RF02 | Vincular funcionário a território em qualquer nível: país, estado, município ou bairro, com vigência (início/fim). | 00:34:35 |
| RF03 | Buscar território digitando o nome; sugestões mostram bairro, município e UF. | 00:34:35 |
| RF04 | Impedir sobreposição: um território não pode ser atribuído a dois funcionários no mesmo período, inclusive por hierarquia (estado x município x bairro). | 00:25:06, 00:40:39 |
| RF05 | Exibir cobertura: municípios com lojas e seu responsável, destacando os "sem vendedor". | 00:40:39 |
| RF06 | Definir tempo de atendimento global da empresa (sugerido pelo segmento). | 00:35:31 |
| RF07 | Definir exceções de tempo por estado, município, bairro, funcionário ou loja. Precedência: loja > funcionário > bairro > município > estado > global. | 00:36:37 a 00:38:51 |
| RF08 | Manter status de loja: ativo, inativo, novo, reativação, journey, prospecção (padrões do sistema; gestor pode acrescentar). | 00:41:34 |
| RF09 | Manter motivos de não visita (reagendamento, logística, estrada, clima, loja fechada, imprevisto, outros). | 00:42:27 |
| RF10 | Manter motivos de não venda (estoque cheio, prazo de pagamento, markup, problema do cliente, outros). | 00:43:14 |
| RF11 | Motivos padrão vêm do produto; o gestor pode ocultá-los e criar os seus. "Outros" exige texto livre, revisado periodicamente para gerar novos motivos. | 00:43:14 a 00:44:14 |
| RF12 | Cadastrar lojas (código do cliente, CNPJ, endereço, município/bairro, coordenadas, status, ticket médio). | 00:46:12 |
| RF13 | Manter lista de marcas qualificadas e calcular a qualificação da loja: 1 marca = good, 2 = very good, 3+ = best. | 00:59:34 |
| RF14 | Configurar parâmetros de rota: horizonte (12 semanas), visitas por dia (2), dias de viagem, limite territorial padrão (país/estado/município/bairro), horário limite de deslocamento, somente cidades qualificadas, custos (km, hospedagem, alimentação). | 00:03:55, 00:06:01, 00:13:54, 00:46:12 |
| RF15 | Cadastrar a conta de IA do cliente (GPT, Claude...) como pré-requisito de uso; a credencial é armazenada cifrada. | 01:03:55 |
| RF16 | Importar bases de referência (estado, município, bairro) e carteira de lojas por planilha CSV. | 00:12:50, 00:48:35 |

## 3. Regras de negócio

- **RN01** Exclusividade territorial por empresa e período. Atribuir o estado RJ a alguém bloqueia qualquer município ou bairro do RJ para outra pessoa, e vice-versa.
- **RN02** Encerrar um vínculo (data fim) em vez de excluir, para preservar histórico de aderência e desempenho.
- **RN03** Funcionário inativo não recebe novos territórios nem rotas.
- **RN04** Sempre existe um tempo global por empresa; exceções são opcionais.
- **RN05** Raio de check-in automático padrão de 10 m da loja (usado pelo app do representante).
- **RN06** Motivos e status padrão do sistema não são editados pelo gestor, apenas ocultados.
- **RN07** Assinatura de lançamento: R$ 19,90 por 6 meses.

## 4. Requisitos não funcionais

- **RNF01** PostgreSQL como banco; dados isolados por empresa (multi-tenant).
- **RNF02** Credenciais de IA nunca em texto aberto.
- **RNF03** Busca incremental de território responde em menos de 300 ms com a base completa do IBGE.
- **RNF04** Protótipo HTML navegável publicado em nuvem para validação semanal com um representante indicado pelo cliente.

## 5. Fora do escopo desta entrega

Motor de roteirização, check-in por GPS, cronômetro de atendimento (início/fim e lançamento manual), registro da visita, gravação de áudio, painéis demográficos e relatórios de ROI. Estes itens dependem do módulo do gestor e entram nas próximas iterações.

## 6. Pontos para o cliente validar

1. A precedência de tempo coloca **loja acima de funcionário**. Confirmar.
2. Na reunião ficou em aberto quem cria os motivos: a proposta é padrão do produto + motivos próprios do gestor.
3. Um mesmo funcionário pode ter territórios de níveis diferentes (ex.: um estado inteiro e um bairro de outro estado)?
4. Qual o critério exato de cidade qualificada (PIB x população)? A regra "15 e 12" citada precisa ser detalhada.

## 7. Artefatos

- `db/01_schema.sql`: tabelas, comentários, triggers e funções.
- `db/02_seed.sql`: padrões do sistema e amostra fictícia.
- `db/03_testes.sql`: testes das regras de sobreposição, tempo e qualificação.
- `prototipo/index.html`: protótipo interativo com dados fictícios.
