# Introduction

This chapter provides an overview of the steps required to prepare the Azure Automation Account for the APDP-DeviceAssociation-Service.

> **Note:** To perform this step, you must have Contributor permissions on the resource group where you want to set up the Azure Automation Account.
> You will also require an administrator with Application Administrator permissions to grant permissions to the managed identity of the Azure Automation Account.

## Setup Azure Automation Account

This chapter covers the creation of the Azure Automation Account resource within your resource group.

1. In the **[Azure Portal](https://portal.azure.com)**, navigate to the resource group where you want to deploy the Automation Account.
* Click on **Create**

* ![Image1](/SupportingFiles/01-01.png)

2. Search for **Automation**

* Select the **Automation Solution**


* ![Image2](/SupportingFiles/01-02.png)

3. Select the Subscription where you want to deploy the Solution and select *Create*

* ![Image3](/SupportingFiles/01-03.png)
4. Select the Azure region and define a name for your Automation Account according to your naming convention.

* ![Image4](/SupportingFiles/01-04.png)

5. On the Advanced tab, ensure that the **System-assigned managed identity** is enabled.

* ![Image5](/SupportingFiles/01-05.png)

6. Select public access on the Networking tab.

* ![Image6](/SupportingFiles/01-06.png)

7. **Review + create** the Automation Account.

## Setup Runtime environment & Modules 

This chapter covers the setup of the runtime environment and the installation of the necessary modules.

1. On the newly created Azure Automation Account, navigate to **Process > Automation > Runtime Environments**.
* Select **Create**

* ![Image7](/SupportingFiles/01-07.png)

2. On the Basics tab, configure:
* Name
* Language = PowerShell
* Runtime version = 7.6 

* ![Image8](/SupportingFiles/01-08.png)

3. On the Packages tab, select **Add from Gallery**.

* ![Image9](/SupportingFiles/01-09.png)

4. Add the **Microsoft.Graph.Authentication** module.

* ![Image10](/SupportingFiles/01-10.png)

## Assign Managed Identity Permissions

This chapter covers the assignment of the required managed identity permissions.

1. On your Azure Automation Account, navigate to **Account Settings > Identity**.
* Note down the **Object (principal) ID**.

* ![Image11](/SupportingFiles/01-11.png)

2. Add it to the script below by replacing the placeholder value for **managedIdentityObjectId**.

``` powershell
#requires -module Microsoft.Graph.Authentication,Microsoft.Graph.Applications

Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All", "Application.Read.All"

$managedIdentityObjectId = "<ManagedIdentityObjectId>"
$permissions = "DeviceManagementServiceConfig.ReadWrite.All", "Device.Read.All","DeviceManagementConfiguration.Read.All"

$graphApi = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$permissions = $graphApi.AppRoles | Where-Object { $_.Value -in $permissions -and $_.AllowedMemberTypes -contains "Application" }

$permissions | ForEach-Object {

    $appRoleAssignment = @{
        ServicePrincipalId = $managedIdentityObjectId
        PrincipalId        = $managedIdentityObjectId
        ResourceId         = $graphApi.Id 
        AppRoleId          = $PSItem.Id 
    }

    New-MgServicePrincipalAppRoleAssignment @appRoleAssignment
}
```
> **Note:** Run the above script on a device of your choice that has the required modules installed. The user running the script must have at least the Application Administrator permission. The script adds the necessary permissions to the managed identity of the Automation Account so it can run the service.

3. After running the script, navigate to the **[Entra ID Portal](https://entra.microsoft.com/#home) > Enterprise apps**.
* Search for the ID of your managed identity.

* ![Image12](/SupportingFiles/01-12.png)

4. On the selected enterprise application, select **Security > Permissions**.
* Verify that the required permissions have been granted.

* ![Image13](/SupportingFiles/01-13.png)

## Create Azure Automation Runbook

This chapter describes the steps to set up the Azure Automation runbook.

1. On the Azure Automation Account, navigate to **Process Automation > Runbooks**.
* Select **Create**

* ![Image14](/SupportingFiles/01-14.png)

2. Create a new runbook:
* Give the runbook a name.
* Select the runbook type: **PowerShell**.
* Select the previously created runbook environment.
* Select **Review + create**.

* ![Image15](/SupportingFiles/01-15.png)

3. The runbook will now be created.
* Copy the runbook code from [Invoke-APDPDeviceImport.ps1](/AzureAutomation/Invoke-APDPDeviceImport.ps1) and paste it into the runbook.
* Click **Save**.

* ![Image16](/SupportingFiles/01-16.png)

> **Important:** Publish the script, don't modify anything as of yet, this will follow later in the setup guide. 


## Create Azure Webhook

This chapter covers the creation of the Azure Automation runbook webhook, which the device-side script will use to submit information to the Azure Automation runbook.

1. On the newly published runbook, navigate to **Resources > Webhooks**.
* Select **Add Webhook**.
* ![Image17](/SupportingFiles/01-17.png)

2. Configure the webhook:
* Provide a name.
* Define how long the webhook is valid.
* Copy the webhook URI and save it in a Key Vault or password manager. You will not be able to view it after creating the webhook, and you will need it later to configure the client-side script.
* Click **Configure Parameters and Run Settings**.
* ![Image18](/SupportingFiles/01-18.png)

> **Important:** Also ensure that you document the expiry date of the Webhook within your IT Operations manual. If the Webhook expires the whole logic will fail and new devices will no longer be processed!

3. Configure the parameter settings as follows:
* Set `WebhookData` to **""**.
* Click **Update**.
* ![Image19](/SupportingFiles/01-19.png)

4. Click **Create** to create the webhook.

# Navigation

Next step: [02-Prepare-ClientSetupScript](/Documentation/02-Prepare-ClientSetupScript)