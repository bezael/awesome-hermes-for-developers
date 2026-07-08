// Illustrative Bicep template for deploying Hermes Agent to Azure Container Apps.
// Not yet run against a live environment — validate resource API versions
// against the current Azure docs before applying. Parametrize anything
// environment-specific (names, region, image tag) before use.

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the Container Apps environment')
param environmentName string = 'env-hermes'

@description('Name of the container app')
param containerAppName string = 'hermes-agent'

@description('Container image for Hermes Agent')
param image string = 'ghcr.io/yourorg/hermes-agent:latest'

@description('Storage account already holding the hermes-state file share')
param storageAccountName string

@description('Key Vault name holding secrets (openai-api-key, telegram-bot-token, ...)')
param keyVaultName string

resource env 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource stateStorage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: env
  name: 'hermes-state-storage'
  properties: {
    azureFile: {
      accountName: storageAccountName
      shareName: 'hermes-state'
      accessMode: 'ReadWrite'
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      // Long-polling channels (Telegram/Discord) require minReplicas >= 1 —
      // see SKILL.md Pitfalls. Only rely on scale-to-zero for webhook channels.
      secrets: [
        {
          name: 'openai-api-key'
          keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/openai-api-key'
          identity: 'system'
        }
        {
          name: 'telegram-bot-token'
          keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/telegram-bot-token'
          identity: 'system'
        }
      ]
      ingress: {
        external: false // set true + configure targetPort if using a webhook channel
        targetPort: 9119 // Hermes web dashboard port — keep internal-only unless intentionally exposed
      }
    }
    template: {
      containers: [
        {
          name: 'hermes-agent'
          image: image
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'OPENAI_API_KEY'
              secretRef: 'openai-api-key'
            }
            {
              name: 'TELEGRAM_BOT_TOKEN'
              secretRef: 'telegram-bot-token'
            }
            {
              name: 'HERMES_HOME'
              value: '/mnt/hermes-state'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'hermes-state-volume'
              mountPath: '/mnt/hermes-state'
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'hermes-state-volume'
          storageType: 'AzureFile'
          storageName: stateStorage.name
        }
      ]
      scale: {
        minReplicas: 1 // do not set to 0 if a long-polling channel is configured
        maxReplicas: 1
      }
    }
  }
}

// After deploy, grant the container app's system-assigned identity the
// "Key Vault Secrets User" role on keyVaultName — RBAC assignment is
// intentionally left out of this template since it depends on your
// subscription's role-assignment scoping conventions.

output principalId string = containerApp.identity.principalId
