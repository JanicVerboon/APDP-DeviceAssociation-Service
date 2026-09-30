<#
.SYNOPSIS
    [Client side] Collects Autopilot Device Preparation (APDP) device link data and sends it to an
    Azure Automation webhook so the device can be associated with the tenant.

.DESCRIPTION
    Runs MdmDiagnosticsTool.exe to export the Autopilot diagnostics cab, extracts it and looks for a
    "*.devicelink.csv" file. This file only gets generated on Windows versions/builds that support
    Autopilot Device Preparation (APDP). If it is missing, the script shows an error message (the
    device most likely does not support APDP) and exits.

    When the file is found, its content (SerialNumber, Manufacturer, Model, Data) is posted as JSON to
    the supplied Azure Automation webhook URI, optionally including the APDP profile (device
    preparation policy) that should be assigned to the device.

.PARAMETER WebhookUri
    Optional. The Azure Automation Webhook URI that receives the device data. Defaults to the
    webhook baked into this script.

.PARAMETER APDPProfileId
    Optional. The id of the Autopilot Device Preparation profile (devicePreparationPolicyId) that
    should be associated with the device.

.PARAMETER CabPath
    Optional. Path where the MdmDiagnosticsTool cab file is created. Defaults to
    C:\Program Files\APDP-DeviceAssociater\AP.cab.

.PARAMETER ExtractPath
    Optional. Path where the cab file is extracted to. Defaults to
    C:\Program Files\APDP-DeviceAssociater\Extracted.

.PARAMETER ResourceGroup
    Optional. Name of the resource group that hosts the Azure Automation Account. Only used to
    enrich the error message if the webhook turns out to be invalid (HTTP 404).

.PARAMETER AutomationAccountName
    Optional. Name of the Azure Automation Account that hosts the runbook/webhook. Only used to
    enrich the error message if the webhook turns out to be invalid (HTTP 404).

.PARAMETER RunbookName
    Optional. Name of the runbook the webhook is linked to. Only used to enrich the error message
    if the webhook turns out to be invalid (HTTP 404).
#>

function Invoke-APDPDeviceAssociation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebhookUri,

        [Parameter(Mandatory = $false)]
        [string]$APDPProfileId,

        [Parameter(Mandatory = $false)]
        [string]$CabPath = "C:\Program Files\APDP-DeviceAssociater\AP.cab",

        [Parameter(Mandatory = $false)]
        [string]$ExtractPath = "C:\Program Files\APDP-DeviceAssociater\Extracted",

        [Parameter(Mandatory = $false)]
        [string]$ResourceGroup,

        [Parameter(Mandatory = $false)]
        [string]$AutomationAccountName,

        [Parameter(Mandatory = $false)]
        [string]$RunbookName
    )

# Load necessary assemblies
Add-Type -AssemblyName System.Windows.Forms

# App folder also hosts the dedicated log file
$appFolder = "C:\Program Files\APDP-DeviceAssociater"
if (-not (Test-Path -Path $appFolder)) {
    New-Item -Path $appFolder -ItemType Directory -Force | Out-Null
}
$logFile = Join-Path -Path $appFolder -ChildPath "apdp_association_log.txt"

function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp | $message"
}

function Show-ErrorAndExit {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Problem,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $false)]
        [string]$TechnicalDetails
    )

    $messageParts = @(
        $Title
        ''
        "PROBLEM`n$Problem"
        "REQUIRED ACTION`n$Action"
    )
    if (-not [string]::IsNullOrWhiteSpace($TechnicalDetails)) {
        $messageParts += "TECHNICAL DETAILS`n$TechnicalDetails"
    }
    $message = $messageParts -join "`n`n"
    Write-Log "ERROR | $Title | Problem: $Problem | Action: $Action$(if ($TechnicalDetails) { " | Details: $TechnicalDetails" })"
    [System.Windows.Forms.MessageBox]::Show($message, 'APDP-DeviceAssociation-Service', 'OK', 'Error') | Out-Null
    exit 1
}

function Get-AutomationDetailsText {
    $details = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) { $details.Add("Resource Group: $ResourceGroup") }
    if (-not [string]::IsNullOrWhiteSpace($AutomationAccountName)) { $details.Add("Automation Account: $AutomationAccountName") }
    if (-not [string]::IsNullOrWhiteSpace($RunbookName)) { $details.Add("Runbook: $RunbookName") }
    if ($details.Count -eq 0) { return "" }
    return "`n`n" + ($details -join "`n")
}

function Invoke-APDPWebhookWithRetry {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Body
    )

    while ($true) {
        try {
            Invoke-RestMethod -Method Post -Body ($Body | ConvertTo-Json) -Uri $WebhookUri -ContentType "application/json"
            Write-Log "REST method invoked successfully."
            return
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            }

            if ($statusCode -eq 404) {
                Show-ErrorAndExit `
                    -Title 'Webhook is no longer valid' `
                    -Problem 'The Azure Automation webhook returned HTTP 404 (Not Found). The webhook may have expired or been deleted.' `
                    -Action "Create a new webhook, update the installation source with the new webhook URI, and reinstall the device using the updated installation media.$(Get-AutomationDetailsText)" `
                    -TechnicalDetails "HTTP status: 404`nWebhook host: $(([System.Uri]$WebhookUri).Host)"
            }

            $errorMessage = $_.Exception.Message
            Write-Log "ERROR | Webhook request failed | Status: $statusCode | Details: $errorMessage"
            $retryMessage = @(
                'Unable to send device association data'
                ''
                'PROBLEM'
                'The device data could not be sent to the Azure Automation webhook.'
                ''
                'REQUIRED ACTION'
                'Check the network connection and select Retry to send the data again. Select Cancel to stop the association.'
                ''
                "TECHNICAL DETAILS`n$errorMessage"
            ) -join "`n"
            $retryResult = [System.Windows.Forms.MessageBox]::Show($retryMessage, 'APDP-DeviceAssociation-Service', 'RetryCancel', 'Error')
            if ($retryResult -eq 'Cancel') {
                Write-Log 'INFO | User cancelled after webhook request failure.'
                exit 1
            }
            Write-Log 'INFO | User selected Retry after webhook request failure.'
        }
    }
}

# Function to check if the URI is reachable using Test-NetConnection
function Test-UriReachable {
    param (
        [string]$Uri
    )
    $uriHost = ([System.Uri]$Uri).Host
    $result = Test-NetConnection -ComputerName $uriHost -Port 443
    Write-Log "NETWORK | Testing webhook host $uriHost on TCP 443 | Reachable: $($result.TcpTestSucceeded)"
    return $result.TcpTestSucceeded
}

Write-Log 'START | APDP-DeviceAssociation-Service client started.'

# Autopilot device preparation requires elevated rights to run MdmDiagnosticsTool
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Show-ErrorAndExit `
        -Title 'Administrator rights required' `
        -Problem 'The client script is not running with elevated permissions.' `
        -Action 'Run the installation workflow as a local administrator or as SYSTEM, then run the association again.' `
        -TechnicalDetails 'MdmDiagnosticsTool.exe requires administrative rights.'
}

# Make sure the target folders exist / are clean
$cabFolder = Split-Path -Path $CabPath -Parent
if (-not (Test-Path -Path $cabFolder)) {
    New-Item -Path $cabFolder -ItemType Directory -Force | Out-Null
}
if (Test-Path -Path $CabPath) {
    Remove-Item -Path $CabPath -Force
}
if (Test-Path -Path $ExtractPath) {
    Remove-Item -Path $ExtractPath -Recurse -Force
}
New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null

# Collect the Autopilot diagnostics cab
Write-Log "Running MdmDiagnosticsTool.exe to collect Autopilot diagnostics."
try {
    $process = Start-Process -FilePath "MdmDiagnosticsTool.exe" -ArgumentList "-area Autopilot -cab `"$CabPath`"" -Wait -PassThru -WindowStyle Hidden
} catch {
    Show-ErrorAndExit `
        -Title 'Autopilot diagnostics could not start' `
        -Problem 'MdmDiagnosticsTool.exe could not be started.' `
        -Action 'Verify that the Windows installation includes MdmDiagnosticsTool.exe and run the installation again.' `
        -TechnicalDetails $_.Exception.Message
}

if ($process.ExitCode -ne 0 -or -not (Test-Path -Path $CabPath)) {
    Show-ErrorAndExit `
        -Title 'Autopilot diagnostics collection failed' `
        -Problem 'The diagnostics tool did not create the expected APDP cab file.' `
        -Action 'Verify the Windows build, administrative context, and write access to the APDP working folder, then reinstall or retry.' `
        -TechnicalDetails "Exit code: $($process.ExitCode)`nExpected cab: $CabPath"
}

# Extract the cab file
Write-Log "Extracting $CabPath to $ExtractPath."
$expandOutput = & expand.exe -F:* "$CabPath" "$ExtractPath" 2>&1
Write-Log "expand.exe output: $expandOutput"

# Look for the devicelink.csv file that indicates APDP support
$deviceLinkFile = Get-ChildItem -Path $ExtractPath -Filter "*.devicelink.csv" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $deviceLinkFile) {
    Show-ErrorAndExit `
        -Title 'Autopilot Device Preparation is not available' `
        -Problem "The diagnostics data does not contain a '*.devicelink.csv' file. This Windows installation most likely does not support APDP device association." `
        -Action 'Reinstall the device using installation media or an image that supports Autopilot Device Preparation.' `
        -TechnicalDetails "Diagnostics folder: $ExtractPath"
}

Write-Log "Found device link file: $($deviceLinkFile.FullName)"

# Parse the CSV (SerialNumber,Manufacturer,Model,Data)
$deviceLinkData = Import-Csv -Path $deviceLinkFile.FullName | Select-Object -First 1

if (-not $deviceLinkData -or [string]::IsNullOrWhiteSpace($deviceLinkData.Data)) {
    Show-ErrorAndExit `
        -Title 'Device-link data is incomplete' `
        -Problem 'The device-link CSV was found, but it does not contain a usable Data value.' `
        -Action 'Collect the diagnostics again. If the problem persists, reinstall using APDP-capable installation media.' `
        -TechnicalDetails "Device-link file: $($deviceLinkFile.FullName)"
}

$serialNumber = $deviceLinkData.SerialNumber
$manufacturer = $deviceLinkData.Manufacturer
$model = $deviceLinkData.Model
$data = $deviceLinkData.Data

Write-Log "Parsed device link data for SerialNumber '$serialNumber', Manufacturer '$manufacturer', Model '$model'."

# Loop to check webhook reachability with a message for user interaction
while (-not (Test-UriReachable -Uri $WebhookUri)) {
    Write-Log "NETWORK | Webhook host is unreachable | Serial: $serialNumber"
    $networkMessage = @(
        'Network connection required'
        ''
        'PROBLEM'
        'The Azure Automation webhook host cannot be reached over HTTPS.'
        ''
        'REQUIRED ACTION'
        "Connect the device to a network, verify serial number $serialNumber, and select Retry. Select Cancel if the device is already associated or the operation should stop."
        ''
        'TECHNICAL DETAILS'
        "Webhook host: $(([System.Uri]$WebhookUri).Host)`nPort: 443"
    ) -join "`n"
    $result = [System.Windows.Forms.MessageBox]::Show($networkMessage, 'APDP-DeviceAssociation-Service', 'RetryCancel', 'Information')
    if ($result -eq 'Cancel') {
        Write-Log 'INFO | User cancelled during network connectivity check.'
        exit
    }
    Write-Log 'INFO | User selected Retry during network connectivity check.'
    Start-Sleep -Seconds 60
}

# Build the payload to send to the Azure Automation webhook
$associationData = [ordered]@{
    SerialNumber = $serialNumber
    Manufacturer = $manufacturer
    Model        = $model
    Data         = $data
}

if (-not [string]::IsNullOrWhiteSpace($APDPProfileId)) {
    $associationData.APDPProfileId = $APDPProfileId
}

Write-Output $associationData

# Invoke the webhook, retrying on transient/network failures
Write-Log "URI reachable. Invoking REST method."
Invoke-APDPWebhookWithRetry -Body $associationData
}

Invoke-APDPDeviceAssociation `
    -WebhookUri "<INSERT_WEBHOOK_URI_HERE>" `
    -APDPProfileId "<INSERT_APDP_PROFILE_ID_HERE>" `
    -ResourceGroup $ResourceGroup `
    -AutomationAccountName $AutomationAccountName `
    -RunbookName $RunbookName
