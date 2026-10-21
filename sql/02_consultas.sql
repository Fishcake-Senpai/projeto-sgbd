-- =====================================================
-- Atividade Prática – Consultas de exemplo  |  Azure SQL Database (T-SQL)
-- 02 - Executar após a carga (python/gerar_dados.py)
-- Cada bloco é independente: selecione e execute individualmente.
-- =====================================================

-- -----------------------------------------------------
-- 1. Conferência do volume carregado
-- -----------------------------------------------------
SELECT 'cliente'    AS tabela, COUNT(*) AS registros FROM dbo.cliente
UNION ALL SELECT 'produto',    COUNT(*) FROM dbo.produto
UNION ALL SELECT 'venda',      COUNT(*) FROM dbo.venda
UNION ALL SELECT 'item_venda', COUNT(*) FROM dbo.item_venda;

-- -----------------------------------------------------
-- 2. Integridade: total da venda = soma dos itens (esperado: 0 linhas)
-- -----------------------------------------------------
SELECT v.cod_venda, v.total, SUM(i.total_item) AS soma_itens
FROM dbo.venda v
JOIN dbo.item_venda i ON i.cod_venda = v.cod_venda
GROUP BY v.cod_venda, v.total
HAVING v.total <> SUM(i.total_item);

-- -----------------------------------------------------
-- 3. Faturamento e ticket médio por status da venda
-- -----------------------------------------------------
SELECT status,
       COUNT(*)              AS qtd_vendas,
       SUM(total)            AS faturamento,
       AVG(total)            AS ticket_medio
FROM dbo.venda
GROUP BY status
ORDER BY faturamento DESC;

-- -----------------------------------------------------
-- 4. Faturamento mensal (vendas não canceladas) - últimos 12 meses
-- -----------------------------------------------------
SELECT YEAR(data)  AS ano,
       MONTH(data) AS mes,
       COUNT(*)    AS qtd_vendas,
       SUM(total)  AS faturamento
FROM dbo.venda
WHERE status <> 'CANCELADA'
  AND data >= DATEADD(MONTH, -12, CAST(GETDATE() AS DATE))
GROUP BY YEAR(data), MONTH(data)
ORDER BY ano, mes;

-- -----------------------------------------------------
-- 5. Top 10 clientes por valor comprado (JOIN cliente x venda)
-- -----------------------------------------------------
SELECT TOP 10
       c.cod_cliente, c.nome_completo,
       COUNT(v.cod_venda) AS qtd_compras,
       SUM(v.total)       AS total_comprado
FROM dbo.cliente c
JOIN dbo.venda v ON v.cod_cliente = c.cod_cliente
WHERE v.status <> 'CANCELADA'
GROUP BY c.cod_cliente, c.nome_completo
ORDER BY total_comprado DESC;

-- -----------------------------------------------------
-- 6. Top 10 produtos mais vendidos (JOIN item_venda x produto)
-- -----------------------------------------------------
SELECT TOP 10
       p.cod_produto, p.descricao, p.nome_fornecedor,
       SUM(i.quantidade) AS unidades_vendidas,
       SUM(i.total_item) AS receita
FROM dbo.item_venda i
JOIN dbo.produto p ON p.cod_produto = i.cod_produto
GROUP BY p.cod_produto, p.descricao, p.nome_fornecedor
ORDER BY unidades_vendidas DESC;

-- -----------------------------------------------------
-- 7. Receita por fornecedor (JOIN das 4 tabelas, sem canceladas)
-- -----------------------------------------------------
SELECT p.nome_fornecedor,
       COUNT(DISTINCT c.cod_cliente) AS clientes_atendidos,
       COUNT(DISTINCT v.cod_venda)   AS vendas,
       SUM(i.total_item)             AS receita
FROM dbo.cliente c
JOIN dbo.venda      v ON v.cod_cliente = c.cod_cliente
JOIN dbo.item_venda i ON i.cod_venda   = v.cod_venda
JOIN dbo.produto    p ON p.cod_produto = i.cod_produto
WHERE v.status <> 'CANCELADA'
GROUP BY p.nome_fornecedor
ORDER BY receita DESC;

-- -----------------------------------------------------
-- 8. Detalhe completo de uma venda (nota)
-- -----------------------------------------------------
SELECT v.cod_venda, v.data, v.status, c.nome_completo,
       i.cod_item, p.descricao, i.quantidade, p.preco_unitario, i.total_item
FROM dbo.venda v
JOIN dbo.cliente    c ON c.cod_cliente = v.cod_cliente
JOIN dbo.item_venda i ON i.cod_venda   = v.cod_venda
JOIN dbo.produto    p ON p.cod_produto = i.cod_produto
WHERE v.cod_venda = 1
ORDER BY i.cod_item;

-- -----------------------------------------------------
-- 9. Clientes com gasto acima da média (subconsulta)
-- -----------------------------------------------------
WITH gasto AS (
    SELECT cod_cliente, SUM(total) AS total_comprado
    FROM dbo.venda
    WHERE status <> 'CANCELADA'
    GROUP BY cod_cliente
)
SELECT c.cod_cliente, c.nome_completo, g.total_comprado
FROM gasto g
JOIN dbo.cliente c ON c.cod_cliente = g.cod_cliente
WHERE g.total_comprado > (SELECT AVG(total_comprado) FROM gasto)
ORDER BY g.total_comprado DESC;

-- -----------------------------------------------------
-- 10. Ranking de produtos por fornecedor (função de janela)
-- -----------------------------------------------------
SELECT nome_fornecedor, descricao, receita,
       RANK() OVER (PARTITION BY nome_fornecedor ORDER BY receita DESC) AS posicao
FROM (
    SELECT p.nome_fornecedor, p.descricao, SUM(i.total_item) AS receita
    FROM dbo.item_venda i
    JOIN dbo.produto p ON p.cod_produto = i.cod_produto
    GROUP BY p.nome_fornecedor, p.descricao
) r
ORDER BY nome_fornecedor, posicao;

-- -----------------------------------------------------
-- 11. Produtos com estoque baixo e alta saída (reposição)
-- -----------------------------------------------------
SELECT TOP 15
       p.cod_produto, p.descricao, p.qtd_estoque,
       SUM(i.quantidade) AS unidades_vendidas
FROM dbo.produto p
JOIN dbo.item_venda i ON i.cod_produto = p.cod_produto
WHERE p.qtd_estoque < 50
GROUP BY p.cod_produto, p.descricao, p.qtd_estoque
ORDER BY unidades_vendidas DESC;

-- -----------------------------------------------------
-- 12. Faturamento acumulado por mês (função de janela)
-- -----------------------------------------------------
SELECT ano, mes, faturamento,
       SUM(faturamento) OVER (ORDER BY ano, mes) AS acumulado
FROM (
    SELECT YEAR(data) AS ano, MONTH(data) AS mes, SUM(total) AS faturamento
    FROM dbo.venda
    WHERE status <> 'CANCELADA'
    GROUP BY YEAR(data), MONTH(data)
) m
ORDER BY ano, mes;
