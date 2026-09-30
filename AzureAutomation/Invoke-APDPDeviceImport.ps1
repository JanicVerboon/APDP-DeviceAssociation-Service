#Requires -Module Microsoft.Graph.Authentication

param (
    [Parameter(Mandatory = $true)]
    [object]$WebhookData,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveExistingHardwareHash,

    [Parameter(Mandatory = $false)]
    [string[]]$TeamsWebhookUri,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Added', 'Updated', 'NoChangeRequired', 'HardwareHashRemoved', 'Failed')]
    [string[]]$TeamsEvent
)

# The APDP device preparation policies are configuration policies based on this enrollment template
$deviceLinkImportUri = "https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice"
$apdpProfilesUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$select=id,name,description,platforms,lastModifiedDateTime,technologies,settingCount,roleScopeTagIds,isAssigned,templateReference,priorityMetaData%20&$top=100%20&$filter=(technologies%20has%20%27enrollment%27)%20and%20(platforms%20eq%20%27windows10%27)%20and%20(TemplateReference/templateId%20eq%20%2770d256b3-6120-4f88-9e00-0972ec64fc83_1%27)%20and%20(Templatereference/templateFamily%20eq%20%27enrollmentConfiguration%27)%20"

function Get-MgGraphAllPages {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri

    while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
        $response = Invoke-MgGraphRequest -Uri $nextUri -Method GET
        if ($response.value) {
            $results.AddRange([object[]]$response.value)
        }
        $nextUri = $response.'@odata.nextLink'
    }

    return $results
}

function Send-APDPTeamsNotification {
    <#
    .SYNOPSIS
        Posts an adaptive card to one or more Teams webhooks summarizing an APDP association result.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$TeamsWebhookUri,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Added', 'Updated', 'NoChangeRequired', 'HardwareHashRemoved', 'Failed')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$SerialNumber,

        [Parameter(Mandatory = $false)]
        [string]$Manufacturer,

        [Parameter(Mandatory = $false)]
        [string]$Model,

        [Parameter(Mandatory = $false)]
        [string]$NewApdpProfileName,

        [Parameter(Mandatory = $false)]
        [string]$OldApdpProfileName,

        [Parameter(Mandatory = $false)]
        [switch]$HardwareHashRemoved,

        [Parameter(Mandatory = $false)]
        [switch]$HardwareHashExists,

        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $false)]
        [string[]]$TeamsEvent
    )

    if ($TeamsEvent -and $TeamsEvent -notcontains $Action) {
        Write-Output "Teams notification skipped for event '$Action'; configured events: $($TeamsEvent -join ', ')."
        return
    }

    $titleText = switch ($Action) {
        'Added' { 'New device associated with APDP' }
        'Updated' { 'APDP profile updated for existing device' }
        'NoChangeRequired' { 'Device already associated with APDP - no change required' }
        'HardwareHashRemoved' { 'Windows Autopilot Hardware Hash removed' }
        'Failed' { 'APDP device association failed' }
    }

    $contextText = switch ($Action) {
        'Added' { 'The device-link was accepted and the device was added to the tenant association service.' }
        'Updated' { 'The device was already associated. Its Device Preparation profile was changed to the requested profile.' }
        'NoChangeRequired' { 'The device association and requested Device Preparation profile were already current.' }
        'HardwareHashRemoved' { 'The APDP association was already current. A Windows Autopilot Hardware Hash record was removed as requested.' }
        'Failed' { 'The association workflow did not complete. Review the error below and the Azure Automation job output.' }
    }

    $titleColor = switch ($Action) {
        'Failed' { 'Attention' }
        'Updated' { 'Warning' }
        'HardwareHashRemoved' { 'Warning' }
        default { 'Good' }
    }

    $accentColor = '#0078D4'
    $logoPath = 'M21.25 16.5a.75.75 0 0 1 .1 1.5H16.5v-1.5h4.75ZM4 10h1.5V6.75c0-.14.11-.25.25-.25h12.5c.14 0 .25.11.25.25v7.5c0 .14-.11.25-.25.25H16.5V16h1.75c.97 0 1.75-.78 1.75-1.75v-7.5C20 5.78 19.22 5 18.25 5H5.75C4.78 5 4 5.78 4 6.75V10Zm3.75 7a.75.75 0 0 0 0 1.5h2.5a.75.75 0 0 0 0-1.5h-2.5Zm-3.5-6C3.01 11 2 12 2 13.25v5.5C2 19.99 3 21 4.25 21h9c1.24 0 2.25-1 2.25-2.25v-5.5c0-1.24-1-2.25-2.25-2.25h-9Zm-.75 2.25c0-.41.34-.75.75-.75h9c.41 0 .75.34.75.75v5.5c0 .41-.34.75-.75.75h-9a.75.75 0 0 1-.75-.75v-5.5Z'
    $logoSvg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='$logoPath' fill='$accentColor'/></svg>"
    $logoUri = "data:image/svg+xml,$([System.Uri]::EscapeDataString($logoSvg))"

    $facts = [System.Collections.Generic.List[object]]::new()
    $facts.Add(@{ title = 'Serial Number'; value = [string]$SerialNumber })
    if ($Manufacturer) { $facts.Add(@{ title = 'Manufacturer'; value = [string]$Manufacturer }) }
    if ($Model) { $facts.Add(@{ title = 'Model'; value = [string]$Model }) }

    if ($Action -eq 'Updated') {
        $facts.Add(@{ title = 'Previous APDP Profile'; value = [string]$(if ($OldApdpProfileName) { $OldApdpProfileName } else { 'None' }) })
        $facts.Add(@{ title = 'New APDP Profile'; value = [string]$(if ($NewApdpProfileName) { $NewApdpProfileName } else { 'None' }) })
    }
    elseif ($NewApdpProfileName) {
        $facts.Add(@{ title = 'APDP Profile'; value = $NewApdpProfileName })
    }

    if ($HardwareHashRemoved) {
        $facts.Add(@{ title = 'Windows Autopilot Hardware Hash'; value = 'Deleted successfully' })
    }
    elseif ($HardwareHashExists) {
        $facts.Add(@{ title = 'Windows Autopilot Hardware Hash'; value = 'Found and retained; RemoveExistingHardwareHash was not enabled' })
    }

    if ($Action -eq 'Failed' -and $ErrorMessage) {
        $facts.Add(@{ title = 'Error'; value = $ErrorMessage })
    }

    $card = @{
        type        = 'message'
        attachments = @(
            @{
                contentType = 'application/vnd.microsoft.card.adaptive'
                contentUrl  = $null
                content     = @{
                    '$schema' = 'http://adaptivecards.io/schemas/adaptive-card.json'
                    type      = 'AdaptiveCard'
                    version   = '1.5'
                    msteams   = @{ width = 'Full' }
                    body      = @(
                        @{
                            type    = 'ColumnSet'
                            spacing = 'Medium'
                            columns = @(
                                @{
                                    type  = 'Column'
                                    width = 'auto'
                                    items = @(
                                        @{
                                            type   = 'Image'
                                            url    = $logoUri
                                            size   = 'Medium'
                                            style  = 'Default'
                                            altText = 'APDP device association'
                                        }
                                    )
                                },
                                @{
                                    type  = 'Column'
                                    width = 'stretch'
                                    items = @(
                                        @{
                                            type   = 'TextBlock'
                                            weight = 'Bolder'
                                            size   = 'Large'
                                            text   = 'APDP-DeviceAssociation-Service'
                                            wrap   = $true
                                        },
                                        @{
                                            type      = 'TextBlock'
                                            spacing   = 'Small'
                                            isSubtle  = $true
                                            text      = $titleText
                                            color     = $titleColor
                                            wrap      = $true
                                        }
                                    )
                                }
                            )
                        },
                        @{
                            type      = 'TextBlock'
                            spacing   = 'Medium'
                            separator = $true
                            text      = $contextText
                            wrap      = $true
                        },
                        @{
                            type      = 'TextBlock'
                            spacing   = 'Small'
                            text      = "Processed $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
                            isSubtle  = $true
                            wrap      = $true
                        },
                        @{
                            type  = 'FactSet'
                            facts = $facts
                        }
                    )
                }
            }
        )
    } | ConvertTo-Json -Depth 20

    foreach ($uri in $TeamsWebhookUri) {
        try {
            $parsedUri = [System.Uri]$uri
            if ($parsedUri.Scheme -ne 'https') {
                throw 'Teams webhook URI must use HTTPS.'
            }

            Write-Output "Sending Teams notification for action '$Action' and serial '$SerialNumber'."
            Invoke-RestMethod -Uri $uri -Method POST -Body $card -ContentType 'application/json'
            Write-Output "Teams notification sent successfully for action '$Action' and serial '$SerialNumber'."
        }
        catch {
            Write-Warning "Could not send the Teams notification for action '$Action' and serial '$SerialNumber'. Error: $($_.Exception.Message)"
        }
    }
}

function Invoke-APDPDeviceImport {
    <#
    .SYNOPSIS
        [Azure Automation runbook] Receives the incoming APDP device webhook data and associates the
        device with the tenant using the Autopilot Device Preparation (APDP) Microsoft Graph API.

    .DESCRIPTION
        Expects a webhook payload containing SerialNumber, Manufacturer, Model and Data (the base64
        encoded device link generated on the client), and optionally an APDPProfileId
        (devicePreparationPolicyId).

        Flow:
          1. Connect to Microsoft Graph using the Automation Account's managed identity.
          2. Retrieve all tenant associated devices (paging through @odata.nextLink) and check whether
             the device (by SerialNumber) is already associated with the tenant.
          3. If an APDPProfileId was supplied, verify it actually exists as a device preparation policy;
             if not, ignore it and proceed without a profile.
          4. If the device exists, update the APDP profile (devicePreparationPolicyId) only if it differs.
          5. If it does not exist, import it via importTenantAssociatedDevice (expects 201 on success,
             409 if the device was created concurrently), optionally with the supplied APDP profile.
          6. Check whether the device's serial number is registered in Windows Autopilot Hardware Hash
             (windowsAutopilotDeviceIdentities); delete that record only when
             -RemoveExistingHardwareHash is specified.
          7. If -TeamsWebhookUri is supplied, posts an adaptive card to the given Teams channel(s)
             summarizing the outcome (new association, profile update, no change, or failure),
             including the APDP profile name(s) and Windows Autopilot Hardware Hash status.

    .PARAMETER WebhookData
        The Azure Automation webhook payload (see DESCRIPTION for the expected fields).

    .PARAMETER RemoveExistingHardwareHash
        Optional switch. When set, deletes a Windows Autopilot Hardware Hash record
        (windowsAutopilotDeviceIdentities) matching the device's serial number.

    .PARAMETER TeamsWebhookUri
        Optional. One or more Teams (or Power Automate) webhook URLs that receive an adaptive card
        summarizing the outcome of the device association.

    .PARAMETER TeamsEvent
        Optional. One or more event names to report to Teams. Supported values are Added, Updated,
        NoChangeRequired, HardwareHashRemoved, and Failed. If omitted, every event is reported.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$WebhookData,

        [Parameter(Mandatory = $false)]
        [switch]$RemoveExistingHardwareHash,

        [Parameter(Mandatory = $false)]
        [string[]]$TeamsWebhookUri,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Added', 'Updated', 'NoChangeRequired', 'HardwareHashRemoved', 'Failed')]
        [string[]]$TeamsEvent
    )

    Write-Output $WebHookData.RequestBody

    $webhookRequestBody = ConvertFrom-Json -InputObject $WebHookData.RequestBody -ErrorAction Stop

    if ($null -eq $webhookRequestBody -or $webhookRequestBody -isnot [pscustomobject]) {
        throw 'The webhook RequestBody must be a JSON object.'
    }

    $requiredWebhookProperties = @('SerialNumber', 'Manufacturer', 'Model', 'Data')
    foreach ($propertyName in $requiredWebhookProperties) {
        $property = $webhookRequestBody.PSObject.Properties[$propertyName]
        if ($null -eq $property -or $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw "The webhook RequestBody is invalid. Required property '$propertyName' must be a non-empty string."
        }
    }

    if ($webhookRequestBody.PSObject.Properties['APDPProfileId'] -and $null -ne $webhookRequestBody.APDPProfileId -and $webhookRequestBody.APDPProfileId -isnot [string]) {
        throw "The webhook RequestBody is invalid. Optional property 'APDPProfileId' must be a string when supplied."
    }

    Write-Output 'Connecting to Microsoft Graph using the Automation Account managed identity.'
    Connect-MgGraph -Identity -NoWelcome
    $graphContext = Get-MgContext
    if ($null -eq $graphContext) {
        throw 'Microsoft Graph authentication did not return a context.'
    }
    if ([string]::IsNullOrWhiteSpace($graphContext.TenantId)) {
        throw 'Microsoft Graph authentication returned no tenant ID.'
    }
    Write-Output "Microsoft Graph authentication succeeded for tenant $($graphContext.TenantId)."

    $deviceSerial = [string]$webhookRequestBody.SerialNumber
    $deviceLink = [string]$webhookRequestBody.Data
    $manufacturer = [string]$webhookRequestBody.Manufacturer
    $model = [string]$webhookRequestBody.Model
    $apdpProfileId = if ($webhookRequestBody.PSObject.Properties['APDPProfileId']) { [string]$webhookRequestBody.APDPProfileId } else { $null }

    if ([string]::IsNullOrWhiteSpace($deviceSerial)) {
        throw "The webhook payload did not contain a SerialNumber."
    }
    if ([string]::IsNullOrWhiteSpace($deviceLink)) {
        throw "The webhook payload did not contain the device link Data."
    }

    Write-Output "Processing device with Serial $deviceSerial"

    $apdpProfiles = @()
    $hardwareHashRemoved = $false
    $hardwareHashExists = $false
    $windowsAutopilotHardwareHashDevice = $null

    try {
        if ($TeamsEvent) {
            Write-Output "Teams notifications configured for event(s): $($TeamsEvent -join ', ')."
        }
        else {
            Write-Output 'Teams notifications configured for all event types.'
        }

        Write-Output "Checking for an existing Windows Autopilot Hardware Hash record for serial $deviceSerial..."
        $windowsAutopilotHardwareHashDevices = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
        $windowsAutopilotHardwareHashDevice = $windowsAutopilotHardwareHashDevices | Where-Object { $_.serialNumber -eq $deviceSerial } | Select-Object -First 1

        if ($null -eq $windowsAutopilotHardwareHashDevice) {
            Write-Output "No existing Windows Autopilot Hardware Hash record found for serial $deviceSerial."
        }
        else {
            $hardwareHashExists = $true
            Write-Output "Found existing Windows Autopilot Hardware Hash record (id: $($windowsAutopilotHardwareHashDevice.id))."

            if ($RemoveExistingHardwareHash) {
                Write-Output "Found existing Windows Autopilot Hardware Hash record (id: $($windowsAutopilotHardwareHashDevice.id)). Deleting it..."
                Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($windowsAutopilotHardwareHashDevice.id)" -Method DELETE
                Write-Output "Existing Windows Autopilot Hardware Hash record deleted successfully."
                $hardwareHashRemoved = $true
            }
            else {
                Write-Output 'Windows Autopilot Hardware Hash record was retained because RemoveExistingHardwareHash was not enabled.'
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($apdpProfileId)) {
            Write-Output "Validating APDP profile $apdpProfileId..."
            $apdpProfiles = Get-MgGraphAllPages -Uri $apdpProfilesUri
            if ($apdpProfileId -notin $apdpProfiles.id) {
                Write-Output "APDP profile $apdpProfileId was not found among the existing device preparation policies. Proceeding without an APDP profile."
                $apdpProfileId = $null
            }
            else {
                Write-Output "APDP profile $apdpProfileId is valid."
            }
        }

        Write-Output "Retrieving all tenant associated devices..."
        $tenantAssociatedDevices = Get-MgGraphAllPages -Uri "https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices"
        Write-Output "Retrieved $($tenantAssociatedDevices.Count) tenant associated devices."

        $existingDevice = $tenantAssociatedDevices | Where-Object { $_.serialNumber -eq $deviceSerial } | Select-Object -First 1

        $notificationAction = 'NoChangeRequired'
        $newProfileName = if ($apdpProfileId) { ($apdpProfiles | Where-Object { $_.id -eq $apdpProfileId } | Select-Object -First 1).name } else { $null }
        $oldProfileName = $null

        if ($null -eq $existingDevice) {
            Write-Output "Device does not exist, will now proceed with the device association import."

            $importBody = @{
                deviceLink = $deviceLink
            }
            if (-not [string]::IsNullOrWhiteSpace($apdpProfileId)) {
                $importBody.devicePreparationPolicyId = $apdpProfileId
            }

            $importResult = Invoke-MgGraphRequest -Uri $deviceLinkImportUri -Method POST -Body ($importBody | ConvertTo-Json) -StatusCodeVariable "importStatusCode" -SkipHttpErrorCheck

            switch ($importStatusCode) {
                201 {
                    Write-Output "Device imported successfully."
                    Write-Output ($importResult | ConvertTo-Json -Depth 5)
                    $notificationAction = 'Added'
                }
                409 {
                    Write-Output "Device already exists (409 conflict). Nothing further to do."
                    $notificationAction = 'NoChangeRequired'
                }
                default {
                    throw "Device import failed with status code $importStatusCode. Response: $($importResult | ConvertTo-Json -Depth 5)"
                }
            }
        }
        else {
            Write-Output "Device already exists! Current tenant associated device id is $($existingDevice.id)"

            if ([string]::IsNullOrWhiteSpace($apdpProfileId)) {
                Write-Output "No valid APDPProfileId was supplied in the webhook payload, no update required."
            }
            elseif ($existingDevice.devicePreparationPolicyId -eq $apdpProfileId) {
                Write-Output "Current APDP profile ($($existingDevice.devicePreparationPolicyId)) already matches the requested profile ($apdpProfileId). No update required."
            }
            else {
                Write-Output "Current APDP profile ($($existingDevice.devicePreparationPolicyId)) does not match the requested profile ($apdpProfileId). Updating..."

                $oldProfileName = ($apdpProfiles | Where-Object { $_.id -eq $existingDevice.devicePreparationPolicyId } | Select-Object -First 1).name

                $updateBody = @{
                    devicePreparationPolicyId = $apdpProfileId
                }

                Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/$($existingDevice.id)" -Method PATCH -Body ($updateBody | ConvertTo-Json)
                Write-Output "APDP profile updated successfully."
                $notificationAction = 'Updated'
            }

            if ($hardwareHashRemoved -and $notificationAction -eq 'NoChangeRequired') {
                $notificationAction = 'HardwareHashRemoved'
                Write-Output 'The APDP association required no change, but Windows Autopilot Hardware Hash removal is a reportable change.'
            }
        }

        if ($TeamsWebhookUri) {
            Write-Output "Preparing Teams notification with action '$notificationAction'."
            Send-APDPTeamsNotification -TeamsWebhookUri $TeamsWebhookUri -Action $notificationAction -SerialNumber $deviceSerial -Manufacturer $manufacturer -Model $model -NewApdpProfileName $newProfileName -OldApdpProfileName $oldProfileName -HardwareHashRemoved:$hardwareHashRemoved -HardwareHashExists:$hardwareHashExists -TeamsEvent $TeamsEvent
            Write-Output 'Teams notification processing completed.'
        }
    }
    catch {
        if ($TeamsWebhookUri) {
            Write-Output "Preparing failure Teams notification for serial '$deviceSerial'."
            Send-APDPTeamsNotification -TeamsWebhookUri $TeamsWebhookUri -Action 'Failed' -SerialNumber $deviceSerial -Manufacturer $manufacturer -Model $model -HardwareHashRemoved:$hardwareHashRemoved -HardwareHashExists:$hardwareHashExists -ErrorMessage $_.Exception.Message -TeamsEvent $TeamsEvent
        }
        throw
    }
}

Invoke-APDPDeviceImport `
    -WebhookData $WebhookData `
    #-RemoveExistingHardwareHash `
    -TeamsWebhookUri "<INSERT_TEAMS_WEBHOOK_URI_HERE>" `
    -TeamsEvent $TeamsEvent
