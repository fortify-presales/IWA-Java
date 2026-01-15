bicep/README.md

Purpose
-------
This folder contains example Bicep templates and helper scripts used to deploy a sample web application (container-based) to Azure. The templates and helper scripts in this folder are intended for demonstration and security-testing purposes only.

Important safety note
---------------------
- The templates are intentionally insecure and may include misconfigurations on purpose for training and scanning exercises. Do not deploy them into a production subscription.
- Use an isolated, disposable Azure subscription or a dedicated resource group and clean up resources after testing.

Prerequisites
-------------
- Azure CLI (az) installed and authenticated (az login).
- PowerShell (Windows PowerShell or PowerShell Core) to run `deploy-bicep.ps1`.
- Bicep CLI for strict template validation (recommended). The `deploy-bicep.ps1` script includes a strict Bicep build pre-check by default and will fail if Bicep is not present. You can override this behavior with `-RequireBicep:$false`.

Installing the Bicep CLI
------------------------
Recommended: install via the Azure CLI (cross-platform):

PowerShell / Command Prompt:

```powershell
az bicep install
az bicep version
```

Alternative (Windows):
- winget: `winget install --id Microsoft.Bicep -e`
- Chocolatey: `choco install bicep`
- Manual: download the `bicep` binary from the Bicep releases page and place it on your PATH: https://github.com/Azure/bicep/releases

Mac / Linux:
- az bicep install (requires Azure CLI)
- or follow manual install instructions on the Bicep repo releases page.

Verifying the Bicep CLI
-----------------------
After installation, verify it is available from your shell:

```powershell
bicep --version
```

If `bicep` is not found but `az` is installed you can install it with `az bicep install` as shown above.

Script: `deploy-bicep.ps1` overview
----------------------------------
This script is a light wrapper around `az deployment group` for the templates in this folder. Key behavior and options:

- Strict build pre-check: by default the script requires the Bicep CLI and runs `bicep build` to validate the template before attempting any Azure operations. This fails fast and surfaces syntax/type errors early.
- If compilation succeeds, the script uses the compiled ARM JSON for the deployment. Temporary compiled files are removed when the script exits.
- Parameters (defaults shown):
  - `-ResourceGroup 'rg-iwa-demo'`
  - `-Location 'eastus'`
  - `-AcrName 'iwadeveus'`
  - `-WebAppName 'iwa'`
  - `-ImageRepo 'iwa'`
  - `-ImageTag 'latest'`
  - `-TemplatePath './modular/main.bicep'`
  - `-WhatIf` run an Azure What-If preview instead of performing the deployment
  - `-Destroy` delete the resource group
  - `-NoPrompt` suppress confirmations
  - `-RequireBicep` explicitly require the Bicep CLI (the script defaults to requiring it)

Usage examples
--------------
Open PowerShell in this repo and run:

# Deploy (default behavior)
```powershell
.\bicep\deploy-bicep.ps1 -ResourceGroup rg-iwa-demo -Location eastus -AcrName iwadeveus -WebAppName iwajava -ImageRepo iwa -ImageTag latest
```

# Preview changes (What-If) without making any changes
```powershell
.\bicep\deploy-bicep.ps1 -ResourceGroup rg-iwa-demo -WhatIf
```

# Destroy the resource group (non-recoverable); use -NoPrompt to skip confirmation
```powershell
.\bicep\deploy-bicep.ps1 -ResourceGroup rg-iwa-demo -Destroy -NoPrompt
```

# If you do not have the Bicep CLI and want to continue anyway
```powershell
.\bicep\deploy-bicep.ps1 -RequireBicep:$false
```

Notes and troubleshooting
-------------------------
- "Bicep CLI not found" or "Bicep build failed" errors:
  - Ensure `bicep` is installed and on your PATH. Run `bicep --version` to verify.
  - If the project templates use newer language features you may need to update the Bicep CLI to a recent version: `az bicep upgrade` or re-run your installer package manager.

- "Azure CLI not found" or authentication failures:
  - Install `az` (Azure CLI) and sign in with `az login` before running the script.
  - The script tries to call `az account show` and will invoke `az login` if no account is present.

- Permission or quota errors during deployment:
  - The templates may create App Service plans, ACRs, and other resources which could require subscription-level permissions. If you hit permission errors, use an account with Owner/Contributor rights on the target subscription.

- Cleaning up resources:
  - Use the `-Destroy` option in `deploy-bicep.ps1` to delete the resource group created for the demo.
  - Manually remove resources via `az group delete --name rg-iwa-demo --yes --no-wait` if necessary.

Security and intentional vulnerabilities
--------------------------------------
- The templates and scripts in this folder are intentionally permissive and may contain insecure defaults. Examples that may appear include:
  - Application settings exposing secrets in plain text (for demo scanning tools)
  - Weak access controls or broad role assignments
  - Disabled SSL/TLS enforcement or permissive firewall rules

Document any intentional vulnerabilities in `bicep/README.md` or in a per-template README in the same folder. Treat them as training/data for security scanners — do not leak real secrets into templates.

Example developer workflow
--------------------------
1. Ensure tools are installed: Azure CLI and Bicep CLI.
2. Build and validate templates locally with the script's pre-check: `.\bicep\deploy-bicep.ps1 -WhatIf`.
3. When happy, run a real deployment.
4. After testing, destroy resources with `.\bicep\deploy-bicep.ps1 -Destroy -NoPrompt`.

Further reading
---------------
- Bicep project: https://github.com/Azure/bicep
- Bicep docs: https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview

