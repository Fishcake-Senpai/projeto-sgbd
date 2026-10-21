# =====================================================
# Atividade Prática - Passo 1: criar a instância do banco (Azure SQL Database)
#
# Cria resource group, servidor lógico e um banco serverless usando a oferta
# gratuita do Azure SQL (pausa automaticamente ao fim do limite mensal, sem cobrança).
#
# Pré-requisitos: Azure CLI instalado e login feito (az login).
# Uso:  .\01_criar_instancia.ps1 -UsuarioAdmin "<usuario>" -SenhaAdmin "<senha forte>"
# =====================================================
param(
    [Parameter(Mandatory)] [string] $UsuarioAdmin,
    [Parameter(Mandatory)] [string] $SenhaAdmin,
    [string] $Sufixo       = (-join ((97..122) + (48..57) | Get-Random -Count 5 | ForEach-Object { [char]$_ })),
    [string] $Regiao       = "brazilsouth",
    [string] $ResourceGroup = "rg-projeto-sgbd",
    [string] $Banco        = "db-projeto-sgbd"
)

$servidor = "sql-projeto-sgbd-$Sufixo"

az group create -n $ResourceGroup -l $Regiao -o none

az sql server create -n $servidor -g $ResourceGroup -l $Regiao `
    -u $UsuarioAdmin -p $SenhaAdmin -o none

# Serverless 1 vCore + oferta gratuita; backup local (o padrão geo-redundante custa mais)
az sql db create -g $ResourceGroup -s $servidor -n $Banco `
    --edition GeneralPurpose --compute-model Serverless --family Gen5 --capacity 1 `
    --use-free-limit --free-limit-exhaustion-behavior AutoPause `
    --backup-storage-redundancy Local -o none

# Firewall aberto (ambiente de estudo, dados fictícios). Em produção, liberar só IPs específicos.
az sql server firewall-rule create -g $ResourceGroup -s $servidor -n allow-all `
    --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255 -o none

Write-Host "Servidor: $servidor.database.windows.net  |  Banco: $Banco"
