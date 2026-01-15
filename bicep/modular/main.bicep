// bicep/modular/main.bicep
// Top-level orchestrator that deploys the registry module and the webapp module.
// This example wires together the insecure registry and web app modules for demo use.

param location string = resourceGroup().location
param acrName string = 'iwadevuks' // default aligned with deploy.ps1
param webAppName string = 'iwa' // default aligned with deploy.ps1 (app name iwa)
param imageRepo string = 'iwa' // repository name pushed by CI/CD
param imageTag string = 'latest'

// Deploy registry (insecure module)
module registry './registry.bicep' = {
  name: 'registryModule'
  params: {
    acrName: acrName
    location: location
  }
}

// Build fully qualified image: "<loginServer>/<repo>:<tag>"
var fullyQualifiedImage = '${registry.outputs.loginServer}/${imageRepo}:${imageTag}'

// Deploy the insecure web app module, passing the fully qualified image and the ACR resource id
module webapp './webapp.bicep' = {
  name: 'webappModule'
  params: {
    webAppName: webAppName
    location: location
    image: fullyQualifiedImage
    acrId: registry.outputs.acrId
  }
  dependsOn: [
    registry
  ]
}

output webUrl string = 'https://${webapp.outputs.defaultHostName}'
output acrLoginServer string = registry.outputs.loginServer
