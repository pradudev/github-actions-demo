[string]$keyVaultName = "bigw-devops-dev-kv"
[string]$SqlAdminPasswordKvSecret = "BIGW-MSSQL-DEV-AAE-MARKETPLACES-PRODUCT-SRV--ADMINISTRATOR-LOGIN-PASSWORD"


Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $SqlAdminPasswordKvSecret -AsPlainText | ConvertTo-SecureString -AsPlainText -Force