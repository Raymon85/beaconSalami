// Key Vault for BeaconSalami's security demo (week 40).
// Uses access policies, not RBAC, since RBAC needs role-assignment rights
// that not everyone in the course has - see TUTORIAL.md.

param vaultName string
param location string = resourceGroup().location
param appName string
param ownerObjectId string

@secure()
param secretValue string

var secretsRead = [
  'get'
  'list'
]

resource app 'Microsoft.Web/sites@2025-03-01' existing = {
  name: appName
}

resource vault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: vaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: false
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: app.identity.principalId
        permissions: {
          secrets: secretsRead
        }
      }
      {
        tenantId: subscription().tenantId
        objectId: ownerObjectId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
          ]
        }
      }
    ]
  }
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: vault
  name: 'demo-secret'
  properties: {
    value: secretValue
  }
}

output secretUri string = secret.properties.secretUri
