"""
Atividade Prática - Carga de dados fictícios (Azure SQL Database)

Volumes gerados:
    cliente    :        100 registros
    produto    :        100 registros
    venda      :    100.000 registros
    item_venda :  1.000.000 registros (10 itens por venda)

Os dados são sintéticos (nomes, CPFs, telefones e e-mails fictícios). A geração
é feita em Python com semente fixa (reprodutível) e os registros são enviados
ao banco em INSERTs multi-linha de 1.000 linhas (limite do T-SQL por comando).
O total de cada venda já é calculado aqui (soma dos itens), então não é
necessário nenhum UPDATE posterior.

Uso:
    pip install -r requirements.txt
    set DB_PASSWORD=...        (PowerShell: $env:DB_PASSWORD = "...")
    python gerar_dados.py --servidor <servidor>.database.windows.net --usuario <usuario_admin> --recriar

Parâmetros também podem vir de variáveis de ambiente:
    DB_SERVER, DB_NAME, DB_USER, DB_PASSWORD
"""
import argparse
import os
import random
import sys
import time
from datetime import date, timedelta
from pathlib import Path

import pymssql

QTD_CLIENTES = 100
QTD_PRODUTOS = 100
QTD_VENDAS = 100_000
ITENS_POR_VENDA = 10  # 100.000 x 10 = 1.000.000 de itens

TAMANHO_LOTE = 1000  # máximo de linhas por INSERT ... VALUES no T-SQL
LOTES_POR_COMMIT = 20

DDL = Path(__file__).resolve().parent.parent / "sql" / "01_ddl.sql"

NOMES = ["Ana", "Bruno", "Carla", "Diego", "Eduarda", "Felipe", "Gabriela", "Henrique",
         "Isabela", "João", "Larissa", "Marcos", "Natália", "Otávio", "Paula", "Rafael",
         "Sofia", "Thiago", "Vanessa", "William", "Lucas", "Mariana", "Pedro", "Camila",
         "Rodrigo", "Juliana", "Leonardo", "Beatriz", "Gustavo", "Fernanda"]
SOBRENOMES = ["Silva", "Santos", "Oliveira", "Souza", "Lima", "Pereira", "Costa", "Ferreira",
              "Almeida", "Ribeiro", "Carvalho", "Gomes", "Martins", "Rocha", "Barbosa",
              "Mendes", "Freitas", "Cardoso", "Teixeira", "Moreira", "Araújo", "Nunes"]
DDDS = ["11", "21", "31", "41", "51", "61", "71", "81", "85"]

CATEGORIAS = ["Notebook", "Mouse", "Teclado", "Monitor", "Headset", "Webcam",
              "Impressora", "SSD", "Cadeira Gamer", "Roteador"]
FORNECEDORES = ["Tech Distribuidora", "InfoMax", "Mega Eletrônicos", "Prime Import", "Byte Shop"]

STATUS = ["ENTREGUE", "PAGA", "ENVIADA", "ABERTA", "CANCELADA"]
PESOS_STATUS = [45, 15, 15, 15, 10]


# ---------------------------------------------------------------- helpers SQL
def txt(valor: str) -> str:
    """Literal NVARCHAR seguro para T-SQL."""
    return "N'" + valor.replace("'", "''") + "'"


def dinheiro(centavos: int) -> str:
    return f"{centavos // 100}.{centavos % 100:02d}"


def cpf_valido(base9: str) -> str:
    """Completa os 9 dígitos com os dois dígitos verificadores do CPF."""
    digitos = [int(d) for d in base9]
    for tamanho in (9, 10):
        soma = sum(d * (tamanho + 1 - i) for i, d in enumerate(digitos[:tamanho]))
        resto = (soma * 10) % 11
        digitos.append(0 if resto == 10 else resto)
    return "".join(map(str, digitos))


# ------------------------------------------------------------------ geradores
def gerar_clientes(rng: random.Random):
    cpfs = set()
    for i in range(1, QTD_CLIENTES + 1):
        while True:
            cpf = cpf_valido(f"{rng.randrange(10**9):09d}")
            if cpf not in cpfs:
                cpfs.add(cpf)
                break
        nome, sobrenome = rng.choice(NOMES), rng.choice(SOBRENOMES)
        telefone = f"({rng.choice(DDDS)}) 9{rng.randrange(10**4):04d}-{rng.randrange(10**4):04d}"
        email = f"cliente{i}@exemplo.com.br"
        yield (txt(f"{nome} {sobrenome}"), f"'{cpf}'", f"'{telefone}'", f"'{email}'")


def gerar_produtos(rng: random.Random):
    """Devolve (linhas SQL, lista de preços em centavos indexada por cod_produto-1)."""
    linhas, precos = [], []
    for i in range(1, QTD_PRODUTOS + 1):
        preco = rng.randrange(1000, 200_001)  # R$ 10,00 a R$ 2.000,00
        precos.append(preco)
        linhas.append((
            txt(f"{rng.choice(CATEGORIAS)} Modelo {i}"),
            dinheiro(preco),
            str(rng.randrange(0, 501)),
            txt(rng.choice(FORNECEDORES)),
        ))
    return linhas, precos


def gerar_vendas_e_itens(rng: random.Random, precos):
    """Gera as vendas (com total já somado) e os itens correspondentes."""
    hoje = date.today()
    vendas, itens = [], []
    for cod_venda in range(1, QTD_VENDAS + 1):
        total = 0
        for cod_item, cod_produto in enumerate(rng.sample(range(1, QTD_PRODUTOS + 1), ITENS_POR_VENDA), start=1):
            quantidade = rng.randrange(1, 11)
            total_item = quantidade * precos[cod_produto - 1]
            total += total_item
            itens.append((str(cod_venda), str(cod_item), str(cod_produto), str(quantidade), dinheiro(total_item)))
        data = hoje - timedelta(days=rng.randrange(730))  # últimos 2 anos
        status = rng.choices(STATUS, weights=PESOS_STATUS)[0]
        vendas.append((str(rng.randrange(1, QTD_CLIENTES + 1)), f"'{data.isoformat()}'", f"'{status}'", dinheiro(total)))
    return vendas, itens


# ------------------------------------------------------------------- banco
def conectar(args):
    ultimo_erro = None
    for tentativa in range(1, 5):  # o banco serverless pode estar pausado: 1ª conexão demora/falha
        try:
            return pymssql.connect(server=args.servidor, user=args.usuario, password=args.senha,
                                   database=args.banco, port=1433, login_timeout=120, timeout=600)
        except pymssql.Error as erro:
            ultimo_erro = erro
            print(f"  tentativa {tentativa} falhou ({str(erro)[:80]}...); aguardando o banco acordar")
            time.sleep(20)
    sys.exit(f"Não foi possível conectar: {ultimo_erro}")


def recriar_tabelas(conn):
    print("Recriando tabelas a partir de sql/01_ddl.sql")
    cur = conn.cursor()
    cur.execute(DDL.read_text(encoding="utf-8"))
    conn.commit()


def limpar_tabelas(conn):
    print("Limpando tabelas existentes")
    cur = conn.cursor()
    for tabela in ("item_venda", "venda", "produto", "cliente"):
        cur.execute(f"DELETE FROM dbo.{tabela}")
    for tabela in ("venda", "produto", "cliente"):  # reinicia o IDENTITY: ids voltam a 1..N
        cur.execute(f"DBCC CHECKIDENT ('dbo.{tabela}', RESEED, 0) WITH NO_INFOMSGS")
    conn.commit()


def inserir(conn, tabela, colunas, linhas, coluna_id=None):
    """Insere em lotes. Se `coluna_id` for informada (tabelas com IDENTITY), o id 1..N é enviado
    explicitamente: num INSERT multi-linha o SQL Server não garante que o IDENTITY siga a ordem
    das linhas, e as FKs/totais calculados aqui dependem de cada linha ter o id esperado."""
    cur = conn.cursor()
    if coluna_id:
        colunas = [coluna_id] + colunas
        linhas = [(str(n),) + l for n, l in enumerate(linhas, start=1)]
        cur.execute(f"SET IDENTITY_INSERT dbo.{tabela} ON")
    cab = f"INSERT INTO dbo.{tabela} ({', '.join(colunas)}) VALUES\n"
    inicio, total = time.time(), len(linhas)
    for n, i in enumerate(range(0, total, TAMANHO_LOTE), start=1):
        lote = linhas[i:i + TAMANHO_LOTE]
        cur.execute(cab + ",\n".join("(" + ", ".join(l) + ")" for l in lote))
        if n % LOTES_POR_COMMIT == 0:
            conn.commit()
            print(f"  {tabela}: {min(i + TAMANHO_LOTE, total):>9,}/{total:,}".replace(",", "."), flush=True)
    if coluna_id:
        cur.execute(f"SET IDENTITY_INSERT dbo.{tabela} OFF")
    conn.commit()
    print(f"  {tabela}: {total:,} linhas em {time.time() - inicio:.1f}s".replace(",", "."))


def conferir(conn):
    cur = conn.cursor()
    print("\nConferência")
    for tabela in ("cliente", "produto", "venda", "item_venda"):
        cur.execute(f"SELECT COUNT(*) FROM dbo.{tabela}")
        print(f"  {tabela:<11}{cur.fetchone()[0]:>12,}".replace(",", "."))
    cur.execute("""SELECT COUNT(*) FROM dbo.venda v
                   JOIN (SELECT cod_venda, SUM(total_item) s FROM dbo.item_venda GROUP BY cod_venda) i
                     ON i.cod_venda = v.cod_venda
                   WHERE v.total <> i.s""")
    print(f"  vendas com total diferente da soma dos itens: {cur.fetchone()[0]}")
    cur.execute("""SELECT COUNT(*) FROM dbo.item_venda i
                   JOIN dbo.produto p ON p.cod_produto = i.cod_produto
                   WHERE i.total_item <> i.quantidade * p.preco_unitario""")
    print(f"  itens com total_item diferente de quantidade x preço: {cur.fetchone()[0]}")


def main():
    ap = argparse.ArgumentParser(description="Popula o banco com dados fictícios.")
    ap.add_argument("--servidor", default=os.getenv("DB_SERVER"))
    ap.add_argument("--banco", default=os.getenv("DB_NAME", "db-projeto-sgbd"))
    ap.add_argument("--usuario", default=os.getenv("DB_USER"))
    ap.add_argument("--senha", default=os.getenv("DB_PASSWORD"))
    ap.add_argument("--semente", type=int, default=42, help="semente do gerador (reprodutibilidade)")
    ap.add_argument("--recriar", action="store_true", help="executa sql/01_ddl.sql antes (derruba e recria as tabelas)")
    args = ap.parse_args()
    if not (args.servidor and args.usuario and args.senha):
        ap.error("informe servidor, usuário e senha (argumentos ou DB_SERVER / DB_USER / DB_PASSWORD)")

    rng = random.Random(args.semente)
    print("Gerando dados em memória")
    clientes = list(gerar_clientes(rng))
    produtos, precos = gerar_produtos(rng)
    vendas, itens = gerar_vendas_e_itens(rng, precos)

    print(f"Conectando em {args.servidor}/{args.banco}")
    conn = conectar(args)
    try:
        recriar_tabelas(conn) if args.recriar else limpar_tabelas(conn)
        print("Inserindo")
        inserir(conn, "cliente", ["nome_completo", "cpf", "telefone", "email"], clientes, "cod_cliente")
        inserir(conn, "produto", ["descricao", "preco_unitario", "qtd_estoque", "nome_fornecedor"], produtos, "cod_produto")
        inserir(conn, "venda", ["cod_cliente", "data", "status", "total"], vendas, "cod_venda")
        inserir(conn, "item_venda", ["cod_venda", "cod_item", "cod_produto", "quantidade", "total_item"], itens)
        conferir(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
