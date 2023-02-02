# This script imports the MSSQL DB from a Storage Account to a new Azure SQL DB

Param (
)

# Get values from ENV variables
[string]$dbResourceGroupName = $env:AZURE_SQL_DB_RESOURCEGROUP_NAME
[string]$dbServerName = $env:AZURE_SQL_DB_SERVER_NAME
[string]$dbNamePrefix = $env:AZURE_SQL_DB_NAME_PREFIX
[string]$bacpacUri = $env:BACPAC_URI
[string]$storageAccountAccessKey = $env:STORAGEACCOUNT_ACCESS_KEY
[string]$dbMaxSizeBytes = $env:AZURE_SQL_DB_MAX_SIZE_BYTES
[string]$dbEdition = $env:AZURE_SQL_DB_EDITION
[string]$dbServiceObjectiveName = $env:AZURE_SQL_DB_SERVICE_OBJECTIVE_NAME
[string]$keyVaultName = $env:KEYVAULT_NAME
[string]$sqlAdminUserNameKvSecretName = $env:SQLADMIN_USERNAME_KV_SECRET_NAME
[string]$sqlAdminPasswordKvSecretName = $env:SQLADMIN_PASSWORD_KV_SECRET_NAME


# Fetch SQL Server Admin Credentials from the Key Vault
$sqlAdminUserName = $(Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $sqlAdminUserNameKvSecretName -AsPlainText)
[securestring]$sqlAdminPassword = $(Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $sqlAdminPasswordKvSecretName -AsPlainText) | ConvertTo-SecureString -AsPlainText -Force


# Check firewall exception
$hasFirewallExceptionFromPortal = $null -ne $(Get-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName `
    -ServerName $dbServerName `
    -FirewallRuleName "AllowAllWindowsAzureIps" `
    -ErrorAction SilentlyContinue)


$hasFirewallExceptionFromScript = $null -ne $(Get-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName `
    -ServerName $dbServerName `
    -FirewallRuleName "AllowAllAzureIPs" `
    -ErrorAction SilentlyContinue)    

Write-Host ("Need a firewall exception?: $needFwException")

# Turn ON "Allow access to Azure services"
if (($hasFirewallExceptionFromPortal -eq $false) -and ($hasFirewallExceptionFromScript -eq $false)){
    New-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName  -ServerName $dbServerName -AllowAllAzureIPs
}

$bacpacFileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($bacpacUri.Segments[-1])
$dbName = $dbNamePrefix + $bacpacFileNameWithoutExt;

Write-Host "Creating a new DB: $dbServerName/$dbName"

# Export the DB schema + data 
$importRequest = New-AzSqlDatabaseImport -ResourceGroupName $dbResourceGroupName `
    -ServerName $dbServerName -DatabaseName $dbName `
    -DatabaseMaxSizeBytes $dbMaxSizeBytes `
    -StorageKeyType "StorageAccessKey" `
    -StorageKey $storageAccountAccessKey `
    -StorageUri $bacpacUri `
    -Edition $dbEdition `
    -ServiceObjectiveName $dbServiceObjectiveName `
    -AdministratorLogin $sqlAdminUserName `
    -AdministratorLoginPassword $sqlAdminPassword

# Check the status of the export
$importStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $importRequest.OperationStatusLink
Write-Host -NoNewline "Importing"
while ($importStatus.Status -eq "InProgress") {
    $importStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $importRequest.OperationStatusLink
    Write-Host -NoNewline "."
    Start-Sleep -s 10
}
Write-Host ""
$importStatus


# Turn OFF "Allow access to Azure services"
if ($hasFirewallExceptionFromScript){
    Remove-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName -ServerName $dbServerName -FirewallRuleName "AllowAllAzureIPs"
}