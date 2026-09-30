# Introduction

This chapter describes the steps required to prepare the installation media for the device association service.

> **Information:** The following steps describe the procedure for implementing the solution with a bootable USB stick, but you can apply the same logic to any installation medium used for Autopilot provisioning.

1. On your installation media, create the following folder path: **Sources\$OEM$\$$\Panther\Unattend**. Copy **[unattend.xml](/Client/unattend.xml)** into the folder.

* ![Image1](/SupportingFiles/03-01.png)

2. On your installation media, create the following folder path: **Sources\$OEM$\$$\Temp**. Copy **[Invoke-APDPDeviceAssociation.ps1](/Client/Invoke-APDPDeviceAssociation.ps1)** into the folder.

* ![Image2](/SupportingFiles/03-02.png)

# Navigation
Previous step [02-Prepare-ClientSetupScript](/Documentation/02-Prepare-ClientSetupScript.md)
Next step: [04-[Optional]Setup-TeamsWebhook](/Documentation/04-[Optional]%20Setup-TeamsWebhook.md)

