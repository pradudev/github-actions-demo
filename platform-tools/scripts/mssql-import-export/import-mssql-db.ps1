# This script imports the MSSQL DB from a Storage Account to a new Azure SQL DB

Param (
  [string]$DBResourceGroupName = "bigw-rg-dev-aae-marketplaces",
  [string]$DBServerName = "bigw-mssql-dev-aae-marketplaces-product-srv",
  [string]$DBNamePrefix = "marketplaces-product-",
  [uri]$BacpacUri = "https://pradeepmssqlbackup.blob.core.windows.net/marketplaces-product-bkps/202301310547.bacpac",
  [string]$StorageAccountResourceGroupName = "pradeep-test-rg",
  [string]$StorageAccountName = "pradeepmssqlbackup",
  [string]$DBMaxSizeBytes = "34359738368",
  [string]$DBEdition = "GeneralPurpose",
  [string]$DBServiceObjectiveName = "GP_S_Gen5_1",
  [string]$KeyVaultName = "bigw-devops-dev-kv",
  [string]$SqlAdminUserNameKvSecretName= "BIGW-MSSQL-DEV-AAE-MARKETPLACES-PRODUCT-SRV--ADMINISTRATOR-LOGIN",
  [string]$SqlAdminPasswordKvSecretName = "BIGW-MSSQL-DEV-AAE-MARKETPLACES-PRODUCT-SRV--ADMINISTRATOR-LOGIN-PASSWORD"
)

# Connect Azure using SPN
$spnCreds = New-Object System.Management.Automation.PSCredential $env:ARM_CLIENT_ID, $(ConvertTo-SecureString -String $env:ARM_CLIENT_SECRET -AsPlainText -Force)
Connect-AzAccount -ServicePrincipal -TenantId $env:ARM_TENANT_ID -Credential $spnCreds
Select-AzSubscription -Subscription $env:ARM_SUBSCRIPTION_ID

# Fetch Storage Account Access Key
$saAccessKey = $(Get-AzStorageAccountKey -ResourceGroupName $StorageAccountResourceGroupName -Name $StorageAccountName)[0].Value

# Fetch SQL Server Admin Credentials from the Key Vault
$sqlAdminUserName = $(Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SqlAdminUserNameKvSecretName -AsPlainText)
[securestring]$sqlAdminPassword = $(Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SqlAdminPasswordKvSecretName -AsPlainText) | ConvertTo-SecureString -AsPlainText -Force


# Check firewall exception
$needFwException = $null -eq $(Get-AzSqlServerFirewallRule -ResourceGroupName $DBResourceGroupName `
    -ServerName $DBServerName `
    -FirewallRuleName "AllowAllWindowsAzureIps" `
    -ErrorAction SilentlyContinue)

Write-Output ("Need a firewall exception?: $needFwException")

# Turn ON "Allow access to Azure services"
if ($needFwException){
    New-AzSqlServerFirewallRule -ResourceGroupName $DBResourceGroupName  -ServerName $DBServerName -AllowAllAzureIPs
}

$bacpacFileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BacpacUri.Segments[-1])
$dbName = $DBNamePrefix + $bacpacFileNameWithoutExt;

Write-Host "Creating a new DB: $DBServerName/$dbName"

# Export the DB schema + data 
$importRequest = New-AzSqlDatabaseImport -ResourceGroupName $DBResourceGroupName `
    -ServerName $DBServerName -DatabaseName $dbName `
    -DatabaseMaxSizeBytes $DBMaxSizeBytes `
    -StorageKeyType "StorageAccessKey" `
    -StorageKey $saAccessKey `
    -StorageUri $BacpacUri `
    -Edition $DBEdition `
    -ServiceObjectiveName $DBServiceObjectiveName `
    -AdministratorLogin $sqlAdminUserName `
    -AdministratorLoginPassword $sqlAdminPassword

# Check the status of the export
$importStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $importRequest.OperationStatusLink

[Console]::Write("Importing")
while ($importStatus.Status -eq "InProgress") {
    $importStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $importRequest.OperationStatusLink
    [Console]::Write(".")
    Start-Sleep -s 10
}
[Console]::WriteLine("")
$importStatus


# Turn OFF "Allow access to Azure services"
if ($needFwException){
    Remove-AzSqlServerFirewallRule -ResourceGroupName $DBResourceGroupName -ServerName $DBServerName -FirewallRuleName "AllowAllAzureIPs"
}
