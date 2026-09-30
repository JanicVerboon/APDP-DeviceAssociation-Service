# Introduction

This chapter documents the setup of the client script, which collects the device-link file and sends it to the Azure Automation runbook configured in [Step 1](./01-Setup-AzureAutomation.md).

## Add the Webhook Data to the Client Script

This step describes how to preconfigure the webhook URI in the client-side script.

1. Open the client [script](/Client/Invoke-APDPDeviceAssociation.ps1).
* Add the webhook URI to the **WebhookUri** parameter at the end of the script.
* ![Image1](/SupportingFiles/02-01.png)

## [Optional] Pre-Configure the Autopilot Device Preparation Policy

This step is optional and can be used if you want to specify an Autopilot Device Preparation policy when adding the device. If you do not specify this value, the device will be pre-associated without a Device Preparation policy assigned. This can be changed later.

1. Go to the **[Intune admin center](https://intune.microsoft.com/#home)** and navigate to **Devices > Windows > Enrollment > Windows Autopilot device preparation > Device preparation policies**.

* ![Image2](/SupportingFiles/02-02.png)

2. Select a device preparation policy created with the new template that supports device association.
* You can verify this by clicking the profile and checking whether the out-of-box settings are available.

| Supported | Not Supported |
| --------- | ------------- |
| ![Image3](/SupportingFiles/02-03.png) | ![Image4](/SupportingFiles/02-04.png) |
| TemplateId: 80d33118-b7b4-40d8-b15f-81be745e053f_1 | 70d256b3-6120-4f88-9e00-0972ec64fc83_1 |

> **Important:** If your current Autopilot Device Preparation policy is not supported, create a new one based on the new template. This will also give you access to the newly available OOBE settings. If you specify an unsupported policy ID, the Azure Automation runbook will validate the provided ID and check whether it was created with the new template.

3. Once you have selected a supported Autopilot device association policy, select it in the Intune portal and copy the URL.
* https://intune.microsoft.com/#view/Microsoft_Intune_Enrollment/DpPropertiesEditor.ReactView/policyName/Windows-COPE-DevicePreparation-Association/policyId/e7dd4e7a-260d-4a7a-84c7-da46c608879b/templateId/70d256b3-6120-4f88-9e00-0972ec64fc83_1 
* Extract the ID of the policy from the **policyId** value. In this example, it is **e7dd4e7a-260d-4a7a-84c7-da46c608879b**.

4. Paste the Autopilot Device Preparation policy ID into the client-side script.

* ![Image5](/SupportingFiles/02-05.png)

## [Optional] Configure Azure Automation Runbook Information 

This step is optional but highly recommended.
Simply add the following information about where you are running the APDP Device Registration Service:
* Resource group
* Azure Automation Account
* Runbook name

This will help you identify where to renew the webhook when it expires.

# Navigation
Previous step [01-Setup-AzureAutomation](/Documentation/01-Setup-AzureAutomation.md)
Next step: [03-Prepare-Installationmedia](/Documentation/03-Prepare-Installationmedia.md)