#!/usr/bin/env bash
# Provisions everything from scratch: App Service track and Container Apps track.
# Usage: ./scripts/provision-all.sh <resource-group>

set -euo pipefail

RESOURCE_GROUP="${1:?Provide the resource group as the first argument}"
LOCATION="${2:-westeurope}"

echo "Step 1: Creating resource group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

echo "Step 2: Deploying App Service infrastructure..."
./scripts/deploy-infra.sh "$RESOURCE_GROUP"

echo "Step 3: Deploying registry, environment and Container App (image not built yet)..."
./scripts/deploy-container.sh "$RESOURCE_GROUP"

echo "Step 4: Building and pushing the container image..."
az acr build --registry acrclo25rayan --image beacon:v1 \
  --file src/BeaconSalami/Dockerfile .

echo "Step 5: Redeploying so the Container App picks up the image..."
./scripts/deploy-container.sh "$RESOURCE_GROUP"

echo "Provisioning complete."