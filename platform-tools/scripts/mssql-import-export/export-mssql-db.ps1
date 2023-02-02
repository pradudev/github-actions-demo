## This script exports the MSSQL DB to a Storage Account as a BACPAC file 

Param (
)

# Get values from ENV variables
[string]$dbResourceGroupName = $env:DB_RESOURCEGROUP_NAME
[string]$dbServerName = $env:DB_SERVER_NAME
[string]$dbName = $env:DB_NAME
[securestring]$storageAccountAccessKey = ConvertTo-SecureString $env:STORAGEACCOUNT_ACCESS_KEY -AsPlainText -Force
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
$needFwException = $null -eq $(Get-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName `
    -ServerName $dbServerName `
    -FirewallRuleName "AllowAllWindowsAzureIps" `
    -ErrorAction SilentlyContinue)

Write-Host ("Need a firewall exception?: $needFwException")

# Turn ON "Allow access to Azure services"
if ($needFwException){
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
[Console]::Write("Exporting")
while ($exportStatus.Status -eq "InProgress")
{
    Start-Sleep -s 10
    $exportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink
    [Console]::Write(".")
}
[Console]::WriteLine("")
$exportStatus

# Turn OFF "Allow access to Azure services"
if ($needFwException){
    Remove-AzSqlServerFirewallRule -ResourceGroupName $dbResourceGroupName -ServerName $dbServerName -FirewallRuleName "AllowAllAzureIPs"
}
