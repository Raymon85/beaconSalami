using 'container.bicep'

param registryName = 'acrclo25rayan'
param containerImage = 'acrclo25rayan.azurecr.io/beacon:v1'
param targetPort = 8080
param minReplicas = 0
param maxReplicas = 3
param concurrentRequests = 10