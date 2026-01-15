<#
.SYNOPSIS
  Build (optional), push a Docker image to Azure Container Registry (ACR) and deploy it to an Azure Web App.
.DESCRIPTION
  Cross-platform PowerShell script (works with Windows PowerShell and PowerShell Core/pwsh). Requires Docker and Azure CLI (az) installed and authenticated (az login).
  - Optionally builds a local Docker image (uses local Dockerfile).
  - Tags and pushes the image to the specified ACR.
  - Creates resource group / app service plan / web app if missing.
  - Configures the Web App to pull the image from ACR using ACR credentials.
.PARAMETER ResourceGroup
  Azure resource group name.
.PARAMETER AcrName
  Azure Container Registry name (short name, without ".azurecr.io").
.PARAMETER AppName
  Azure Web App name.
.PARAMETER ImageName
  Local image name (repository portion). Example: iwa or myapp/iwa.
.PARAMETER Tag
  Image tag to use (default: latest).
.PARAMETER Location
  Azure location (default: eastus).
.PARAMETER PlanName
  App Service plan name (default: "${AppName}-plan").
.PARAMETER Sku
  App Service plan SKU (default: B1).
.PARAMETER Build
  Switch. If present, runs `docker build` to create the local image before pushing.
.PARAMETER Dockerfile
  Path to Dockerfile to use when building (default: Dockerfile in current directory).
.EXAMPLE
  ./deploy.ps1 -ResourceGroup my-rg -AcrName myacr -AppName myapp -ImageName iwa -Build
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup,
    [string]$AcrName,
    [string]$AppName,
    [string]$ImageName,
    [string]$Tag,
    [string]$Location,
    [string]$PlanName,
    [string]$Sku,
    [switch]$Build,
    [string]$Dockerfile,
    [string]$AcrUser,
    [string]$AcrPass,
    [switch]$WhatIfConfig
    , [switch]$WaitFor
    , [int]$WaitTimeoutSeconds = 300
    , [int]$WaitIntervalSeconds = 5
)

function Fail($msg){ Write-Error $msg; exit 1 }
function Info($msg){ Write-Host $msg }

# Announce start
Write-Host "=== Deploy Script Starting ===" -ForegroundColor Yellow

# Step 1: prerequisites
Write-Host "[1/8] Checking prerequisites..." -ForegroundColor Yellow

# Basic prerequisites
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Fail "Azure CLI 'az' not found. Install it and run 'az login'." }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail "Docker CLI 'docker' not found." }
Write-Host "Prerequisites OK." -ForegroundColor Green

# Step 2: resolve and prompt for parameters
Write-Host "[2/8] Resolving configuration and parameters (CLI > Environment > deploy.config) prompts..." -ForegroundColor Yellow

# Load deploy.config (if present)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir 'deploy.config'
$config = @{}
$sectionMap = @{}
if (Test-Path $configPath) {
    Write-Host "Loading configuration from $configPath" -ForegroundColor Yellow
    $currentSection = $null
    Get-Content $configPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) {
            if ($line -match '^\[(.+)\]$') {
                $currentSection = $matches[1].Trim()
            } else {
                $parts = $line -split '=', 2
                if ($parts.Length -eq 2) {
                    $k = $parts[0].Trim()
                    $v = $parts[1].Trim()
                    # Don't overwrite an existing non-empty value with an empty value from a later section block
                    if (-not ($config.ContainsKey($k) -and $config[$k] -and -not $v)) {
                        $config[$k] = $v
                    }
                    if ($currentSection) { $sectionMap[$k] = $currentSection }
                }
            }
        }
    }
} else {
    Write-Host "No deploy.config found at $configPath (this is optional)." -ForegroundColor Yellow
}

# Helper: convert parameter name to UPPER_SNAKE (e.g., AcrName -> ACR_NAME)
function To-SnakeUpper([string]$name) {
    if (-not $name) { return $null }
    # Two-step regex conversion: handle Uppercase+lowercase word boundaries first, then lowercase->Uppercase transitions
    $s = [regex]::Replace($name, '(.)([A-Z][a-z]+)', '$1_$2')
    $s = [regex]::Replace($s, '([a-z0-9])([A-Z])', '$1_$2')
    $s = $s -replace '[^A-Za-z0-9_]', '_'
    return $s.ToUpper()
}

# Helper: build env var name from section and parameter
function Build-EnvName([string]$section, [string]$param) {
    $p = To-SnakeUpper $param
    if ($section) {
        $sec = $section.ToUpper()
        return "${sec}_${p}"
    }
    return $p
}

# Helper to resolve a value using precedence: Section-prefixed env var > generic env var > config file > script parameter
# This variant also records the "source" for each resolved parameter in $resolvedSources
$resolvedSources = @{}
$resolvedValues = @{}
function Resolve-Value-Record([string]$name, [string]$current) {
    $value = $null

    # 0) If a script parameter (CLI) was provided, prefer it (highest precedence)
    if ($current -ne $null -and $current -ne '') {
        $resolvedSources[$name] = 'cli'
        $resolvedValues[$name] = $current
        return $current
    }

    # 1) If parameter is mapped to a section, check section-prefixed env var first
    if ($sectionMap.ContainsKey($name)) {
        $section = $sectionMap[$name]
        $envName = Build-EnvName $section $name
        $envVal = (Get-Item -Path "Env:\$envName" -ErrorAction SilentlyContinue).Value
        if ($envVal) { $resolvedSources[$name] = "env:$envName"; $resolvedValues[$name] = $envVal; return $envVal }
    }

    # 2) Check generic env var using upper-snake (e.g., ACR_NAME)
    $genEnv = Build-EnvName $null $name
    $envVal2 = (Get-Item -Path "Env:\$genEnv" -ErrorAction SilentlyContinue).Value
    if ($envVal2) { $resolvedSources[$name] = "env:$genEnv"; $resolvedValues[$name] = $envVal2; return $envVal2 }

    # 3) Check old-style env var matching the parameter name (case-insensitive on Windows)
    $envVal3 = (Get-Item -Path "Env:\$name" -ErrorAction SilentlyContinue).Value
    if ($envVal3) { $resolvedSources[$name] = "env:$name"; $resolvedValues[$name] = $envVal3; return $envVal3 }

    # 4) Check deploy.config parsed values (lowest precedence)
    if ($config.ContainsKey($name) -and $config[$name]) { $resolvedSources[$name] = 'config'; $resolvedValues[$name] = $config[$name]; return $config[$name] }

    # 5) Nothing found
    $resolvedSources[$name] = '<unset>'
    $resolvedValues[$name] = $null
    return $null
}

# Resolve each parameter (note Build is a special boolean/switch)
$ResourceGroup = Resolve-Value-Record 'ResourceGroup' $ResourceGroup
$AcrName = Resolve-Value-Record 'AcrName' $AcrName
$AppName = Resolve-Value-Record 'AppName' $AppName
$ImageName = Resolve-Value-Record 'ImageName' $ImageName
$Tag = Resolve-Value-Record 'Tag' $Tag
$Location = Resolve-Value-Record 'Location' $Location
$PlanName = Resolve-Value-Record 'PlanName' $PlanName
$Sku = Resolve-Value-Record 'Sku' $Sku
$Dockerfile = Resolve-Value-Record 'Dockerfile' $Dockerfile
$AcrUser = Resolve-Value-Record 'AcrUser' $AcrUser
$AcrPass = Resolve-Value-Record 'AcrPass' $AcrPass

# Build the local image name used by docker build/tag operations
if (-not $Tag) { $Tag = 'latest' }
$ImageName = ($ImageName -as [string]).Trim()
if (-not $ImageName) {
    Fail "ImageName is not set. Provide -ImageName on the command line, set DOCKER_IMAGE_NAME/IMAGE_NAME, or add ImageName to the [docker] section in deploy.config."
}
$localImage = "$($ImageName):$($Tag)"
Write-Host "Local image reference: $localImage" -ForegroundColor Cyan

# Resolve Build: check env var or config (true/false), otherwise respect switch
if (-not $Build.IsPresent) {
    $buildRaw = Resolve-Value-Record 'Build' $null
    if ($buildRaw) {
        $buildBool = $false
        if ($buildRaw -match '^(1|true|yes)$') { $buildBool = $true }
        if ($buildBool) { $Build = $true } else { $Build = $false }
        # Record source for Build as derived when coming from env/config
        $resolvedSources['Build'] = 'derived'
        $resolvedValues['Build'] = [string]$Build
    }
}

# After resolving values, support -WhatIfConfig to print effective configuration and exit
if ($WhatIfConfig.IsPresent) {
    function Mask([string]$name, [string]$val) {
        if (-not $val) { return '<not set>' }
        # If the user passed the built-in -Debug common parameter, show unmasked values
        if ($PSBoundParameters.ContainsKey('Debug')) { return $val }
        $lower = $name.ToLower()
        if ($lower -like '*pass*' -or $lower -like '*secret*' -or $lower -like '*token*') {
            return '****(masked)'
        }
        return $val
    }

    Write-Host "=== Effective deploy configuration (WhatIfConfig) ===" -ForegroundColor Yellow
    # Base keys to show
    $keys = @('ResourceGroup','AcrName','AppName','ImageName','Tag','Location','PlanName','Sku','Dockerfile','AcrUser','AcrPass','Build')
    # Include any keys from the [env] section so users can see app settings that would be applied
    $envKeys = $sectionMap.Keys | Where-Object { $sectionMap[$_] -ieq 'env' } | Sort-Object
    foreach ($ek in $envKeys) { $keys += $ek }

    # Build a report array of objects so we can render a clean table
    $report = @()
    foreach ($k in $keys) {
        # Prefer the resolvedValues captured during resolution
        $val = $null
        if ($resolvedValues.ContainsKey($k)) { $val = $resolvedValues[$k] }
        if ($k -eq 'Build' -and -not $val) { $val = [string]($Build.IsPresent -or $Build) }
        if (-not $val) {
            # fallback to existing variable value if present
            $gv = Get-Variable -Name $k -Scope 0 -ErrorAction SilentlyContinue
            if ($gv) { $val = $gv.Value }
        }

        # Try to resolve any remaining keys (env, section-prefixed env, generic env, deploy.config)
        if (-not $val) {
            $derived = $null
            # exact env var matching the key
            $e = Get-Item -Path "Env:\$k" -ErrorAction SilentlyContinue
            if ($e -and $e.Value -ne '') { $derived = $e.Value; $resolvedSources[$k] = "env:$k" }

            # section-prefixed
            if (-not $derived -and $sectionMap.ContainsKey($k)) {
                $sec = $sectionMap[$k]
                $prefName = Build-EnvName $sec $k
                $pe = Get-Item -Path "Env:\$prefName" -ErrorAction SilentlyContinue
                if ($pe -and $pe.Value -ne '') { $derived = $pe.Value; $resolvedSources[$k] = "env:$prefName" }
            }

            # generic env var
            if (-not $derived) {
                $gen = Build-EnvName $null $k
                if ($gen) {
                    $ge = Get-Item -Path "Env:\$gen" -ErrorAction SilentlyContinue
                    if ($ge -and $ge.Value -ne '') { $derived = $ge.Value; $resolvedSources[$k] = "env:$gen" }
                }
            }

            # deploy.config fallback
            if (-not $derived -and $config.ContainsKey($k) -and $config[$k] -ne '') { $derived = $config[$k]; $resolvedSources[$k] = 'config' }

            if ($derived) { $val = $derived; $resolvedValues[$k] = $derived }
        }

        $src = $resolvedSources[$k]
        if (-not $src) { $src = '<unknown>' }
        $display = Mask $k $val

        $report += [PSCustomObject]@{
            Key    = $k
            Value  = $display
            Source = $src
        }
    }

    # Render the table
    Write-Host "Configuration (table):" -ForegroundColor Yellow
    $report | Sort-Object Key | Format-Table -Property @{Label='Key';Expression={$_.Key}}, @{Label='Value';Expression={$_.Value}}, @{Label='Source';Expression={$_.Source}} -AutoSize

    # If verbose requested show which environment variables were checked for each key
    if ($PSBoundParameters.ContainsKey('Verbose')) {
        Write-Host "\nEnvironment variables checked (per key):" -ForegroundColor Yellow
        foreach ($k in $keys) {
            $sec = $null
            if ($sectionMap.ContainsKey($k)) { $sec = $sectionMap[$k] }
            $cand = @()
            if ($sec) { $cand += Build-EnvName $sec $k }
            $cand += Build-EnvName $null $k
            $cand += $k
            foreach ($envName in $cand) {
                if (-not $envName) { continue }
                $e = Get-Item -Path "Env:\$envName" -ErrorAction SilentlyContinue
                if ($e -and $e.Value -ne '') {
                    if ($PSBoundParameters.ContainsKey('Debug')) { $valShown = $e.Value } else { $valShown = Mask $k $e.Value }
                    Write-Host ('    {0,-35} -> {1, -20} (present)' -f $envName, $valShown) -ForegroundColor DarkGreen
                } else {
                    Write-Host ('    {0,-35} -> {1, -20} (absent)' -f $envName, '<not set>') -ForegroundColor DarkGray
                }
            }
        }
    }

    if (-not $PSBoundParameters.ContainsKey('Verbose')) {
        Write-Host "Tip: run with -Verbose to show which environment variable names were checked for each parameter." -ForegroundColor Yellow
    }
    Write-Host "Note: values containing 'pass', 'secret', or 'token' are masked." -ForegroundColor Yellow
    exit 0
}

# Step 3: Optional build
Write-Host "[3/8] Build (optional)..." -ForegroundColor Yellow

# Optional build
if ($Build) {
    Info "Building Docker image '$localImage' using Dockerfile '$Dockerfile'..."
    $buildArgs = "-f $Dockerfile -t $localImage ."
    $buildResult = docker build -f $Dockerfile -t $localImage .
    if ($LASTEXITCODE -ne 0) { Fail "Docker build failed." }
    Write-Host "Docker build completed successfully." -ForegroundColor Green
} else {
    Write-Host "Skipping Docker build (Build not requested)." -ForegroundColor Gray
}

# Step 4: verify local image
Write-Host "[4/8] Verifying local Docker image exists..." -ForegroundColor Yellow

# Ensure local image exists
$images = docker images --format "{{.Repository}}:{{.Tag}}"
if (-not ($images -contains $localImage)) { Fail "Local image '$localImage' not found. Run with -Build or build the image first." }
Write-Host "Local image verified: $localImage" -ForegroundColor Green

# Step 5: tag and push
Write-Host "[5/8] Tagging and pushing image to ACR..." -ForegroundColor Yellow

# Discover ACR login server
$AcrLoginServer = (& az acr show -n $AcrName --query loginServer -o tsv) 2>$null
if (-not $AcrLoginServer) { Fail "ACR '$AcrName' not found in the current subscription or you are not logged in to Azure." }

# Construct the final image reference to push/use in Azure. Avoid double-prefixing if ImageName already contains a registry host.
$normalizedImageName = $ImageName
if ($AcrLoginServer -and $ImageName) {
    $lcAcr = $AcrLoginServer.ToLower()
    $lcImage = $ImageName.ToLower()
    if ($lcImage.StartsWith($lcAcr + '/')) {
        # ImageName already has the ACR login server prefix (e.g. "iwadevuks.azurecr.io/iwa") -> use as-is
        $normalizedImageName = $ImageName
    } elseif ($lcImage -match '^[^/]+\.azurecr\.io/') {
        # ImageName appears to reference an Azure CR host already -> use as-is
        $normalizedImageName = $ImageName
    } else {
        # Prefix with the ACR login server
        $normalizedImageName = "$AcrLoginServer/$ImageName"
    }
}

$acrImage = "${normalizedImageName}:$Tag"

# Obtain ACR credentials up-front (used for docker login fallback and later webapp config)
if ($AcrUser -and $AcrPass) {
    Write-Host "Using provided ACR credentials from environment/config/CLI." -ForegroundColor Cyan
    $acrUser = $AcrUser
    $acrPass = $AcrPass
} else {
    $acrUser = (& az acr credential show -n $AcrName --query username -o tsv) 2>$null
    $acrPass = (& az acr credential show -n $AcrName --query "passwords[0].value" -o tsv) 2>$null
}

# Login to ACR: prefer 'az acr login' which configures Docker credential helper, but fall back to 'docker login' if it fails
Info "Attempting 'az acr login' for ACR '$AcrName'..."
& az acr login -n $AcrName > $null
if ($LASTEXITCODE -ne 0) {
    Info "'az acr login' failed; attempting 'docker login' using ACR credentials if available..."
    if ($acrUser -and $acrPass) {
        $dl = docker login $AcrLoginServer -u $acrUser -p $acrPass 2>&1
        if ($LASTEXITCODE -ne 0) {
            Info "'docker login' with retrieved ACR credentials failed: $dl"
        } else {
            Info "Docker login succeeded using ACR credentials."
        }
    } else {
        Info "ACR credentials not available. Trying 'az acr login --expose-token'..."
        $token = (& az acr login -n $AcrName --expose-token --output tsv --query accessToken) 2>$null
        if ($token) {
            # Use the well-known service principal username for token login
            $tokenUser = '00000000-0000-0000-0000-000000000000'
            $dl = docker login $AcrLoginServer -u $tokenUser -p $token 2>&1
            if ($LASTEXITCODE -ne 0) {
                Info "Docker login using exposed token failed: $dl"
            } else {
                Info "Docker login succeeded using exposed token."
            }
        } else {
            Info "Failed to obtain an access token from 'az acr login --expose-token'."
        }
    }
    # Re-check whether docker is logged in by attempting to tag (will fail later if not)
} else {
    Info "'az acr login' succeeded."
}

# Tag and push
Info "Tagging local image '$localImage' -> '$acrImage'..."
Write-Host "Final ACR image reference to push: $acrImage" -ForegroundColor Cyan
docker tag $localImage $acrImage
if ($LASTEXITCODE -ne 0) { Fail "Failed to tag image." }

Info "Pushing image to ACR..."
docker push $acrImage
if ($LASTEXITCODE -ne 0) { Fail "Docker push failed. Ensure you can authenticate to $AcrLoginServer." }
Write-Host "Image pushed to ACR: $acrImage" -ForegroundColor Green

# Step 6: ensure azure resources
Write-Host "[6/8] Ensuring Azure resource group, App Service plan, and Web App exist..." -ForegroundColor Yellow

# Ensure resource group exists
$rgExists = (& az group exists -n $ResourceGroup) -eq 'True'
if (-not $rgExists) {
    Write-Host "Creating resource group '$ResourceGroup' in '$Location'..." -ForegroundColor Cyan
    Info "Creating resource group '$ResourceGroup' in '$Location'..."
    & az group create -n $ResourceGroup -l $Location | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Failed to create resource group." }
    Write-Host "Resource group created: $ResourceGroup" -ForegroundColor Green
} else {
    Write-Host "Resource group already exists: $ResourceGroup" -ForegroundColor Gray
}

# Ensure App Service plan exists
& az appservice plan show -g $ResourceGroup -n $PlanName -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating Linux App Service plan '$PlanName' (SKU: $Sku) in $Location..." -ForegroundColor Cyan
    Info "Creating Linux App Service plan '$PlanName' (SKU: $Sku) in $Location..."
    & az appservice plan create -g $ResourceGroup -n $PlanName --is-linux --sku $Sku --location $Location | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Failed to create App Service plan." }
    Write-Host "App Service plan created: $PlanName" -ForegroundColor Green
} else {
    Write-Host "App Service plan already exists: $PlanName" -ForegroundColor Gray
}

# Create web app if missing
$configuredOnCreate = $false
& az webapp show -g $ResourceGroup -n $AppName -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating Web App '$AppName'..." -ForegroundColor Cyan
    Info "Creating Web App '$AppName'..."

    $createArgs = @('webapp','create','-g',$ResourceGroup,'-p',$PlanName,'-n',$AppName)

    # Determine whether the target App Service plan is Linux (reserved=true). If we just created the plan earlier
    # we expect it to be a Linux plan. If the plan already existed, query it and respect its OS. Only pass --runtime
    # for Linux plans to avoid the Azure CLI error that asks for multicontainer config when conflicting flags are used.
    $isLinuxPlan = $false
    $planReserved = $null
    try {
        $planReserved = (& az appservice plan show -g $ResourceGroup -n $PlanName --query reserved -o tsv) 2>$null
    } catch {
        $planReserved = $null
    }
    if ($planReserved -ne $null -and $planReserved -ne '') {
        if ($planReserved -in @('True','true','1')) { $isLinuxPlan = $true }
    } else {
        # If we could not determine, assume Linux because the script creates a Linux plan by default earlier.
        $isLinuxPlan = $true
    }

    # If plan is Linux and we have a pushed image ($acrImage), create the app with the container image so we can skip
    # the separate 'az webapp config container set' call later (fewer Azure CLI calls and avoids deprecation warnings).
    if ($isLinuxPlan -and $acrImage) {
        Info "Creating a Linux Web App with container image supplied to 'az webapp create'..."
        # Use the newer container image create-time options where supported to avoid deprecation warnings later.
        $createArgs += @('--container-image-name',$acrImage)
        # If registry info is available, pass it so Azure can pull the image (use newer container-registry flags)
        if ($AcrLoginServer) { $createArgs += @('--container-registry-url',"https://$AcrLoginServer") }
        if ($acrUser) { $createArgs += @('--container-registry-user',$acrUser) }
        if ($acrPass) { $createArgs += @('--container-registry-password',$acrPass) }

        $configuredOnCreate = $true
    } else {
        if ($isLinuxPlan) {
            # No image available at create time; pass a default runtime to avoid CLI complaining. The container will be configured later.
            $createArgs += @('--runtime','JAVA|11-java11')
        } else {
            Write-Warning "Target App Service plan '$PlanName' appears to be a Windows plan. Deploying a Linux container requires a Linux plan."
        }
    }

    & az @createArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Failed to create Web App." }
    Write-Host "Web App created: $AppName" -ForegroundColor Green

    # If we attempted to configure the container during create, verify it actually took effect.
    if ($configuredOnCreate) {
        Write-Host "Verifying create-time container configuration was applied..." -ForegroundColor Yellow
        $containerInfo = (& az webapp config container show -g $ResourceGroup -n $AppName -o json) 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $containerInfo) {
            Write-Host "Could not read container configuration after create. Falling back to explicit container configuration..." -ForegroundColor Yellow
            $configuredOnCreate = $false
        } else {
            $containerInfoStr = $containerInfo | Out-String
            # Check whether the configured container info contains the image reference we expected
            if (-not ($containerInfoStr -match [regex]::Escape($acrImage))) {
                Write-Host "Container image '$acrImage' not found in the web app's container configuration. Applying configuration now..." -ForegroundColor Yellow
                $configuredOnCreate = $false
            } else {
                Write-Host "Container image present in web app configuration." -ForegroundColor Green
            }
        }

        # If verification failed above, attempt to apply the container config now and confirm success
        if (-not $configuredOnCreate) {
            Write-Host "Applying container settings via 'az webapp config container set' as a fallback..." -ForegroundColor Yellow
            $setArgs = @('webapp','config','container','set','-g',$ResourceGroup,'-n',$AppName,'--container-image-name',$acrImage)
            if ($AcrLoginServer) { $setArgs += @('--container-registry-url',"https://$AcrLoginServer") }
            if ($acrUser) { $setArgs += @('--container-registry-user',$acrUser) }
            if ($acrPass) { $setArgs += @('--container-registry-password',$acrPass) }
            & az @setArgs | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Fallback container configuration failed. The Web App may not be configured to pull the container." -ForegroundColor Red
            } else {
                Write-Host "Fallback container configuration applied successfully." -ForegroundColor Green
                $configuredOnCreate = $true
            }
        }
    }
} else {
    Write-Host "Web App already exists: $AppName" -ForegroundColor Gray
}

# Step 7: configure container
Write-Host "[7/8] Configuring Web App container settings..." -ForegroundColor Yellow

# Configure the web app container to use the image from ACR
Info "Configuring Web App container settings..."
# If the app was configured at create time with the container image, skip the separate config step
if ($configuredOnCreate) {
    Write-Host "Container image was applied during Web App creation; skipping 'az webapp config container set'." -ForegroundColor Gray
} else {
    # Use the newer az options (container-image-name / container-registry-url / container-registry-user / container-registry-password)
    & az webapp config container set -g $ResourceGroup -n $AppName `
        --container-image-name $acrImage `
        --container-registry-url "https://$AcrLoginServer" `
        --container-registry-user $acrUser `
        --container-registry-password $acrPass | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Failed to configure Web App container settings." }
    Write-Host "Web App container configuration applied." -ForegroundColor Green
}

# Configure application settings from [env] section (Environment variables override values in deploy.config)
Write-Host "Configuring Web App application settings from [env] section..." -ForegroundColor Yellow
$envKeys = $sectionMap.Keys | Where-Object { $sectionMap[$_] -ieq 'env' }
if ($envKeys.Count -eq 0) {
    Write-Host "No [env] section entries found in deploy.config; skipping app settings configuration." -ForegroundColor Gray
} else {
    $configuredKeys = @()
    # We'll apply each setting individually to avoid batching issues and to provide clearer diagnostics.
    function MaskKey([string]$key) {
        $lower = $key.ToLower()
        if ($lower -like '*pass*' -or $lower -like '*secret*' -or $lower -like '*token*') { return "$key (masked)" }
        return $key
    }

    foreach ($k in $envKeys) {
        $val = $null
        # 1) exact environment variable matching the key (recommended for [env] entries)
        $e = Get-Item -Path "Env:\$k" -ErrorAction SilentlyContinue
        if ($e -and $e.Value -ne '') { $val = $e.Value }

        # 2) section-prefixed env var (e.g., ENV_SPRING_MAIL_HOST) - support older behavior
        if (-not $val) {
            $sec = $sectionMap[$k]
            if ($sec) {
                $prefName = Build-EnvName $sec $k
                $pe = Get-Item -Path "Env:\$prefName" -ErrorAction SilentlyContinue
                if ($pe -and $pe.Value -ne '') { $val = $pe.Value }
            }
        }

        # 3) fallback to deploy.config value
        if (-not $val -and $config.ContainsKey($k) -and $config[$k] -ne '') { $val = $config[$k] }

        if ($val -ne $null -and $val -ne '') {
            # Apply single setting and check result
            Write-Host "Applying app setting: $(MaskKey $k)" -ForegroundColor Cyan
            $arg = @('webapp','config','appsettings','set','-g',$ResourceGroup,'-n',$AppName,'--settings',"$k=$val")
            & az @arg | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to set app setting: $k" -ForegroundColor Red
            } else {
                Write-Host "Set app setting: $(MaskKey $k)" -ForegroundColor Green
                $configuredKeys += $k
            }
        }
    }

    if ($configuredKeys.Count -gt 0) {
        # Verify settings were applied
        $currentJson = (& az webapp config appsettings list -g $ResourceGroup -n $AppName -o json) 2>$null
        $currentMap = @{}
        if ($currentJson) {
            try { $current = $currentJson | ConvertFrom-Json } catch { $current = @() }
            foreach ($s in $current) { $currentMap[$s.name] = $s.value }
        }

        Write-Host "Application settings applied to Web App." -ForegroundColor Green
        Write-Host "Summary (keys attempted):" -ForegroundColor Cyan
        foreach ($k in $configuredKeys) {
            $present = $false
            if ($currentMap.ContainsKey($k) -and -not [string]::IsNullOrEmpty($currentMap[$k])) { $present = $true }
            $displayVal = $k
            $lower = $k.ToLower()
            if ($lower -like '*pass*' -or $lower -like '*secret*' -or $lower -like '*token*') { $displayVal = "$k (masked)" }
            $status = If ($present) { 'present' } else { 'missing' }
            Write-Host ('    {0,-35} : {1}' -f $displayVal, $status) -ForegroundColor Gray
        }
    } else {
        Write-Host "No application settings had values to set; skipping." -ForegroundColor Gray
    }
}

# Step 8: restart
Write-Host "[8/8] Restarting Web App to pick up the new image..." -ForegroundColor Yellow

# Restart the web app to pick up the new image
Info "Restarting Web App '$AppName'..."
& az webapp restart -g $ResourceGroup -n $AppName | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Failed to restart Web App." }

Write-Host "=== Deploy Script Completed ===" -ForegroundColor Green

# Optional: wait for web app to reach 'Running' state
if ($WaitFor.IsPresent) {
    Write-Host "[8.1] Waiting for Web App '$AppName' to reach 'Running' state (timeout: ${WaitTimeoutSeconds}s) ..." -ForegroundColor Yellow
    $start = Get-Date
    $endTime = $start.AddSeconds($WaitTimeoutSeconds)
    $lastState = $null
    while ((Get-Date) -lt $endTime) {
        $state = (& az webapp show -g $ResourceGroup -n $AppName --query state -o tsv) 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to query Web App state from Azure CLI." -ForegroundColor Red
            break
        }
        $state = ($state -as [string]).Trim()
        if ($state -ne $lastState) { Write-Host ("Current web app state: {0}" -f $state) -ForegroundColor Cyan; $lastState = $state }
        if ($state -ieq 'Running') {
            Write-Host "Web App is Running." -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds $WaitIntervalSeconds
    }
    if ((Get-Date) -ge $endTime) { Fail "Timed out waiting for Web App to become 'Running' after $WaitTimeoutSeconds seconds." }
}

