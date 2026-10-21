-- =====================================================
-- Atividade Prática – Modelo CLIENTE / VENDA / ITEM_VENDA / PRODUTO
-- 01 - Estrutura das tabelas (DDL)  |  Azure SQL Database (T-SQL)
--
-- Pré-requisito: a instância (servidor + banco) já criada, ver
-- infra/01_criar_instancia.ps1. Execute este script conectado ao
-- banco db-projeto-sgbd.
--
-- O script é re-executável: derruba as tabelas (ordem inversa
-- das dependências) e recria tudo.
-- =====================================================

DROP TABLE IF EXISTS dbo.item_venda;
DROP TABLE IF EXISTS dbo.venda;
DROP TABLE IF EXISTS dbo.produto;
DROP TABLE IF EXISTS dbo.cliente;

-- -----------------------------------------------------
-- CLIENTE (5 atributos)
-- -----------------------------------------------------
CREATE TABLE dbo.cliente (
    cod_cliente     INT           IDENTITY(1,1) NOT NULL,
    nome_completo   NVARCHAR(150) NOT NULL,
    cpf             CHAR(11)      NOT NULL,
    telefone        VARCHAR(20)   NULL,
    email           VARCHAR(150)  NULL,
    CONSTRAINT pk_cliente     PRIMARY KEY (cod_cliente),
    CONSTRAINT uq_cliente_cpf UNIQUE (cpf)
);

-- -----------------------------------------------------
-- PRODUTO (5 atributos)
-- -----------------------------------------------------
CREATE TABLE dbo.produto (
    cod_produto     INT           IDENTITY(1,1) NOT NULL,
    descricao       NVARCHAR(200) NOT NULL,
    preco_unitario  DECIMAL(10,2) NOT NULL,
    qtd_estoque     INT           NOT NULL CONSTRAINT df_produto_estoque DEFAULT 0,
    nome_fornecedor NVARCHAR(150) NULL,
    CONSTRAINT pk_produto       PRIMARY KEY (cod_produto),
    CONSTRAINT ck_produto_preco CHECK (preco_unitario >= 0),
    CONSTRAINT ck_produto_qtd   CHECK (qtd_estoque >= 0)
);

-- -----------------------------------------------------
-- VENDA (5 atributos)  -  CLIENTE 1 ---- N VENDA
-- -----------------------------------------------------
CREATE TABLE dbo.venda (
    cod_venda       INT           IDENTITY(1,1) NOT NULL,
    cod_cliente     INT           NOT NULL,
    data            DATE          NOT NULL CONSTRAINT df_venda_data   DEFAULT CAST(GETDATE() AS DATE),
    status          VARCHAR(20)   NOT NULL CONSTRAINT df_venda_status DEFAULT 'ABERTA',
    total           DECIMAL(12,2) NOT NULL CONSTRAINT df_venda_total  DEFAULT 0,
    CONSTRAINT pk_venda         PRIMARY KEY (cod_venda),
    CONSTRAINT fk_venda_cliente FOREIGN KEY (cod_cliente) REFERENCES dbo.cliente (cod_cliente),
    CONSTRAINT ck_venda_status  CHECK (status IN ('ABERTA','PAGA','ENVIADA','ENTREGUE','CANCELADA'))
);

-- -----------------------------------------------------
-- ITEM_VENDA (5 atributos)
-- VENDA 1 ---- N ITEM_VENDA N ---- 1 PRODUTO
-- PK composta (cod_venda, cod_item)
-- -----------------------------------------------------
CREATE TABLE dbo.item_venda (
    cod_venda       INT           NOT NULL,
    cod_item        INT           NOT NULL,
    cod_produto     INT           NOT NULL,
    quantidade      INT           NOT NULL,
    total_item      DECIMAL(12,2) NOT NULL,
    CONSTRAINT pk_item_venda         PRIMARY KEY (cod_venda, cod_item),
    CONSTRAINT fk_item_venda_venda   FOREIGN KEY (cod_venda)   REFERENCES dbo.venda (cod_venda) ON DELETE CASCADE,
    CONSTRAINT fk_item_venda_produto FOREIGN KEY (cod_produto) REFERENCES dbo.produto (cod_produto),
    CONSTRAINT ck_item_venda_qtd     CHECK (quantidade > 0)
);

-- -----------------------------------------------------
-- Índices de apoio às chaves estrangeiras
-- (aceleram os JOINs / filtros das consultas em 02_consultas.sql)
-- -----------------------------------------------------
CREATE INDEX ix_venda_cliente       ON dbo.venda       (cod_cliente);
CREATE INDEX ix_venda_data          ON dbo.venda       (data) INCLUDE (status, total);
CREATE INDEX ix_item_venda_produto  ON dbo.item_venda  (cod_produto) INCLUDE (quantidade, total_item);
