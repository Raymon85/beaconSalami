#!/usr/bin/env bash
# Deploys (or previews) the Bicep infrastructure template to a resource group.
# Usage: ./scripts/deploy-container.sh [--what-if] <resource-group> [param-file]
#
# --what-if as the first argument previews the change without applying it.
# Without the flag, the script deploys for real.

set -euo pipefail

WHAT_IF=false
if [ "${1:-}" = "--what-if" ]; then
  WHAT_IF=true
  shift
fi

RESOURCE_GROUP="${1:?Provide the resource group as the first argument}"
PARAM_FILE="${2:-infra/container.bicepparam}"
TEMPLATE_FILE="infra/container.bicep"

if [ "$WHAT_IF" = true ]; then
  echo "Previewing changes (what-if) for resource group: $RESOURCE_GROUP"
  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAM_FILE"
else
  echo "Deploying to resource group: $RESOURCE_GROUP"
  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAM_FILE" \
    --query properties.outputs \
    --output json
  echo "Done. Deployment complete."
fi