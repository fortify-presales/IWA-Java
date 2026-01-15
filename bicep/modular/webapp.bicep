// bicep/modular/webapp.bicep
// Module: create App Service Plan + Web App for Containers and grant AcrPull for the web identity.
// Contains intentionally insecure settings (HTTP enabled, plaintext app settings, remote debugging, etc.)

param webAppName string
param location string = resourceGroup().location
param image string
param acrId string

resource plan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${webAppName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: 'P1v2'
    tier: 'PremiumV2'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

resource web 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id

    // INSECURE: Allowing HTTP (httpsOnly=false) and leaving diagnostic logging high
    httpsOnly: false

    siteConfig: {
      linuxFxVersion: 'DOCKER|${image}'
      appSettings: [
        { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE', value: 'true' }
        { name: 'SPRING_MAIL_DEFAULT_ENCODING', value: 'UTF-8' }
        // Plaintext password (insecure)
        { name: 'SPRING_MAIL_PASSWORD', value: 'demo-pass' }
        // Allow all hosts
        { name: 'ALLOWED_HOSTS', value: '*' }
        // Expose container registry credentails (insecure)
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://insecure.example' }
        { name: 'DOCKER_REGISTRY_SERVER_USERNAME', value: 'admin' }
        { name: 'DOCKER_REGISTRY_SERVER_PASSWORD', value: 'adminpass' }
      ]

      scmType: 'LocalGit'
      // Enable remote debugging to demonstrate detection of debug flags
      remoteDebuggingEnabled: true
      remoteDebuggingVersion: 'VS2019'
    }
  }
  dependsOn: [
    plan
  ]
}

// Assign AcrPull to the web app identity for the provided ACR (keeps example functional)
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

// The module receives an ACR resource id string (acrId). Bicep expects the 'scope' property
// for the role assignment to be a resource reference (not a plain string). Create an
// existing resource reference for the ACR in this resource group using the name parsed
// from the provided resource id, then use that resource as the scope for the role assignment.
var acrNameFromId = last(split(acrId, '/'))
resource acrExisting 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrNameFromId
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(web.id, acrExisting.id, acrPullRoleId)
  scope: acrExisting
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: web.identity.principalId
  }
  dependsOn: [
    web
  ]
}

output defaultHostName string = web.properties.defaultHostName
output principalId string = web.identity.principalId
