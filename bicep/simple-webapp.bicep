// bicep/simple-webapp.bicep
// Intentionally insecure example for security scanning/demo purposes.
// This file intentionally contains several insecure configurations (with comments) so that
// security scanners can detect them as part of training/demos. Do NOT use these settings in production.

param location string = resourceGroup().location
param webAppName string = 'iwa' // default adjusted to match deploy.ps1 usage
param acrName string = 'iwadevuks' // default adjusted to match deploy.ps1 usage
param imageName string = 'iwa:latest' // default adjusted to match deploy.ps1 usage

// INSECURE: adminUserEnabled = true exposes an administrative account on the registry.
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true // Vulnerability: ACR admin user enabled (credentials can be abused)
  }
}

// App Service plan (Linux)
resource plan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${webAppName}-plan'
  location: location
  sku: {
    name: 'P1v2'
    tier: 'PremiumV2'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// Web App for Containers with deliberately insecure settings for demo
resource web 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    // INSECURE: httpsOnly intentionally left out/false below so HTTP is allowed.
    httpsOnly: false // Vulnerability: allows unencrypted HTTP traffic

    siteConfig: {
      // Image points to the insecure registry image; CI should push this image in demo scenarios
      linuxFxVersion: 'DOCKER|${acr.properties.loginServer}/${imageName}'

      // INSECURE app settings: plaintext secrets and excessive privileges
      appSettings: [
        // Sensitive secrets in plaintext (vulnerability): scanners should flag these
        { name: 'SPRING_MAIL_USERNAME'; value: 'demo-user@example.com' }
        { name: 'SPRING_MAIL_PASSWORD'; value: 'P@ssw0rd123!' }
        { name: 'SPRING_MAIL_HOST'; value: 'smtp.example.invalid' }
        { name: 'SPRING_MAIL_PORT'; value: '587' }

        // Insecurely enabling writeable storage in App Service (can be abused)
        { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'; value: 'true' }

        // Insecurely exposing Docker registry credentials as app settings (plaintext)
        { name: 'DOCKER_REGISTRY_SERVER_URL'; value: 'https://${acr.properties.loginServer}' }
        { name: 'DOCKER_REGISTRY_SERVER_USERNAME'; value: 'acr-admin' }
        { name: 'DOCKER_REGISTRY_SERVER_PASSWORD'; value: 'acrp@ssw0rd' }

        // Dangerous: allow all hostnames (simulates misconfiguration)
        { name: 'ALLOWED_HOSTS'; value: '*' }

        // Example of a Key Vault reference that would be secure — included here for contrast
        // { name: 'SECURE_SECRET_FROM_KV'; value: '@Microsoft.KeyVault(SecretUri=<your-secret-uri>)' }
      ]

      // INSECURE: enabling SCM (git) deployment and leaving it open can allow unauthorized code pushes
      scmType: 'LocalGit' // Vulnerability: Local Git deployment enabled

      // Note: remote debugging is typically a Windows feature; setting it here is intentionally noisy
      // to demonstrate detection of debug flags in site configuration.
      remoteDebuggingEnabled: true
      remoteDebuggingVersion: 'VS2019'
    }
  }
  dependsOn: [
    acr
    plan
  ]
}

// Role assignment: give the web app's identity AcrPull on the registry (keeps example functional)
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource webAcrPull 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(web.id, acr.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: web.identity.principalId
  }
  dependsOn: [
    web
  ]
}

// Expose outputs (note: outputs may reveal sensitive values in some CI systems; be cautious)
output acrLoginServer string = acr.properties.loginServer
output webAppUrl string = 'https://${web.properties.defaultHostName}'
