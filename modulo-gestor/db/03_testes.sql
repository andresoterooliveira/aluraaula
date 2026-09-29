-- Testes de regra de negócio (executar após 01 e 02). Cada bloco deve falhar/passar conforme indicado.
SET search_path TO rota, public;

-- Esperado: FALHA (bairro Centro de Itaboraí pertence ao município já atribuído a Marcos)
DO $$ BEGIN
  INSERT INTO funcionario_territorio (empresa_id, funcionario_id, nivel, bairro_id) VALUES (1, 3, 'BAIRRO', 1);
  RAISE EXCEPTION 'teste falhou: sobreposição aceita';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'OK: %', SQLERRM; END $$;

-- Esperado: FALHA (estado RJ contém Itaboraí)
DO $$ BEGIN
  INSERT INTO funcionario_territorio (empresa_id, funcionario_id, nivel, estado_id) VALUES (1, 3, 'ESTADO', 33);
  RAISE EXCEPTION 'teste falhou: sobreposição aceita';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'OK: %', SQLERRM; END $$;

-- Esperado: SUCESSO (Niterói está livre)
INSERT INTO funcionario_territorio (empresa_id, funcionario_id, nivel, municipio_id) VALUES (1, 2, 'MUNICIPIO', 3303302);

-- Esperado: SUCESSO (vigência não coincide: Itaboraí passa para Juliana só após encerrar o vínculo de Marcos)
UPDATE funcionario_territorio SET vigencia_fim = current_date + 30 WHERE funcionario_id = 2 AND municipio_id = 3301900;
INSERT INTO funcionario_territorio (empresa_id, funcionario_id, nivel, municipio_id, vigencia_inicio)
VALUES (1, 1, 'MUNICIPIO', 3301900, current_date + 31);

-- Tempo: loja 1 com Marcos -> 60 (FUNCIONARIO); loja 1 sem funcionário -> 120 (GLOBAL)
SELECT 'loja1/marcos' AS caso, * FROM fn_tempo_atendimento(1, 2)
UNION ALL SELECT 'loja1/sem func', * FROM fn_tempo_atendimento(1)
UNION ALL SELECT 'loja2/juliana', * FROM fn_tempo_atendimento(2, 3);

SELECT * FROM vw_loja_qualificacao ORDER BY loja_id;
SELECT municipio, uf, lojas, responsaveis FROM vw_cobertura_municipio ORDER BY municipio;
