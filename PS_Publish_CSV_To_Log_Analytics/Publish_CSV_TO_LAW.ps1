##################################################################################
## Name: Mudit Mittal                                                           ##
## Email: mudit.a.mittal@avanade.com                                            ##
## Description: Publish CSV Data to Azure Log Analytics Workspace               ##
## Pre-Requisites: NA                                                           ##
## Version: 1.0                                                                 ##
## Modified Date: 20-Oct-2023                                                   ##
## Reference: https://github.com/muditmittal1985/PowerShell                     ##
##################################################################################

<# (Optional) Retrive the log analytics "Customer Id" & "Shared key" from AKV
$SharedKey = (Get-AzKeyVaultSecret -VaultName "akv-irin-dev-vault-0010" -Name "law-shared-key").SecretValue
$CustomerId = (Get-AzKeyVaultSecret -VaultName "akv-irin-dev-vault-0010" -Name "law-customer-Id").SecretValue
#>


$Custom_Logs = "Test_CL" # Provide the Custom Table Name
$CustomerId = "f21ba7a7-aaeb-453c-869b-2c6aef6b6ff9" # Log Analytics Workspace ID
$SharedKey = 'nk82EaQg8h4tdU1MAtbgHHg6gzLu4fuwdmyzmlkq9IijcllCaKKSR2yZe+VJoGFDart8P1yyWilnoGxKUYkkyg==' # Log Analytics Workspace Primary Key
$TimeStampField = ""


# Build PowerShell "Function - Build Signature" for Azure Log Analytics 
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}


# Build PowerShell "Function - Post Data" to Azure Log Analytics 
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $CustomerId `
        -sharedKey $SharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $CustomerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}

*****************************************************************************************************************************************************
# (Method - 01) Build Script to Import-CSV from Local Disk & Convert to JSON

$Test_LA_File = "C:\Users\mudit.a.mittal\Downloads\CCBM\Cost-Management\CostManagement_ira0001-azr-093-preprod01_2023-07-12-1715.csv"
$Get_CSV_FirstLine = Get-Content $Test_LA_File | Select -First 1
$Get_Delimiter = If($Get_CSV_FirstLine.Split(";").Length -gt 1){";"}Else{","};
$Test_LA_CSV = import-csv $Test_LA_File -Delimiter $Get_Delimiter

$InfoToImport_Json = $Test_LA_CSV | ConvertTo-Json

# Trigger the "Function - Post Data" with converted JSON
$params = @{
	CustomerId = $customerId
	SharedKey  = $sharedKey
	Body       = ([System.Text.Encoding]::UTF8.GetBytes($InfoToImport_Json))
	LogType    = $Custom_Logs 
}
$LogResponse = Post-LogAnalyticsData @params

*****************************************************************************************************************************************************
# (Method - 02) Build Script to Import-CSV from Storage Account & Convert to JSON

$storageAccountName = "stirindevizapp0010"
$container_name = "cpp-daily-cloud-consumption-report"
$context = New-AzStorageContext -StorageAccountName $storageAccountName -Anonymous
$blobs = Get-AzStorageBlob -Container $container_name -Context $context | sort @{Expression = "LastModified";Descending=$true}
$latestBlob = $blobs[0]
$blob_download_path = New-Item -ItemType Directory -Path "C:\Temp\1\$((Get-Date).ToString('dd-MM-yyyy-hh-mm-ss'))"

$download_csv = Get-AzStorageBlobContent -Container $container_name -Context $context -Blob $blobs[0].Name -Destination $blob_download_path
$abc = Get-ChildItem -Path $blob_download_path.FullName

$Get_CSV_Content = Get-Content $abc.FullName | Select -First 1
$Get_Delimiter = If($Get_CSV_Content.Split(";").Length -gt 1){";"}Else{","};
$Ready_LA_CSV = Import-Csv $abc.FullName -Delimiter $Get_Delimiter

$InfoToImport_Json = $Ready_LA_CSV | ConvertTo-Json

# Trigger the "Function - Post Data" with converted JSON
$params = @{
	CustomerId = $CustomerId
	SharedKey  = $SharedKey
	Body       = ([System.Text.Encoding]::UTF8.GetBytes($InfoToImport_Json))
	LogType    = $Custom_Logs 
}
$LogResponse = Post-LogAnalyticsData @params
Write-Host $LogResponse

*****************************************************************************************************************************************************

	