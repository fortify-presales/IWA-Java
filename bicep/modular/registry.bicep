// bicep/modular/registry.bicep
// Module: create an Azure Container Registry (ACR) and return the login server and resource id.
// This module intentionally includes insecure settings for demonstration purposes (admin user enabled, public access comments).

param acrName string
param location string = resourceGroup().location

// INSECURE: adminUserEnabled=true -> registry has an admin account
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true // Vulnerability: exposes admin credentials which may be reused elsewhere
  }
}

// Outputting the login server (note: may reveal internal endpoints)
output loginServer string = acr.properties.loginServer
output acrId string = acr.id
