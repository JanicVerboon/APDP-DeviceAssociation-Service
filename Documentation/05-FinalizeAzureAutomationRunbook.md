# Introduction

This chapter documents the final steps for configuring the Azure Automation runbook.

## Final touches

1. In the **[Azure Portal](https://portal.azure.com)**, navigate to your Azure Automation runbook.
* Scroll to the end of the runbook and configure the runbook parameters. More information about the parameters is provided below.
* ![Image1](/SupportingFiles/05-01.png)
* Publish the runbook.

## Runbook parameters

The public invocation parameters for `Invoke-APDPDeviceImport` are listed below.

| Name | Type | Mandatory | Options / accepted values |
|---|---|---:|---|
| `WebhookData` | `object` | Yes | Azure Automation webhook object. Its `RequestBody` must contain valid JSON with `SerialNumber`, `Manufacturer`, `Model`, and `Data`. It may also contain `APDPProfileId`. >  No need to change anything here as the data is received by the client device. |
| `RemoveExistingHardwareHash` | `switch` | No | Include the switch to delete an existing Windows Autopilot hardware hash matching the device serial number. Omit it to retain the hash. Deletions only happen if the APDP Association works.|
| `TeamsWebhookUri` | `string[]` | No | One or more HTTPS Teams or Power Automate webhook URLs. Omit it to disable Teams notifications. |
| `TeamsEvent` | `string[]` | No | Optional event filter. Accepted values and their meanings are described below. If omitted, all events are reported. |

> **Important** `TeamsWebhookUri` values must use HTTPS.

# Navigation
Previous step [04-[Optional]Setup-TeamsWebhook](/Documentation/04-[Optional]%20Setup-TeamsWebhook.md)


