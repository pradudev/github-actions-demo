## This script exports the MSSQL DB to a Storage Account as a BACPAC file 

Param (
)

# Get values from ENV variables
[string]$dbResourceGroupName = $env:AZURE_SQL_DB_RESOURCEGROUP_NAME
[string]$dbServerName = $env:AZURE_SQL_DB_SERVER_NAME
[string]$dbName = $env:AZURE_SQL_DB_NAME
[string]$storageAccountAccessKey = $env:STORAGEACCOUNT_ACCESS_KEY
[string]$storageAccountName = $env:STORAGEACCOUNT_NAME
[string]$storageContainerName = $env:STORAGECONTAINER_NAME
[string]$keyVaultName = $env:KEYVAULT_NAME
[string]$sqlAdminUserNameKvSecretName = $env:SQLADMIN_USERNAME_KV_SECRET_NAME
[string]$sqlAdminPasswordKvSecretName = $env:SQLADMIN_PASSWORD_KV_SECRET_NAME


# Fetch SQL Server Admin Credentials from the Key Vault
$sqlAdminUserName = $(Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $sqlAdminUserNameKvSecretName -AsPlainText)
[securestring]$sqlAdminPassword = $(Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $sqlAdminPasswordKvSecretName -AsPlainText) | ConvertTo-SecureString -AsPlainText -Force


# Prepare bacpac file name
$filename = (get-date).ToString("yyyyMMddhhmm");
$bacpacUri = "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$filename.bacpac"

Write-Host "Source DB: $dbServerName/$dbName"
Write-Host "Export to Bacpac file: $bacpacUri"


# Check firewall exception
$hasFirewallExceptionFromPortal = $null -ne $(Get-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName `
    -ServerName $dbServerName `
    -FirewallRuleName "AllowAllWindowsAzureIps" `
    -ErrorAction SilentlyContinue)

$hasFirewallExceptionFromScript = $null -ne $(Get-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName `
    -ServerName $dbServerName `
    -FirewallRuleName "AllowAllAzureIPs" `
    -ErrorAction SilentlyContinue)    

$needNewFwException = ($hasFirewallExceptionFromPortal -eq $false) -and ($hasFirewallExceptionFromScript -eq $false)

Write-Host ("Need a firewall exception in the Storage Account?: $needNewFwException")

# Turn ON "Allow access to Azure services"
if ($needNewFwException){
    New-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName  -ServerName $dbServerName -AllowAllAzureIPs
}

# Export the DB schema + data 
$exportRequest = New-AzSqlDatabaseExport -ResourceGroupName $dbResourceGroupName `
    -ServerName $dbServerName `
    -DatabaseName $dbName `
    -StorageKeytype "StorageAccessKey" `
    -StorageKey $storageAccountAccessKey `
    -StorageUri $bacpacUri `
    -AdministratorLogin $sqlAdminUserName `
    -AdministratorLoginPassword $sqlAdminPassword

# Check the status of the export
$exportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink
Write-Host -NoNewline "Exporting"
while ($exportStatus.Status -eq "InProgress")
{
    Start-Sleep -s 10
    $exportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink
    Write-Host -NoNewline "."
}
Write-Host ""
$exportStatus

# Turn OFF "Allow access to Azure services"
if ($hasFirewallExceptionFromScript){
    Remove-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName -ServerName $dbServerName -FirewallRuleName "AllowAllAzureIPs"
}

# Output the bacpac file path in the GitHub Action
"BACKPAC_FILE_NAME=$bacpacUri" >> $env:GITHUB_OUTPUT