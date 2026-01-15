<#
.SYNOPSIS
Deploys or destroys the example Bicep templates in this folder.

.DESCRIPTION
This script wraps Azure CLI deployment for the `bicep/modular/main.bicep` template included in this repo.
It is intended for demo/testing use only. The templates are intentionally insecure — see README.md.

.PARAMETER ResourceGroup
Name of the resource group to create/use/destroy. Defaults to rg-iwa-demo.

.PARAMETER Location
Azure location to deploy into. Defaults to eastus.

.PARAMETER AcrName
ACR name to create/use. Defaults to iwadeveus.

.PARAMETER WebAppName
Web App name to create. Defaults to iwa.

.PARAMETER ImageRepo
Container repository name (repo in ACR). Defaults to iwa.

.PARAMETER ImageTag
Image tag to reference. Defaults to latest.

.PARAMETER TemplatePath
Path to the top-level Bicep template. Defaults to ./modular/main.bicep

.PARAMETER WhatIf
If specified, runs an Azure deployment What-If (preview) instead of performing the deployment.

.PARAMETER Destroy
If specified, the script will delete the resource group instead of deploying.

.PARAMETER NoPrompt
Suppresses confirmation prompts for destructive operations.
#>

[CmdletBinding(DefaultParameterSetName = 'Deploy')]
param(
    [string]$ResourceGroup = 'rg-iwa-demo',
    [string]$Location = 'uksouth',
    [string]$AcrName = 'iwadevuks',
    [string]$WebAppName = 'iwa',
    [string]$ImageRepo = 'iwa',
    [string]$ImageTag = 'latest',
    [string]$TemplatePath = './modular/main.bicep',
    [switch]$WhatIf,
    [switch]$Destroy,
    [switch]$NoPrompt,
    [switch]$RequireBicep
)

# --- Compatibility helper functions ---
# Some environments (or earlier scripts) may provide Write-Info/Write-Warn helpers.
# Define lightweight fallbacks so the script works standalone.
if (-not (Get-Command -Name Write-Info -ErrorAction SilentlyContinue)) {
    function Write-Info { param([Parameter(ValueFromRemainingArguments=$true)] $Message)
        if ($PSBoundParameters.ContainsKey('Verbose') -or $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose') -or $global:VerbosePreference -ne 'SilentlyContinue') {
            Write-Verbose $Message
        } else {
            Write-Host $Message -ForegroundColor Cyan
        }
    }
}
if (-not (Get-Command -Name Write-Warn -ErrorAction SilentlyContinue)) {
    function Write-Warn { param([Parameter(Mandatory=$true)] $Message) Write-Warning $Message }
}
if (-not (Get-Command -Name Write-ErrorMsg -ErrorAction SilentlyContinue)) {
    function Write-ErrorMsg { param([Parameter(Mandatory=$true)] $Message) Write-Error $Message }
}
if (-not (Get-Command -Name Write-Success -ErrorAction SilentlyContinue)) {
    function Write-Success { param([Parameter(Mandatory=$true)] $Message) Write-Host $Message -ForegroundColor Green }
}

# Helper: build/compile a Bicep template using the available CLI
function Invoke-BicepBuild {
    param(
        [Parameter(Mandatory=$true)] [string] $TemplatePath,
        [Parameter(Mandatory=$true)] [string] $OutFile
    )

    # Prefer native 'bicep' binary if available; otherwise use 'az bicep'
    $bicepNative = Get-Command bicep -ErrorAction SilentlyContinue
    $azCmd = Get-Command az -ErrorAction SilentlyContinue

    if ($bicepNative) {
        Write-Info "Using native 'bicep' CLI to build '$TemplatePath'..."
        # native bicep: positional file arg, use --outfile
        try {
            $output = & bicep build $TemplatePath --outfile $OutFile 2>&1
            $exit = $LASTEXITCODE
        } catch {
            $output = $_.Exception.Message
            $exit = 1
        }
    } elseif ($azCmd) {
        Write-Info "Using 'az bicep' to build '$TemplatePath'..."
        try {
            $output = & az bicep build --file $TemplatePath --outfile $OutFile 2>&1
            $exit = $LASTEXITCODE
        } catch {
            $output = $_.Exception.Message
            $exit = 1
        }
    } else {
        Write-ErrorMsg "Neither 'bicep' nor 'az' CLI was found to perform a bicep build. Install Bicep or Azure CLI (az)."
        return @{ Success = $false; ExitCode = 2; Output = "Bicep CLI missing" }
    }

    if ($exit -ne 0 -or -not (Test-Path $OutFile)) {
        Write-ErrorMsg "Bicep build failed (exit code $exit). Output:`n$output"
        return @{ Success = $false; ExitCode = $exit; Output = $output }
    }

    Write-Info "Bicep build succeeded; compiled template: $OutFile"
    return @{ Success = $true; ExitCode = 0; Output = $output }
}

# If RequireBicep wasn't explicitly provided, default it to true for strict pre-check behavior (option A)
if (-not $PSBoundParameters.ContainsKey('RequireBicep')) { $RequireBicep = $true }

# Safety reminder
Write-Host ""; Write-Host "[bicep/deploy-bicep.ps1] Starting" -ForegroundColor Cyan
Write-Warn "Templates in this folder are intentionally insecure. Use a disposable subscription/resource group for tests."; Write-Host ""

# Check Azure CLI availability
try {
    az --version > $null 2>&1
} catch {
    Write-ErrorMsg "Azure CLI (az) not found in PATH. Install and sign in (az login) before running this script."; exit 2
}

# Ensure user is logged in
Write-Info "Checking Azure login status..."
$account = az account show --only-show-errors 2>$null | ConvertFrom-Json 2>$null
if (-not $account) {
    Write-Info "Not logged in. Running 'az login'..."
    az login | Out-Null
    $account = az account show --only-show-errors 2>$null | ConvertFrom-Json
    if (-not $account) { Write-ErrorMsg "Failed to authenticate with Azure CLI."; exit 3 }
}

# --- Strict Bicep build pre-check (fail early if Bicep missing or build fails) ---
# This validates the template before doing any resource-group operations so failures are fast and obvious.
$compiledTemplate = $null
$shouldCleanupCompiled = $false

Write-Info "Validating Bicep template and Bicep CLI (strict pre-check)..."
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$templateFullPath = Join-Path $scriptDir $TemplatePath
if (-not (Test-Path $templateFullPath)) {
    Write-ErrorMsg "Template file not found: $templateFullPath"; exit 4
}

if ($templateFullPath -like '*.bicep') {
    $bicepCmd = Get-Command bicep -ErrorAction SilentlyContinue
    if (-not $bicepCmd) {
        if ($RequireBicep) {
            Write-ErrorMsg "Bicep CLI is required but was not found in PATH. Install it with 'az bicep install' or see bicep/README.md for options."; exit 7
        } else {
            Write-Warn "Bicep CLI not found. Proceeding without compilation (Azure CLI may accept .bicep directly if supported)."
        }
    } else {
        Write-Info "Bicep CLI detected. Running a build to validate '$templateFullPath'..."
        try {
            $compiledTemplate = Join-Path $env:TEMP ("bicep-compiled-{0}.json" -f (Get-Random))
            $result = Invoke-BicepBuild -TemplatePath $templateFullPath -OutFile $compiledTemplate
            if (-not $result.Success) {
                Write-ErrorMsg "Bicep build failed. The deployment cannot continue. See bicep/README.md for troubleshooting."; exit 8
            }
            Write-Info "Bicep build succeeded. Using compiled template: $compiledTemplate"
            $shouldCleanupCompiled = $true
            $templateFullPath = $compiledTemplate
        } catch {
            Write-ErrorMsg "Bicep build failed with exception: $_. Deployment aborted."; exit 9
        }
    }
}

# Create resource group if needed
Write-Info "Ensuring resource group '$ResourceGroup' exists in location '$Location'..."
$rg = az group show --name $ResourceGroup --only-show-errors 2>$null | ConvertFrom-Json 2>$null
if (-not $rg) {
    Write-Info "Creating resource group '$ResourceGroup'..."
    az group create --name $ResourceGroup --location $Location --only-show-errors | Out-Null
}

# Resolve absolute template path
# If a compiled template was produced by the pre-check above the $templateFullPath variable already points at it.
if (-not $templateFullPath) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $templateFullPath = Join-Path $scriptDir $TemplatePath
    if (-not (Test-Path $templateFullPath)) {
        Write-ErrorMsg "Template file not found: $templateFullPath"; exit 4
    }
}

# If the template is a .bicep file then require and run the bicep CLI (strict pre-check)
# Skip this compile step if the pre-check already compiled the template.
$bicepCmd = Get-Command bicep -ErrorAction SilentlyContinue
if (($templateFullPath -like '*.bicep') -and (-not $compiledTemplate)) {
    if (-not $bicepCmd) {
        if ($RequireBicep) {
            Write-ErrorMsg "Bicep CLI is required but was not found in PATH. Install it (see bicep/README.md) and try again."; exit 7
        } else {
            Write-Warn "Bicep CLI not found. Attempting to use .bicep file directly with 'az' (may work with newer Azure CLI)."
        }
    } else {
        Write-Info "Bicep CLI detected. Compiling '$templateFullPath' to an ARM template (temporary file)."
        try {
            $compiledTemplate = Join-Path $env:TEMP ("bicep-compiled-{0}.json" -f (Get-Random))
            # Run bicep build and fail if it returns a non-zero exit code
            $result = Invoke-BicepBuild -TemplatePath $templateFullPath -OutFile $compiledTemplate
            if (-not $result.Success) {
                Write-ErrorMsg "Bicep build failed. The deployment cannot continue."; exit 8
            }
            Write-Info "Bicep build succeeded. Using compiled template: $compiledTemplate"
            $shouldCleanupCompiled = $true
            $templateFullPath = $compiledTemplate
        } catch {
            Write-ErrorMsg "Bicep build failed with exception: $_.Deployment aborted."; exit 9
        }
    }
}

# Build parameters for deployment
$paramString = "acrName=$AcrName webAppName=$WebAppName imageRepo=$ImageRepo imageTag=$ImageTag location=$Location"

if ($WhatIf) {
    Write-Info "Running What-If (preview) for deployment to resource group '$ResourceGroup'..."
    $args = @('deployment','group','what-if','--resource-group',$ResourceGroup,'--template-file',$templateFullPath,'--parameters') + $paramString
    # az expects parameters separately; pass as a single string works for simple key=val pairs
    try {
        az deployment group what-if --resource-group $ResourceGroup --template-file $templateFullPath --parameters $paramString
        Write-Success "What-If completed.";
        # cleanup compiled template if we created one
        if ($shouldCleanupCompiled -and $compiledTemplate -and (Test-Path $compiledTemplate)) { Remove-Item $compiledTemplate -Force }
        exit 0
    } catch {
        Write-ErrorMsg "What-If failed: $_";
        if ($shouldCleanupCompiled -and $compiledTemplate -and (Test-Path $compiledTemplate)) { Remove-Item $compiledTemplate -Force }
        exit 5
    }
}

# Perform the deployment
Write-Info "Starting deployment to resource group '$ResourceGroup' using template '$templateFullPath'..."
try {
    az deployment group create --resource-group $ResourceGroup --template-file $templateFullPath --parameters $paramString --only-show-errors
    if ($LASTEXITCODE -eq 0) { Write-Success "Deployment succeeded." } else { Write-ErrorMsg "Deployment completed with exit code $LASTEXITCODE"; if ($shouldCleanupCompiled -and $compiledTemplate -and (Test-Path $compiledTemplate)) { Remove-Item $compiledTemplate -Force }; exit $LASTEXITCODE }
} catch {
    Write-ErrorMsg "Deployment failed: $_";
    if ($shouldCleanupCompiled -and $compiledTemplate -and (Test-Path $compiledTemplate)) { Remove-Item $compiledTemplate -Force }
    exit 6
}

# cleanup compiled template if we created one
if ($shouldCleanupCompiled -and $compiledTemplate -and (Test-Path $compiledTemplate)) {
    Remove-Item $compiledTemplate -Force
}

Write-Host ""; Write-Host "Done." -ForegroundColor Cyan
