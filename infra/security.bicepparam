using './security.bicep'

param vaultName = 'kv-clo25-rayan'
param appName = 'app-clo25-rayan'
param ownerObjectId = readEnvironmentVariable('OWNER_OBJECT_ID')
param secretValue = readEnvironmentVariable('SECRET_VALUE')
