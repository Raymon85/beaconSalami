// Infrastructure as code for the BeaconSalami App Service and its plan.
// Describes the resources exactly as they were built manually in weeks 35-36,
// so this file can recreate them identically after the resource group is deleted.

param planName string   // the plan you already have - no default, describes what exists
param appName string    // the app you already have - no default
param location string = resourceGroup().location

@minValue(1)
@maxValue(3)
param instanceCount int = 3

param skuName string = 'B1'
param runtimeStack string = 'DOTNETCORE|10.0'
param healthCheckPath string = '/health'

resource plan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: skuName
    capacity: instanceCount
  }
  properties: {
    reserved: true // true = Linux
  }
}

resource app 'Microsoft.Web/sites@2025-03-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: runtimeStack
      healthCheckPath: healthCheckPath
      minTlsVersion: '1.3'
      alwaysOn: true
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'false'
        }
      ]
    }
  }
}

output appUrl string = 'https://${app.properties.defaultHostName}'