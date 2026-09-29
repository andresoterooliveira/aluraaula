-- =============================================================================
-- App Rota :: Módulo do Gestor - dados iniciais
-- Parte A: padrões do sistema (sempre carregar)
-- Parte B: amostra de referência territorial e empresa fictícia (protótipo/teste)
-- A base territorial completa deve ser importada do IBGE (CSV) em produção.
-- =============================================================================
SET search_path TO rota, public;

-- ---------- Parte A: padrões do sistema ----------
INSERT INTO segmento (nome, tempo_sugerido_min, nivel_territorial_sugerido) VALUES
  ('Vestuário esportivo', 120, 'MUNICIPIO'),
  ('Calçados',             90, 'MUNICIPIO'),
  ('Bebidas',              15, 'BAIRRO'),
  ('Farmácia',             30, 'BAIRRO'),
  ('Cosméticos',           45, 'MUNICIPIO');

INSERT INTO status_loja (empresa_id, codigo, descricao, cor_hex, ordem) VALUES
  (NULL, 'ATIVO',      'Ativo',                          '#15803D', 1),
  (NULL, 'INATIVO',    'Inativo',                        '#6B7280', 2),
  (NULL, 'NOVO',       'Novo',                           '#2563EB', 3),
  (NULL, 'REATIVACAO', 'Reativação',                     '#B45309', 4),
  (NULL, 'JOURNEY',    'Journey (pulou uma coleção)',    '#7C3AED', 5),
  (NULL, 'PROSPECCAO', 'Prospecção',                     '#0E7490', 6);

INSERT INTO motivo (empresa_id, tipo, descricao, exige_texto_livre, ordem) VALUES
  (NULL, 'NAO_VISITA', 'Visita reagendada pelo cliente',        false, 1),
  (NULL, 'NAO_VISITA', 'Reagendada pelo vendedor',              false, 2),
  (NULL, 'NAO_VISITA', 'Logística',                             false, 3),
  (NULL, 'NAO_VISITA', 'Estrada / condição de tráfego',         false, 4),
  (NULL, 'NAO_VISITA', 'Clima',                                 false, 5),
  (NULL, 'NAO_VISITA', 'Loja fechada',                          false, 6),
  (NULL, 'NAO_VISITA', 'Imprevisto',                            false, 7),
  (NULL, 'NAO_VISITA', 'Outros',                                true,  99),
  (NULL, 'NAO_VENDA',  'Estoque cheio',                         false, 1),
  (NULL, 'NAO_VENDA',  'Não aceitou o prazo de pagamento',      false, 2),
  (NULL, 'NAO_VENDA',  'Não aceitou o markup',                  false, 3),
  (NULL, 'NAO_VENDA',  'Decisor ausente',                       false, 4),
  (NULL, 'NAO_VENDA',  'Problema pessoal/familiar do cliente',  false, 5),
  (NULL, 'NAO_VENDA',  'Outros',                                true,  99);

-- ---------- Parte B: amostra territorial ----------
INSERT INTO pais VALUES (1058, 'BR', 'Brasil');
INSERT INTO estado VALUES (33, 1058, 'RJ', 'Rio de Janeiro'), (26, 1058, 'PE', 'Pernambuco'),
                          (53, 1058, 'DF', 'Distrito Federal'), (35, 1058, 'SP', 'São Paulo');
INSERT INTO municipio (id, estado_id, nome, populacao, qualificado) VALUES
  (3301900, 33, 'Itaboraí',            224267, true),
  (3303302, 33, 'Niterói',             481758, true),
  (3304904, 33, 'São Gonçalo',         896744, true),
  (3304557, 33, 'Rio de Janeiro',     6211223, true),
  (3302700, 33, 'Maricá',              197300, false),
  (2611606, 26, 'Recife',             1488920, true),
  (2609600, 26, 'Olinda',              349976, true),
  (2607901, 26, 'Jaboatão dos Guararapes', 643759, true),
  (5300108, 53, 'Brasília',           2817381, true),
  (3550308, 35, 'São Paulo',         11451999, true),
  (3509502, 35, 'Campinas',           1139047, true);
INSERT INTO bairro (municipio_id, nome) VALUES
  (3301900, 'Centro'), (3301900, 'Manilha'), (3301900, 'Venda das Pedras'), (3301900, 'Outeiro das Pedras'),
  (2611606, 'Boa Viagem'), (2611606, 'Casa Forte'), (2611606, 'Espinheiro'), (2611606, 'Pina'),
  (3303302, 'Icaraí'), (3303302, 'Centro');

-- ---------- Parte B: empresa fictícia ----------
INSERT INTO empresa (razao_social, nome_fantasia, cnpj, segmento_id, assinatura_inicio)
VALUES ('Sportline Representações Ltda', 'Sportline', '12345678000190', 1, '2026-10-01');

INSERT INTO parametro_rota (empresa_id, custo_km, custo_hospedagem_diaria, custo_alimentacao_diaria)
VALUES (1, 1.10, 180.00, 90.00);

INSERT INTO tempo_atendimento (empresa_id, dimensao, minutos, observacao)
VALUES (1, 'GLOBAL', 120, 'Média do segmento vestuário');

INSERT INTO funcionario (empresa_id, nome, cpf, email, perfil, cargo, cep_partida) VALUES
  (1, 'Rodrigo Anjos',   '11122233344', 'rodrigo@sportline.example', 'GESTOR',        'Gerente Regional', '24800000'),
  (1, 'Marcos Tavares',  '22233344455', 'marcos@sportline.example',  'REPRESENTANTE', 'Representante',    '24800010'),
  (1, 'Juliana Freitas', '33344455566', 'juliana@sportline.example', 'REPRESENTANTE', 'Representante',    '51020000');

INSERT INTO funcionario_territorio (empresa_id, funcionario_id, nivel, municipio_id, criado_por)
VALUES (1, 2, 'MUNICIPIO', 3301900, 1);
INSERT INTO funcionario_territorio (empresa_id, funcionario_id, nivel, estado_id, criado_por)
VALUES (1, 3, 'ESTADO', 26, 1);

INSERT INTO tempo_atendimento (empresa_id, dimensao, funcionario_id, minutos, observacao)
VALUES (1, 'FUNCIONARIO', 2, 60, 'Vendedor experiente, fecha pedido mais rápido');

INSERT INTO marca (empresa_id, nome) VALUES (1, 'Adidas'), (1, 'Nike'), (1, 'Fila'), (1, 'Puma');
INSERT INTO loja (empresa_id, codigo_cliente, nome, municipio_id, bairro_id, status_loja_id)
VALUES (1, 'C-0001', 'Arena Esportes', 3301900, 1, 1),
       (1, 'C-0002', 'Boa Viagem Sports', 2611606, 5, 5);
INSERT INTO loja_marca VALUES (1, 1), (1, 2), (1, 3), (2, 2);
