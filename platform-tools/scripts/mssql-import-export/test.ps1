[uri]$bacpacUri = "https://pradeepmssqlbackup.blob.core.windows.net/marketplaces-product-bkps/202302020954.bacpac"

$bacpacFileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($bacpacUri.Segments[-1])

Write-Host "Creating a new DB: $bacpacFileNameWithoutExt"