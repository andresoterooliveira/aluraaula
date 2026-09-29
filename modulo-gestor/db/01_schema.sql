-- =============================================================================
-- App Rota :: Módulo do Gestor (V1)
-- Modelo físico PostgreSQL (>= 14)
--
-- Origem: reunião "App - Rota" de 28/09/2026 (anotações Gemini).
-- Escopo: cadastro de funcionários (representantes), vínculo a territórios
-- sem sobreposição, tempo de atendimento por dimensão, status/motivos
-- parametrizáveis, lojas e qualificação por marcas, parâmetros de rota e
-- conta de IA do cliente.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS rota;
COMMENT ON SCHEMA rota IS 'Esquema do App Rota. Nesta versão contém as tabelas do módulo do gestor e as bases de referência territoriais.';

SET search_path TO rota, public;

-- -----------------------------------------------------------------------------
-- Tipos enumerados
-- -----------------------------------------------------------------------------
CREATE TYPE nivel_territorial AS ENUM ('PAIS', 'ESTADO', 'MUNICIPIO', 'BAIRRO');
COMMENT ON TYPE nivel_territorial IS 'Granularidade territorial, do maior (PAIS) ao menor (BAIRRO). Usada no vínculo funcionário-território e no limite territorial das rotas.';

CREATE TYPE perfil_usuario AS ENUM ('ADMIN', 'GESTOR', 'REPRESENTANTE');
COMMENT ON TYPE perfil_usuario IS 'Perfis de acesso. ADMIN = equipe do produto; GESTOR = parametriza a operação; REPRESENTANTE = executa as visitas no aplicativo.';

CREATE TYPE dimensao_tempo AS ENUM ('GLOBAL', 'ESTADO', 'MUNICIPIO', 'BAIRRO', 'FUNCIONARIO', 'LOJA');
COMMENT ON TYPE dimensao_tempo IS 'Dimensão à qual um tempo de atendimento se aplica. Precedência na resolução: LOJA > FUNCIONARIO > BAIRRO > MUNICIPIO > ESTADO > GLOBAL.';

CREATE TYPE tipo_motivo AS ENUM ('NAO_VISITA', 'NAO_VENDA');
COMMENT ON TYPE tipo_motivo IS 'Situação em que o motivo é apresentado ao representante: visita não realizada ou visita realizada sem venda.';

CREATE TYPE nivel_qualificacao_loja AS ENUM ('NAO_QUALIFICADA', 'GOOD', 'VERY_GOOD', 'BEST');
COMMENT ON TYPE nivel_qualificacao_loja IS 'Qualificação da loja pela contagem de marcas qualificadas: 0 = NAO_QUALIFICADA, 1 = GOOD, 2 = VERY_GOOD, 3 ou mais = BEST.';

CREATE TYPE provedor_ia AS ENUM ('OPENAI', 'ANTHROPIC', 'OUTRO');
COMMENT ON TYPE provedor_ia IS 'Provedor da conta de IA informada pelo cliente (ex.: GPT, Claude).';

-- -----------------------------------------------------------------------------
-- Função utilitária de auditoria
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_atualizado_em() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END $$;
COMMENT ON FUNCTION fn_set_atualizado_em() IS 'Trigger genérica que atualiza a coluna atualizado_em em todo UPDATE.';

-- =============================================================================
-- 1. BASES DE REFERÊNCIA TERRITORIAL (pré-carregadas, ex.: IBGE)
-- =============================================================================
CREATE TABLE pais (
  id          smallint PRIMARY KEY,
  sigla       char(2)      NOT NULL UNIQUE,
  nome        varchar(80)  NOT NULL
);
COMMENT ON TABLE  pais IS 'Base de referência de países. Maior nível territorial do sistema.';
COMMENT ON COLUMN pais.id    IS 'Identificador do país (código numérico, ex.: 1058 = Brasil no IBGE/BACEN).';
COMMENT ON COLUMN pais.sigla IS 'Sigla ISO 3166-1 alfa-2 (ex.: BR).';
COMMENT ON COLUMN pais.nome  IS 'Nome do país.';

CREATE TABLE estado (
  id          smallint PRIMARY KEY,
  pais_id     smallint     NOT NULL REFERENCES pais(id),
  uf          char(2)      NOT NULL UNIQUE,
  nome        varchar(60)  NOT NULL
);
COMMENT ON TABLE  estado IS 'Base de referência de estados (UF), carregada a partir do IBGE.';
COMMENT ON COLUMN estado.id      IS 'Código IBGE da UF (ex.: 33 = RJ).';
COMMENT ON COLUMN estado.pais_id IS 'País ao qual o estado pertence.';
COMMENT ON COLUMN estado.uf      IS 'Sigla da unidade federativa (ex.: RJ).';
COMMENT ON COLUMN estado.nome    IS 'Nome do estado.';

CREATE TABLE municipio (
  id                 integer PRIMARY KEY,
  estado_id          smallint      NOT NULL REFERENCES estado(id),
  nome               varchar(120)  NOT NULL,
  populacao          integer,
  pib_mil_reais      numeric(16,2),
  pib_per_capita     numeric(12,2),
  renda_media        numeric(12,2),
  qualificado        boolean       NOT NULL DEFAULT false,
  qualificado_em     timestamptz,
  latitude           numeric(9,6),
  longitude          numeric(9,6),
  UNIQUE (estado_id, nome)
);
COMMENT ON TABLE  municipio IS 'Base de referência de municípios (IBGE) com indicadores socioeconômicos usados na qualificação de cidades.';
COMMENT ON COLUMN municipio.id             IS 'Código IBGE de 7 dígitos do município (ex.: 3301900 = Itaboraí).';
COMMENT ON COLUMN municipio.estado_id      IS 'Estado ao qual o município pertence.';
COMMENT ON COLUMN municipio.nome           IS 'Nome oficial do município.';
COMMENT ON COLUMN municipio.populacao      IS 'População estimada mais recente.';
COMMENT ON COLUMN municipio.pib_mil_reais  IS 'PIB municipal em milhares de reais.';
COMMENT ON COLUMN municipio.pib_per_capita IS 'PIB per capita em reais.';
COMMENT ON COLUMN municipio.renda_media    IS 'Renda média domiciliar per capita em reais, atualizável via prompt de IA.';
COMMENT ON COLUMN municipio.qualificado    IS 'Indica se a cidade é qualificada (critério PIB x população). Cidades não qualificadas podem entrar na rota por decisão do gestor.';
COMMENT ON COLUMN municipio.qualificado_em IS 'Data/hora da última qualificação calculada.';
COMMENT ON COLUMN municipio.latitude       IS 'Latitude da sede municipal (WGS84).';
COMMENT ON COLUMN municipio.longitude      IS 'Longitude da sede municipal (WGS84).';

CREATE TABLE bairro (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  municipio_id  integer       NOT NULL REFERENCES municipio(id),
  nome          varchar(120)  NOT NULL,
  UNIQUE (municipio_id, nome)
);
COMMENT ON TABLE  bairro IS 'Base de referência de bairros. Menor nível territorial do sistema.';
COMMENT ON COLUMN bairro.id           IS 'Identificador interno do bairro.';
COMMENT ON COLUMN bairro.municipio_id IS 'Município ao qual o bairro pertence.';
COMMENT ON COLUMN bairro.nome         IS 'Nome do bairro.';

CREATE INDEX ix_bairro_nome_busca ON bairro (lower(nome) varchar_pattern_ops);
COMMENT ON INDEX ix_bairro_nome_busca IS 'Apoia a busca incremental por nome de bairro (digitar e sugerir) na tela de territórios.';
CREATE INDEX ix_municipio_nome_busca ON municipio (lower(nome) varchar_pattern_ops);
COMMENT ON INDEX ix_municipio_nome_busca IS 'Apoia a busca incremental por nome de município na tela de territórios.';

-- =============================================================================
-- 2. EMPRESA (cliente/assinante), SEGMENTO E USUÁRIOS
-- =============================================================================
CREATE TABLE segmento (
  id                        smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nome                      varchar(60)  NOT NULL UNIQUE,
  tempo_sugerido_min        integer      NOT NULL CHECK (tempo_sugerido_min > 0),
  nivel_territorial_sugerido nivel_territorial NOT NULL DEFAULT 'MUNICIPIO'
);
COMMENT ON TABLE  segmento IS 'Segmentos de mercado atendidos (vestuário, farmácia, bebidas...). Fornece valores sugeridos na criação da empresa.';
COMMENT ON COLUMN segmento.id                         IS 'Identificador do segmento.';
COMMENT ON COLUMN segmento.nome                       IS 'Nome do segmento.';
COMMENT ON COLUMN segmento.tempo_sugerido_min         IS 'Tempo médio de atendimento sugerido para o segmento, em minutos (ex.: 15 para bebidas, 120 para vestuário).';
COMMENT ON COLUMN segmento.nivel_territorial_sugerido IS 'Granularidade territorial típica do segmento (ex.: BAIRRO para farmácias, MUNICIPIO para vestuário).';

CREATE TABLE empresa (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  razao_social    varchar(150) NOT NULL,
  nome_fantasia   varchar(150),
  cnpj            char(14)     UNIQUE,
  segmento_id     smallint     NOT NULL REFERENCES segmento(id),
  ativa           boolean      NOT NULL DEFAULT true,
  assinatura_valor numeric(10,2) NOT NULL DEFAULT 19.90,
  assinatura_meses smallint    NOT NULL DEFAULT 6,
  assinatura_inicio date,
  criado_em       timestamptz  NOT NULL DEFAULT now(),
  atualizado_em   timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE  empresa IS 'Empresa cliente (tenant). Todos os cadastros do gestor são isolados por empresa.';
COMMENT ON COLUMN empresa.id                IS 'Identificador da empresa.';
COMMENT ON COLUMN empresa.razao_social      IS 'Razão social.';
COMMENT ON COLUMN empresa.nome_fantasia     IS 'Nome fantasia exibido no aplicativo.';
COMMENT ON COLUMN empresa.cnpj              IS 'CNPJ somente com dígitos.';
COMMENT ON COLUMN empresa.segmento_id       IS 'Segmento de mercado principal da empresa.';
COMMENT ON COLUMN empresa.ativa             IS 'Indica se a empresa pode acessar o sistema.';
COMMENT ON COLUMN empresa.assinatura_valor  IS 'Valor da assinatura no período (lançamento: R$ 19,90).';
COMMENT ON COLUMN empresa.assinatura_meses  IS 'Duração do período de assinatura em meses (lançamento: 6).';
COMMENT ON COLUMN empresa.assinatura_inicio IS 'Data de início da assinatura vigente.';
COMMENT ON COLUMN empresa.criado_em         IS 'Data/hora de criação do registro.';
COMMENT ON COLUMN empresa.atualizado_em     IS 'Data/hora da última alteração.';
CREATE TRIGGER tg_empresa_atualizado BEFORE UPDATE ON empresa FOR EACH ROW EXECUTE FUNCTION fn_set_atualizado_em();

CREATE TABLE funcionario (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id       bigint       NOT NULL REFERENCES empresa(id),
  nome             varchar(120) NOT NULL,
  cpf              char(11),
  email            varchar(160) NOT NULL,
  telefone         varchar(20),
  perfil           perfil_usuario NOT NULL DEFAULT 'REPRESENTANTE',
  cargo            varchar(80),
  cep_partida      char(8),
  ativo            boolean      NOT NULL DEFAULT true,
  data_admissao    date,
  criado_em        timestamptz  NOT NULL DEFAULT now(),
  atualizado_em    timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, email),
  UNIQUE (empresa_id, cpf),
  CHECK (cep_partida ~ '^[0-9]{8}$'),
  CHECK (cpf ~ '^[0-9]{11}$')
);
COMMENT ON TABLE  funcionario IS 'Pessoas da empresa com acesso ao app: gestores e representantes (vendedores). Cadastrados pelo gestor.';
COMMENT ON COLUMN funcionario.id            IS 'Identificador do funcionário.';
COMMENT ON COLUMN funcionario.empresa_id    IS 'Empresa à qual o funcionário pertence.';
COMMENT ON COLUMN funcionario.nome          IS 'Nome completo.';
COMMENT ON COLUMN funcionario.cpf           IS 'CPF somente com dígitos.';
COMMENT ON COLUMN funcionario.email         IS 'E-mail, usado como login no aplicativo.';
COMMENT ON COLUMN funcionario.telefone      IS 'Telefone/WhatsApp de contato.';
COMMENT ON COLUMN funcionario.perfil        IS 'Perfil de acesso (GESTOR ou REPRESENTANTE).';
COMMENT ON COLUMN funcionario.cargo         IS 'Cargo livre (ex.: Representante Regional).';
COMMENT ON COLUMN funcionario.cep_partida   IS 'CEP padrão de partida das rotas (normalmente a residência do representante).';
COMMENT ON COLUMN funcionario.ativo         IS 'Funcionário inativo não recebe rotas nem territórios novos.';
COMMENT ON COLUMN funcionario.data_admissao IS 'Data de admissão/início na operação.';
COMMENT ON COLUMN funcionario.criado_em     IS 'Data/hora de criação do registro.';
COMMENT ON COLUMN funcionario.atualizado_em IS 'Data/hora da última alteração.';
CREATE TRIGGER tg_funcionario_atualizado BEFORE UPDATE ON funcionario FOR EACH ROW EXECUTE FUNCTION fn_set_atualizado_em();

CREATE TABLE conta_ia (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id       bigint       NOT NULL REFERENCES empresa(id),
  provedor         provedor_ia  NOT NULL,
  modelo           varchar(80),
  identificacao    varchar(160) NOT NULL,
  credencial_cifrada bytea      NOT NULL,
  nivel_esforco    varchar(20)  NOT NULL DEFAULT 'medio' CHECK (nivel_esforco IN ('baixo','medio','alto')),
  ativa            boolean      NOT NULL DEFAULT true,
  validada_em      timestamptz,
  criado_em        timestamptz  NOT NULL DEFAULT now(),
  atualizado_em    timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE  conta_ia IS 'Conta de IA do próprio cliente (GPT, Claude...). Obrigatória para usar o sistema: o custo de processamento é do cliente.';
COMMENT ON COLUMN conta_ia.id                 IS 'Identificador da conta.';
COMMENT ON COLUMN conta_ia.empresa_id         IS 'Empresa dona da conta.';
COMMENT ON COLUMN conta_ia.provedor           IS 'Provedor da IA.';
COMMENT ON COLUMN conta_ia.modelo             IS 'Modelo preferencial configurado.';
COMMENT ON COLUMN conta_ia.identificacao      IS 'Identificação exibível da conta (e-mail ou apelido da chave), sem o segredo.';
COMMENT ON COLUMN conta_ia.credencial_cifrada IS 'Chave/token de API cifrado pela aplicação. Nunca armazenar em texto aberto.';
COMMENT ON COLUMN conta_ia.nivel_esforco      IS 'Nível de esforço de raciocínio usado nos prompts (impacta profundidade e custo).';
COMMENT ON COLUMN conta_ia.ativa              IS 'Conta em uso. Apenas uma conta ativa por empresa.';
COMMENT ON COLUMN conta_ia.validada_em        IS 'Última validação bem-sucedida da credencial junto ao provedor.';
COMMENT ON COLUMN conta_ia.criado_em          IS 'Data/hora de criação do registro.';
COMMENT ON COLUMN conta_ia.atualizado_em      IS 'Data/hora da última alteração.';
CREATE UNIQUE INDEX ux_conta_ia_ativa ON conta_ia (empresa_id) WHERE ativa;
COMMENT ON INDEX ux_conta_ia_ativa IS 'Garante no máximo uma conta de IA ativa por empresa.';
CREATE TRIGGER tg_conta_ia_atualizado BEFORE UPDATE ON conta_ia FOR EACH ROW EXECUTE FUNCTION fn_set_atualizado_em();

-- =============================================================================
-- 3. TERRITÓRIOS: vínculo funcionário x território, sem sobreposição
-- =============================================================================
CREATE TABLE funcionario_territorio (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id     bigint            NOT NULL REFERENCES empresa(id),
  funcionario_id bigint            NOT NULL REFERENCES funcionario(id),
  nivel          nivel_territorial NOT NULL,
  pais_id        smallint          REFERENCES pais(id),
  estado_id      smallint          REFERENCES estado(id),
  municipio_id   integer           REFERENCES municipio(id),
  bairro_id      bigint            REFERENCES bairro(id),
  vigencia_inicio date             NOT NULL DEFAULT current_date,
  vigencia_fim    date,
  observacao     varchar(255),
  criado_por     bigint            REFERENCES funcionario(id),
  criado_em      timestamptz       NOT NULL DEFAULT now(),
  CHECK (vigencia_fim IS NULL OR vigencia_fim >= vigencia_inicio),
  CHECK ( (nivel = 'PAIS'      AND pais_id IS NOT NULL AND estado_id IS NULL AND municipio_id IS NULL AND bairro_id IS NULL)
       OR (nivel = 'ESTADO'    AND estado_id IS NOT NULL AND municipio_id IS NULL AND bairro_id IS NULL)
       OR (nivel = 'MUNICIPIO' AND municipio_id IS NOT NULL AND bairro_id IS NULL)
       OR (nivel = 'BAIRRO'    AND bairro_id IS NOT NULL) )
);
COMMENT ON TABLE  funcionario_territorio IS 'Área de atuação exclusiva de cada funcionário. Um território (e seus sub/supra-territórios) não pode estar com dois funcionários no mesmo período.';
COMMENT ON COLUMN funcionario_territorio.id              IS 'Identificador do vínculo.';
COMMENT ON COLUMN funcionario_territorio.empresa_id      IS 'Empresa do vínculo. A exclusividade vale dentro da empresa.';
COMMENT ON COLUMN funcionario_territorio.funcionario_id  IS 'Funcionário responsável pelo território.';
COMMENT ON COLUMN funcionario_territorio.nivel           IS 'Nível do território vinculado (PAIS, ESTADO, MUNICIPIO ou BAIRRO).';
COMMENT ON COLUMN funcionario_territorio.pais_id         IS 'País (preenchido para qualquer nível, derivado automaticamente).';
COMMENT ON COLUMN funcionario_territorio.estado_id       IS 'Estado vinculado ou ancestral do município/bairro (derivado automaticamente).';
COMMENT ON COLUMN funcionario_territorio.municipio_id    IS 'Município vinculado ou ancestral do bairro (derivado automaticamente).';
COMMENT ON COLUMN funcionario_territorio.bairro_id       IS 'Bairro vinculado quando nivel = BAIRRO.';
COMMENT ON COLUMN funcionario_territorio.vigencia_inicio IS 'Início da responsabilidade pelo território.';
COMMENT ON COLUMN funcionario_territorio.vigencia_fim    IS 'Fim da responsabilidade. NULL = vigente por tempo indeterminado. Encerrar em vez de apagar preserva o histórico de métricas.';
COMMENT ON COLUMN funcionario_territorio.observacao      IS 'Observação livre do gestor.';
COMMENT ON COLUMN funcionario_territorio.criado_por      IS 'Gestor que criou o vínculo.';
COMMENT ON COLUMN funcionario_territorio.criado_em       IS 'Data/hora de criação do registro.';

CREATE INDEX ix_ft_empresa_estado ON funcionario_territorio (empresa_id, estado_id);
COMMENT ON INDEX ix_ft_empresa_estado IS 'Acelera a checagem de sobreposição e o relatório de cobertura por estado.';
CREATE INDEX ix_ft_funcionario ON funcionario_territorio (funcionario_id);
COMMENT ON INDEX ix_ft_funcionario IS 'Lista os territórios de um funcionário.';

CREATE OR REPLACE FUNCTION fn_funcionario_territorio_validar() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_conflito record;
BEGIN
  -- 1) Deriva a hierarquia a partir do nível informado
  IF NEW.nivel = 'BAIRRO' THEN
    SELECT b.municipio_id, m.estado_id INTO NEW.municipio_id, NEW.estado_id
      FROM bairro b JOIN municipio m ON m.id = b.municipio_id WHERE b.id = NEW.bairro_id;
  ELSIF NEW.nivel = 'MUNICIPIO' THEN
    SELECT m.estado_id INTO NEW.estado_id FROM municipio m WHERE m.id = NEW.municipio_id;
  END IF;
  IF NEW.nivel <> 'PAIS' THEN
    SELECT e.pais_id INTO NEW.pais_id FROM estado e WHERE e.id = NEW.estado_id;
  END IF;

  -- 2) Funcionário deve ser da mesma empresa
  IF NOT EXISTS (SELECT 1 FROM funcionario f WHERE f.id = NEW.funcionario_id AND f.empresa_id = NEW.empresa_id) THEN
    RAISE EXCEPTION 'Funcionário % não pertence à empresa %', NEW.funcionario_id, NEW.empresa_id;
  END IF;

  -- 3) Serializa alterações de território da mesma empresa
  PERFORM pg_advisory_xact_lock(hashtextextended('rota.funcionario_territorio', NEW.empresa_id));

  -- 4) Sobreposição: mesmo território, ancestral ou descendente com período coincidente
  SELECT ft.id, ft.funcionario_id, f.nome INTO v_conflito
    FROM funcionario_territorio ft
    JOIN funcionario f ON f.id = ft.funcionario_id
   WHERE ft.empresa_id = NEW.empresa_id
     AND ft.id IS DISTINCT FROM NEW.id
     AND daterange(ft.vigencia_inicio, ft.vigencia_fim, '[]') && daterange(NEW.vigencia_inicio, NEW.vigencia_fim, '[]')
     AND ft.pais_id = NEW.pais_id
     AND ( ft.nivel = 'PAIS' OR NEW.nivel = 'PAIS'
        OR ( ft.estado_id = NEW.estado_id
             AND ( ft.nivel = 'ESTADO' OR NEW.nivel = 'ESTADO'
                OR ( ft.municipio_id = NEW.municipio_id
                     AND ( ft.nivel = 'MUNICIPIO' OR NEW.nivel = 'MUNICIPIO'
                        OR ft.bairro_id = NEW.bairro_id ) ) ) ) )
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'Sobreposição de território: área já atribuída a % (vínculo %)', v_conflito.nome, v_conflito.id
      USING ERRCODE = 'exclusion_violation';
  END IF;
  RETURN NEW;
END $$;
COMMENT ON FUNCTION fn_funcionario_territorio_validar() IS 'Deriva estado/município/país do território e impede sobreposição (igual, ancestral ou descendente) com período coincidente dentro da empresa.';

CREATE TRIGGER tg_funcionario_territorio_validar
  BEFORE INSERT OR UPDATE ON funcionario_territorio
  FOR EACH ROW EXECUTE FUNCTION fn_funcionario_territorio_validar();

-- =============================================================================
-- 4. LOJAS, MARCAS E QUALIFICAÇÃO
-- =============================================================================
CREATE TABLE status_loja (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id   bigint       REFERENCES empresa(id),
  codigo       varchar(30)  NOT NULL,
  descricao    varchar(80)  NOT NULL,
  cor_hex      char(7)      NOT NULL DEFAULT '#6B7280' CHECK (cor_hex ~ '^#[0-9A-Fa-f]{6}$'),
  ordem        smallint     NOT NULL DEFAULT 0,
  ativo        boolean      NOT NULL DEFAULT true,
  UNIQUE NULLS NOT DISTINCT (empresa_id, codigo)
);
COMMENT ON TABLE  status_loja IS 'Status comercial da loja (ativo, inativo, novo, reativação, journey, prospecção). empresa_id NULL = padrão do sistema, visível a todas as empresas.';
COMMENT ON COLUMN status_loja.id         IS 'Identificador do status.';
COMMENT ON COLUMN status_loja.empresa_id IS 'Empresa que criou o status. NULL = status padrão do sistema (não editável pelo gestor).';
COMMENT ON COLUMN status_loja.codigo     IS 'Código estável do status (ex.: JOURNEY).';
COMMENT ON COLUMN status_loja.descricao  IS 'Texto exibido (ex.: Journey - pulou uma coleção).';
COMMENT ON COLUMN status_loja.cor_hex    IS 'Cor do selo na interface.';
COMMENT ON COLUMN status_loja.ordem      IS 'Ordem de exibição.';
COMMENT ON COLUMN status_loja.ativo      IS 'Status disponível para seleção.';

CREATE TABLE marca (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id   bigint       NOT NULL REFERENCES empresa(id),
  nome         varchar(80)  NOT NULL,
  qualificada  boolean      NOT NULL DEFAULT true,
  UNIQUE (empresa_id, nome)
);
COMMENT ON TABLE  marca IS 'Marcas observadas nas lojas. As marcas qualificadas (ex.: Adidas, Nike, Fila) definem o nível de qualificação da loja.';
COMMENT ON COLUMN marca.id          IS 'Identificador da marca.';
COMMENT ON COLUMN marca.empresa_id  IS 'Empresa que mantém a lista de marcas.';
COMMENT ON COLUMN marca.nome        IS 'Nome da marca.';
COMMENT ON COLUMN marca.qualificada IS 'Se a marca conta para a qualificação da loja (marca premium do segmento).';

CREATE TABLE loja (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id         bigint        NOT NULL REFERENCES empresa(id),
  codigo_cliente     varchar(30),
  nome               varchar(150)  NOT NULL,
  cnpj               char(14),
  logradouro         varchar(200),
  numero             varchar(20),
  cep                char(8),
  bairro_id          bigint        REFERENCES bairro(id),
  municipio_id       integer       NOT NULL REFERENCES municipio(id),
  latitude           numeric(9,6),
  longitude          numeric(9,6),
  raio_checkin_m     smallint      NOT NULL DEFAULT 10 CHECK (raio_checkin_m BETWEEN 5 AND 500),
  status_loja_id     bigint        REFERENCES status_loja(id),
  ticket_medio       numeric(12,2),
  qualificacao       nivel_qualificacao_loja NOT NULL DEFAULT 'NAO_QUALIFICADA',
  qualificacao_origem varchar(10)  NOT NULL DEFAULT 'MANUAL' CHECK (qualificacao_origem IN ('MANUAL','IA')),
  ativo              boolean       NOT NULL DEFAULT true,
  criado_em          timestamptz   NOT NULL DEFAULT now(),
  atualizado_em      timestamptz   NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, codigo_cliente)
);
COMMENT ON TABLE  loja IS 'Lojas/pontos de venda que compõem as rotas. Podem ser importadas por planilha ou mapeadas por IA.';
COMMENT ON COLUMN loja.id                  IS 'Identificador da loja.';
COMMENT ON COLUMN loja.empresa_id          IS 'Empresa dona da carteira.';
COMMENT ON COLUMN loja.codigo_cliente      IS 'Código do cliente no ERP da empresa.';
COMMENT ON COLUMN loja.nome                IS 'Nome fantasia da loja.';
COMMENT ON COLUMN loja.cnpj                IS 'CNPJ somente com dígitos.';
COMMENT ON COLUMN loja.logradouro          IS 'Rua/avenida.';
COMMENT ON COLUMN loja.numero              IS 'Número do endereço.';
COMMENT ON COLUMN loja.cep                 IS 'CEP somente com dígitos.';
COMMENT ON COLUMN loja.bairro_id           IS 'Bairro da loja (base de referência).';
COMMENT ON COLUMN loja.municipio_id        IS 'Município da loja (obrigatório para cobertura territorial).';
COMMENT ON COLUMN loja.latitude            IS 'Latitude para roteirização e check-in por GPS.';
COMMENT ON COLUMN loja.longitude           IS 'Longitude para roteirização e check-in por GPS.';
COMMENT ON COLUMN loja.raio_checkin_m      IS 'Raio em metros que dispara o início automático do atendimento (padrão 10 m).';
COMMENT ON COLUMN loja.status_loja_id      IS 'Status comercial atual da loja.';
COMMENT ON COLUMN loja.ticket_medio        IS 'Ticket médio de compra da loja em reais.';
COMMENT ON COLUMN loja.qualificacao        IS 'Nível de qualificação (GOOD, VERY_GOOD, BEST) pela contagem de marcas qualificadas.';
COMMENT ON COLUMN loja.qualificacao_origem IS 'Origem da qualificação: MANUAL (gestor) ou IA (prompt de qualificação).';
COMMENT ON COLUMN loja.ativo               IS 'Loja considerada na geração de rotas.';
COMMENT ON COLUMN loja.criado_em           IS 'Data/hora de criação do registro.';
COMMENT ON COLUMN loja.atualizado_em       IS 'Data/hora da última alteração.';
CREATE INDEX ix_loja_municipio ON loja (empresa_id, municipio_id);
COMMENT ON INDEX ix_loja_municipio IS 'Consulta de lojas por município (cobertura e roteirização).';
CREATE TRIGGER tg_loja_atualizado BEFORE UPDATE ON loja FOR EACH ROW EXECUTE FUNCTION fn_set_atualizado_em();

CREATE TABLE loja_marca (
  loja_id   bigint NOT NULL REFERENCES loja(id) ON DELETE CASCADE,
  marca_id  bigint NOT NULL REFERENCES marca(id),
  PRIMARY KEY (loja_id, marca_id)
);
COMMENT ON TABLE  loja_marca IS 'Marcas comercializadas por cada loja. Base para o cálculo automático da qualificação.';
COMMENT ON COLUMN loja_marca.loja_id  IS 'Loja.';
COMMENT ON COLUMN loja_marca.marca_id IS 'Marca encontrada na loja.';

CREATE OR REPLACE FUNCTION fn_qualificacao_por_marcas(p_qtd integer) RETURNS nivel_qualificacao_loja
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_qtd >= 3 THEN 'BEST'::nivel_qualificacao_loja
              WHEN p_qtd = 2  THEN 'VERY_GOOD'
              WHEN p_qtd = 1  THEN 'GOOD'
              ELSE 'NAO_QUALIFICADA' END
$$;
COMMENT ON FUNCTION fn_qualificacao_por_marcas(integer) IS 'Regra da reunião: 1 marca qualificada = GOOD, 2 = VERY_GOOD, 3 ou mais = BEST.';

CREATE OR REPLACE VIEW vw_loja_qualificacao AS
SELECT l.id AS loja_id, l.empresa_id, l.nome,
       count(m.id) FILTER (WHERE m.qualificada) AS marcas_qualificadas,
       fn_qualificacao_por_marcas((count(m.id) FILTER (WHERE m.qualificada))::int) AS qualificacao_calculada
  FROM loja l
  LEFT JOIN loja_marca lm ON lm.loja_id = l.id
  LEFT JOIN marca m ON m.id = lm.marca_id
 GROUP BY l.id;
COMMENT ON VIEW vw_loja_qualificacao IS 'Qualificação calculada de cada loja a partir das marcas qualificadas cadastradas.';

-- =============================================================================
-- 5. TEMPO DE ATENDIMENTO (global com exceções por dimensão)
-- =============================================================================
CREATE TABLE tempo_atendimento (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id     bigint         NOT NULL REFERENCES empresa(id),
  dimensao       dimensao_tempo NOT NULL,
  estado_id      smallint       REFERENCES estado(id),
  municipio_id   integer        REFERENCES municipio(id),
  bairro_id      bigint         REFERENCES bairro(id),
  funcionario_id bigint         REFERENCES funcionario(id),
  loja_id        bigint         REFERENCES loja(id),
  minutos        integer        NOT NULL CHECK (minutos BETWEEN 1 AND 1440),
  observacao     varchar(255),
  criado_em      timestamptz    NOT NULL DEFAULT now(),
  atualizado_em  timestamptz    NOT NULL DEFAULT now(),
  CHECK ( num_nonnulls(estado_id, municipio_id, bairro_id, funcionario_id, loja_id) =
          CASE WHEN dimensao = 'GLOBAL' THEN 0 ELSE 1 END ),
  CHECK ( (dimensao <> 'ESTADO'      OR estado_id      IS NOT NULL)
      AND (dimensao <> 'MUNICIPIO'   OR municipio_id   IS NOT NULL)
      AND (dimensao <> 'BAIRRO'      OR bairro_id      IS NOT NULL)
      AND (dimensao <> 'FUNCIONARIO' OR funcionario_id IS NOT NULL)
      AND (dimensao <> 'LOJA'        OR loja_id        IS NOT NULL) )
);
COMMENT ON TABLE  tempo_atendimento IS 'Tempo previsto de atendimento por visita. Uma linha GLOBAL obrigatória por empresa e exceções opcionais por estado, município, bairro, funcionário ou loja.';
COMMENT ON COLUMN tempo_atendimento.id             IS 'Identificador do parâmetro.';
COMMENT ON COLUMN tempo_atendimento.empresa_id     IS 'Empresa dona do parâmetro.';
COMMENT ON COLUMN tempo_atendimento.dimensao       IS 'Dimensão da regra. Resolução por precedência: LOJA > FUNCIONARIO > BAIRRO > MUNICIPIO > ESTADO > GLOBAL.';
COMMENT ON COLUMN tempo_atendimento.estado_id      IS 'Estado alvo quando dimensao = ESTADO.';
COMMENT ON COLUMN tempo_atendimento.municipio_id   IS 'Município alvo quando dimensao = MUNICIPIO.';
COMMENT ON COLUMN tempo_atendimento.bairro_id      IS 'Bairro alvo quando dimensao = BAIRRO.';
COMMENT ON COLUMN tempo_atendimento.funcionario_id IS 'Funcionário alvo quando dimensao = FUNCIONARIO.';
COMMENT ON COLUMN tempo_atendimento.loja_id        IS 'Loja alvo quando dimensao = LOJA.';
COMMENT ON COLUMN tempo_atendimento.minutos        IS 'Tempo de atendimento em minutos.';
COMMENT ON COLUMN tempo_atendimento.observacao     IS 'Justificativa da exceção.';
COMMENT ON COLUMN tempo_atendimento.criado_em      IS 'Data/hora de criação do registro.';
COMMENT ON COLUMN tempo_atendimento.atualizado_em  IS 'Data/hora da última alteração.';
CREATE UNIQUE INDEX ux_tempo_atendimento_alvo ON tempo_atendimento
  (empresa_id, dimensao, coalesce(estado_id,0), coalesce(municipio_id,0), coalesce(bairro_id,0), coalesce(funcionario_id,0), coalesce(loja_id,0));
COMMENT ON INDEX ux_tempo_atendimento_alvo IS 'Uma única regra por alvo (e uma única GLOBAL) por empresa.';
CREATE TRIGGER tg_tempo_atendimento_atualizado BEFORE UPDATE ON tempo_atendimento FOR EACH ROW EXECUTE FUNCTION fn_set_atualizado_em();

CREATE OR REPLACE FUNCTION fn_tempo_atendimento(p_loja_id bigint, p_funcionario_id bigint DEFAULT NULL)
RETURNS TABLE (minutos integer, dimensao dimensao_tempo)
LANGUAGE sql STABLE AS $$
  SELECT t.minutos, t.dimensao
    FROM loja l
    JOIN municipio m ON m.id = l.municipio_id
    JOIN tempo_atendimento t ON t.empresa_id = l.empresa_id
   WHERE l.id = p_loja_id
     AND (  (t.dimensao = 'LOJA'        AND t.loja_id        = l.id)
         OR (t.dimensao = 'FUNCIONARIO' AND t.funcionario_id = p_funcionario_id)
         OR (t.dimensao = 'BAIRRO'      AND t.bairro_id      = l.bairro_id)
         OR (t.dimensao = 'MUNICIPIO'   AND t.municipio_id   = l.municipio_id)
         OR (t.dimensao = 'ESTADO'      AND t.estado_id      = m.estado_id)
         OR  t.dimensao = 'GLOBAL')
   ORDER BY CASE t.dimensao WHEN 'LOJA' THEN 1 WHEN 'FUNCIONARIO' THEN 2 WHEN 'BAIRRO' THEN 3
                            WHEN 'MUNICIPIO' THEN 4 WHEN 'ESTADO' THEN 5 ELSE 6 END
   LIMIT 1
$$;
COMMENT ON FUNCTION fn_tempo_atendimento(bigint, bigint) IS 'Resolve o tempo de atendimento de uma loja (opcionalmente para um funcionário) pela regra mais específica cadastrada, retornando também a dimensão aplicada.';

-- =============================================================================
-- 6. MOTIVOS DE NÃO VISITA / NÃO VENDA
-- =============================================================================
CREATE TABLE motivo (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id          bigint       REFERENCES empresa(id),
  tipo                tipo_motivo  NOT NULL,
  descricao           varchar(120) NOT NULL,
  exige_texto_livre   boolean      NOT NULL DEFAULT false,
  ordem               smallint     NOT NULL DEFAULT 0,
  ativo               boolean      NOT NULL DEFAULT true,
  UNIQUE NULLS NOT DISTINCT (empresa_id, tipo, descricao)
);
COMMENT ON TABLE  motivo IS 'Motivos pré-definidos apresentados ao representante quando não visita a loja ou visita sem vender. empresa_id NULL = lista padrão do sistema.';
COMMENT ON COLUMN motivo.id                IS 'Identificador do motivo.';
COMMENT ON COLUMN motivo.empresa_id        IS 'Empresa que criou o motivo. NULL = motivo padrão fornecido pelo produto.';
COMMENT ON COLUMN motivo.tipo              IS 'NAO_VISITA (ex.: clima, estrada, loja fechada) ou NAO_VENDA (ex.: estoque cheio, prazo de pagamento, markup).';
COMMENT ON COLUMN motivo.descricao         IS 'Texto do motivo exibido no aplicativo.';
COMMENT ON COLUMN motivo.exige_texto_livre IS 'Quando verdadeiro, o representante descreve o motivo (opção "Outros"). Esses textos são revisados periodicamente para criar novos motivos.';
COMMENT ON COLUMN motivo.ordem             IS 'Ordem de exibição.';
COMMENT ON COLUMN motivo.ativo             IS 'Motivo disponível para seleção. A empresa pode ocultar um motivo padrão por meio de motivo_empresa_oculto.';

CREATE TABLE motivo_empresa_oculto (
  empresa_id bigint NOT NULL REFERENCES empresa(id),
  motivo_id  bigint NOT NULL REFERENCES motivo(id),
  PRIMARY KEY (empresa_id, motivo_id)
);
COMMENT ON TABLE  motivo_empresa_oculto IS 'Motivos padrão do sistema que o gestor optou por não exibir aos seus representantes.';
COMMENT ON COLUMN motivo_empresa_oculto.empresa_id IS 'Empresa que ocultou o motivo.';
COMMENT ON COLUMN motivo_empresa_oculto.motivo_id  IS 'Motivo padrão ocultado.';

-- =============================================================================
-- 7. PARÂMETROS DE ROTA DA EMPRESA
-- =============================================================================
CREATE TABLE parametro_rota (
  empresa_id               bigint PRIMARY KEY REFERENCES empresa(id),
  horizonte_semanas        smallint          NOT NULL DEFAULT 12 CHECK (horizonte_semanas BETWEEN 1 AND 52),
  visitas_por_dia          smallint          NOT NULL DEFAULT 2  CHECK (visitas_por_dia BETWEEN 1 AND 50),
  dias_viagem_padrao       smallint          NOT NULL DEFAULT 2  CHECK (dias_viagem_padrao BETWEEN 1 AND 30),
  limite_territorial_padrao nivel_territorial NOT NULL DEFAULT 'MUNICIPIO',
  hora_inicio_jornada      time              NOT NULL DEFAULT '08:00',
  hora_limite_deslocamento time              NOT NULL DEFAULT '19:00',
  intervalo_entre_visitas_min integer        NOT NULL DEFAULT 30 CHECK (intervalo_entre_visitas_min >= 0),
  somente_cidades_qualificadas boolean       NOT NULL DEFAULT true,
  custo_km               numeric(8,2),
  custo_hospedagem_diaria numeric(10,2),
  custo_alimentacao_diaria numeric(10,2),
  atualizado_em          timestamptz         NOT NULL DEFAULT now(),
  CHECK (hora_limite_deslocamento > hora_inicio_jornada)
);
COMMENT ON TABLE  parametro_rota IS 'Parâmetros padrão usados pelo motor de rotas da empresa. O representante pode ajustar alguns deles ao gerar a rota.';
COMMENT ON COLUMN parametro_rota.empresa_id                   IS 'Empresa (um registro por empresa).';
COMMENT ON COLUMN parametro_rota.horizonte_semanas            IS 'Janela de planejamento em semanas para cobrir todas as cidades qualificadas (padrão 12).';
COMMENT ON COLUMN parametro_rota.visitas_por_dia              IS 'Quantidade de visitas planejadas por dia (padrão 2).';
COMMENT ON COLUMN parametro_rota.dias_viagem_padrao           IS 'Dias de viagem sugeridos por roteiro.';
COMMENT ON COLUMN parametro_rota.limite_territorial_padrao    IS 'Limite territorial sugerido ao gerar rota a partir do CEP de partida (PAIS, ESTADO, MUNICIPIO ou BAIRRO).';
COMMENT ON COLUMN parametro_rota.hora_inicio_jornada          IS 'Horário de início da jornada.';
COMMENT ON COLUMN parametro_rota.hora_limite_deslocamento     IS 'Horário após o qual o motor não deve planejar deslocamentos (evitar estrada à noite).';
COMMENT ON COLUMN parametro_rota.intervalo_entre_visitas_min  IS 'Folga mínima entre visitas, em minutos.';
COMMENT ON COLUMN parametro_rota.somente_cidades_qualificadas IS 'Se verdadeiro, só entram na rota municípios qualificados (exceto inclusões manuais).';
COMMENT ON COLUMN parametro_rota.custo_km                     IS 'Custo por km rodado, em reais, para o cálculo de custo/ROI da rota.';
COMMENT ON COLUMN parametro_rota.custo_hospedagem_diaria      IS 'Custo médio de hospedagem por diária.';
COMMENT ON COLUMN parametro_rota.custo_alimentacao_diaria     IS 'Custo médio de alimentação por dia.';
COMMENT ON COLUMN parametro_rota.atualizado_em                IS 'Data/hora da última alteração.';
CREATE TRIGGER tg_parametro_rota_atualizado BEFORE UPDATE ON parametro_rota FOR EACH ROW EXECUTE FUNCTION fn_set_atualizado_em();

-- =============================================================================
-- 8. VISÃO DE COBERTURA (municípios com / sem vendedor)
-- =============================================================================
CREATE OR REPLACE VIEW vw_cobertura_municipio AS
SELECT e.id AS empresa_id, m.id AS municipio_id, m.nome AS municipio, es.uf, m.qualificado,
       (SELECT count(*) FROM loja l WHERE l.empresa_id = e.id AND l.municipio_id = m.id AND l.ativo) AS lojas,
       (SELECT string_agg(DISTINCT f.nome, ', ')
          FROM funcionario_territorio ft JOIN funcionario f ON f.id = ft.funcionario_id
         WHERE ft.empresa_id = e.id
           AND current_date BETWEEN ft.vigencia_inicio AND coalesce(ft.vigencia_fim, 'infinity')
           AND ( ft.nivel = 'PAIS' AND ft.pais_id = es.pais_id
              OR ft.nivel = 'ESTADO' AND ft.estado_id = m.estado_id
              OR ft.nivel IN ('MUNICIPIO','BAIRRO') AND ft.municipio_id = m.id )) AS responsaveis
  FROM empresa e
  CROSS JOIN municipio m
  JOIN estado es ON es.id = m.estado_id
 WHERE EXISTS (SELECT 1 FROM loja l WHERE l.empresa_id = e.id AND l.municipio_id = m.id);
COMMENT ON VIEW vw_cobertura_municipio IS 'Para cada município com lojas da empresa, lista os responsáveis vigentes. responsaveis NULL = município "sem vendedor".';
