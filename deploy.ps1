######################################################################
# Azure Function App - Full Infrastructure & Deployment Script
# 
# This script creates ALL Azure resources needed for the Function App
# with Managed Identity authentication (no connection strings/keys)
#
# Usage:
#   .\deploy.ps1                           # Deploy code only
#   .\deploy.ps1 -ProvisionInfra           # Create all Azure resources + deploy
#   .\deploy.ps1 -ProvisionInfra -Clean    # Clean build + create resources + deploy
#
# Resources Created:
#   - Resource Group
#   - Storage Account (MI-enabled, no shared key access)
#   - Service Bus Namespace (Standard) + Queue
#   - App Service Plan (Basic B1)
#   - Function App with System Managed Identity
#   - Application Insights
#   - MI Role Assignments (Storage + Service Bus)
######################################################################

param(
    # Resource names (customize these)
    [string]$ResourceGroup = "rg-functionapp-demo",
    [string]$Location = "southindia",
    [string]$StorageAccount = "stfuncordersdemo",
    [string]$ServiceBusNamespace = "sbordersdemoin",
    [string]$ServiceBusQueue = "orders",
    [string]$AppServicePlan = "plan-func-orders-demo",
    [string]$FunctionAppName = "func-orders-demo",
    [string]$AppInsightsName = "func-orders-demo",
    
    # Deployment options
    [switch]$ProvisionInfra,    # Create Azure resources
    [switch]$Clean,             # Clean build artifacts
    [switch]$SkipBuild,         # Skip build, deploy existing
    [switch]$SkipDeploy         # Only provision infrastructure
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$PublishPath = Join-Path $ProjectRoot "publish"
$ProjectFile = Join-Path $ProjectRoot "FunctionAppDemos.csproj"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Azure Function App - Infrastructure & Deployment" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group:    $ResourceGroup" -ForegroundColor Gray
Write-Host "  Location:          $Location" -ForegroundColor Gray
Write-Host "  Storage Account:   $StorageAccount" -ForegroundColor Gray
Write-Host "  Service Bus:       $ServiceBusNamespace" -ForegroundColor Gray
Write-Host "  Function App:      $FunctionAppName" -ForegroundColor Gray
Write-Host ""

######################################################################
# INFRASTRUCTURE PROVISIONING (when -ProvisionInfra is specified)
######################################################################
if ($ProvisionInfra) {
    
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host "  PROVISIONING AZURE INFRASTRUCTURE" -ForegroundColor Magenta
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host ""

    #-----------------------------------------------------------------
    # Step 1: Create Resource Group
    #-----------------------------------------------------------------
    Write-Host "[Infra 1/9] Creating Resource Group..." -ForegroundColor Green
    $rgExists = az group exists --name $ResourceGroup 2>$null
    if ($rgExists -eq "true") {
        Write-Host "  Resource Group already exists, skipping." -ForegroundColor Gray
    } else {
        az group create --name $ResourceGroup --location $Location --output none
        Write-Host "  Created: $ResourceGroup" -ForegroundColor Green
    }

    #-----------------------------------------------------------------
    # Step 2: Create Storage Account (with MI access, no shared keys)
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Infra 2/9] Creating Storage Account (MI-enabled)..." -ForegroundColor Green
    $storageExists = az storage account show --name $StorageAccount --resource-group $ResourceGroup 2>$null
    if ($storageExists) {
        Write-Host "  Storage Account already exists, skipping creation." -ForegroundColor Gray
    } else {
        az storage account create `
            --name $StorageAccount `
            --resource-group $ResourceGroup `
            --location $Location `
            --sku Standard_LRS `
            --kind StorageV2 `
            --min-tls-version TLS1_2 `
            --allow-blob-public-access false `
            --output none
        Write-Host "  Created: $StorageAccount" -ForegroundColor Green
    }

    # Disable shared key access (force MI authentication)
    $sharedKeyStatus = (az storage account show --name $StorageAccount --resource-group $ResourceGroup --query allowSharedKeyAccess -o tsv 2>$null)
    if ($sharedKeyStatus -eq "false") {
        Write-Host "  Shared key access already disabled, skipping." -ForegroundColor Gray
    } else {
        Write-Host "  Disabling shared key access (MI only)..." -ForegroundColor Gray
        az storage account update `
            --name $StorageAccount `
            --resource-group $ResourceGroup `
            --allow-shared-key-access false `
            --output none
        Write-Host "  Shared key access disabled." -ForegroundColor Green
    }

    #-----------------------------------------------------------------
    # Step 3: Create Service Bus Namespace (Standard tier for queues)
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Infra 3/9] Creating Service Bus Namespace..." -ForegroundColor Green
    $sbExists = az servicebus namespace show --name $ServiceBusNamespace --resource-group $ResourceGroup 2>$null
    if ($sbExists) {
        Write-Host "  Service Bus Namespace already exists, skipping." -ForegroundColor Gray
    } else {
        az servicebus namespace create `
            --name $ServiceBusNamespace `
            --resource-group $ResourceGroup `
            --location $Location `
            --sku Standard `
            --output none
        Write-Host "  Created: $ServiceBusNamespace" -ForegroundColor Green
    }

    #-----------------------------------------------------------------
    # Step 4: Create Service Bus Queue
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Infra 4/9] Creating Service Bus Queue..." -ForegroundColor Green
    $queueExists = az servicebus queue show --name $ServiceBusQueue --namespace-name $ServiceBusNamespace --resource-group $ResourceGroup 2>$null
    if ($queueExists) {
        Write-Host "  Queue already exists, skipping." -ForegroundColor Gray
    } else {
        az servicebus queue create `
            --name $ServiceBusQueue `
            --namespace-name $ServiceBusNamespace `
            --resource-group $ResourceGroup `
            --output none
        Write-Host "  Created: $ServiceBusQueue" -ForegroundColor Green
    }

    #-----------------------------------------------------------------
    # Step 5: Create Application Insights
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Infra 5/9] Creating Application Insights..." -ForegroundColor Green
    $aiExists = az monitor app-insights component show --app $AppInsightsName --resource-group $ResourceGroup 2>$null
    if ($aiExists) {
        Write-Host "  Application Insights already exists, skipping." -ForegroundColor Gray
        $aiConnectionString = (az monitor app-insights component show --app $AppInsightsName --resource-group $ResourceGroup --query connectionString -o tsv)
    } else {
        $aiConnectionString = (az monitor app-insights component create `
            --app $AppInsightsName `
            --resource-group $ResourceGroup `
            --location $Location `
            --kind web `
            --application-type web `
            --query connectionString -o tsv)
        Write-Host "  Created: $AppInsightsName" -ForegroundColor Green
    }

    #-----------------------------------------------------------------
    # Step 6: Create App Service Plan (Basic B1)
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Infra 6/9] Creating App Service Plan..." -ForegroundColor Green
    $planExists = az appservice plan show --name $AppServicePlan --resource-group $ResourceGroup 2>$null
    if ($planExists) {
        Write-Host "  App Service Plan already exists, skipping." -ForegroundColor Gray
    } else {
        az appservice plan create `
            --name $AppServicePlan `
            --resource-group $ResourceGroup `
            --location $Location `
            --sku B1 `
            --is-linux false `
            --output none
        Write-Host "  Created: $AppServicePlan (Basic B1)" -ForegroundColor Green
    }

    #-----------------------------------------------------------------
    # Step 7: Create Function App with System Managed Identity
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Infra 7/9] Creating Function App with Managed Identity..." -ForegroundColor Green
    $funcExists = az functionapp show --name $FunctionAppName --resource-group $ResourceGroup 2>$null
    if ($funcExists) {
        Write-Host "  Function App already exists, skipping creation." -ForegroundColor Gray
    } else {
        az functionapp create `
            --name $FunctionAppName `
            --resource-group $ResourceGroup `
            --plan $AppServicePlan `
            --storage-account $StorageAccount `
            --runtime dotnet-isolated `
            --runtime-version 8 `
            --functions-version 4 `
            --os-type Windows `
            --assign-identity "[system]" `
            --output none
        Write-Host "  Created: $FunctionAppName" -ForegroundColor Green
    }

    # Ensure System MI is enabled
    $principalId = (az functionapp identity show --name $FunctionAppName --resource-group $ResourceGroup --query principalId -o tsv 2>$null)
    if ($principalId) {
        Write-Host "  System Managed Identity already enabled, skipping." -ForegroundColor Gray
        Write-Host "  MI Principal ID: $principalId" -ForegroundColor Gray
    } else {
        Write-Host "  Enabling System Managed Identity..." -ForegroundColor Gray
        az functionapp identity assign --name $FunctionAppName --resource-group $ResourceGroup --output none
        $principalId = (az functionapp identity show --name $FunctionAppName --resource-group $ResourceGroup --query principalId -o tsv)
        Write-Host "  MI Principal ID: $principalId" -ForegroundColor Green
    }

    #-----------------------------------------------------------------
    # Step 8: Assign MI Roles for Storage Account
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Infra 8/9] Assigning Storage MI Roles..." -ForegroundColor Green
    
    $storageId = (az storage account show --name $StorageAccount --resource-group $ResourceGroup --query id -o tsv)
    
    $storageRoles = @(
        @{ Name = "Storage Blob Data Owner"; Id = "b7e6dc6d-f1e8-4753-8033-0f276bb0955b" },
        @{ Name = "Storage Queue Data Contributor"; Id = "974c5e8b-45b9-4653-ba55-5f855dd0fb88" },
        @{ Name = "Storage Table Data Contributor"; Id = "0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3" }
    )
    
    foreach ($role in $storageRoles) {
        # Check if role assignment already exists
        $existingRole = az role assignment list --assignee $principalId --role $role.Id --scope $storageId --query "[0].id" -o tsv 2>$null
        if ($existingRole) {
            Write-Host "  $($role.Name) already assigned, skipping." -ForegroundColor Gray
        } else {
            Write-Host "  Assigning: $($role.Name)..." -ForegroundColor Gray
            az role assignment create `
                --assignee $principalId `
                --role $role.Id `
                --scope $storageId `
                --output none 2>$null
            Write-Host "  Assigned: $($role.Name)" -ForegroundColor Green
        }
    }

    #-----------------------------------------------------------------
    # Step 9: Assign MI Roles for Service Bus
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Infra 9/9] Assigning Service Bus MI Roles..." -ForegroundColor Green
    
    $sbId = (az servicebus namespace show --name $ServiceBusNamespace --resource-group $ResourceGroup --query id -o tsv)
    $sbRoleId = "69a216fc-b8fb-44d8-bc22-1f3c2cd27a39"  # Azure Service Bus Data Sender
    
    # Check if role assignment already exists
    $existingSbRole = az role assignment list --assignee $principalId --role $sbRoleId --scope $sbId --query "[0].id" -o tsv 2>$null
    if ($existingSbRole) {
        Write-Host "  Azure Service Bus Data Sender already assigned, skipping." -ForegroundColor Gray
    } else {
        Write-Host "  Assigning: Azure Service Bus Data Sender..." -ForegroundColor Gray
        az role assignment create `
            --assignee $principalId `
            --role $sbRoleId `
            --scope $sbId `
            --output none 2>$null
        Write-Host "  Assigned: Azure Service Bus Data Sender" -ForegroundColor Green
    }

    #-----------------------------------------------------------------
    # Configure App Settings for MI Authentication
    #-----------------------------------------------------------------
    Write-Host ""
    Write-Host "[Config] Configuring App Settings for MI Authentication..." -ForegroundColor Cyan
    
    # Get current app settings
    $currentSettings = az functionapp config appsettings list --name $FunctionAppName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
    $currentSettingsHash = @{}
    foreach ($s in $currentSettings) { $currentSettingsHash[$s.name] = $s.value }
    
    # Check if MI settings are already configured
    $miConfigured = ($currentSettingsHash["AzureWebJobsStorage__credential"] -eq "managedidentity") -and
                    ($currentSettingsHash["AzureWebJobsStorage__accountName"] -eq $StorageAccount) -and
                    ($currentSettingsHash["ServiceBusConnection__fullyQualifiedNamespace"] -eq "$ServiceBusNamespace.servicebus.windows.net")
    
    if ($miConfigured) {
        Write-Host "  MI-based app settings already configured, skipping." -ForegroundColor Gray
    } else {
        # Remove unnecessary/legacy settings that might interfere with MI
        Write-Host "  Removing legacy connection string settings..." -ForegroundColor Gray
        $settingsToRemove = @(
            "AzureWebJobsStorage",           # Remove if it contains connection string
            "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING"
        )
        foreach ($setting in $settingsToRemove) {
            if ($currentSettingsHash.ContainsKey($setting)) {
                az functionapp config appsettings delete `
                    --name $FunctionAppName `
                    --resource-group $ResourceGroup `
                    --setting-names $setting `
                    --output none 2>$null
                Write-Host "  Removed: $setting" -ForegroundColor Gray
            }
        }

        # Set MI-based app settings
        Write-Host "  Setting MI-based configuration..." -ForegroundColor Gray
        az functionapp config appsettings set `
            --name $FunctionAppName `
            --resource-group $ResourceGroup `
            --settings `
                "AzureWebJobsStorage__accountName=$StorageAccount" `
                "AzureWebJobsStorage__blobServiceUri=https://$StorageAccount.blob.core.windows.net" `
                "AzureWebJobsStorage__queueServiceUri=https://$StorageAccount.queue.core.windows.net" `
                "AzureWebJobsStorage__tableServiceUri=https://$StorageAccount.table.core.windows.net" `
                "AzureWebJobsStorage__credential=managedidentity" `
                "ServiceBusConnection__fullyQualifiedNamespace=$ServiceBusNamespace.servicebus.windows.net" `
                "APPLICATIONINSIGHTS_CONNECTION_STRING=$aiConnectionString" `
                "FUNCTIONS_WORKER_RUNTIME=dotnet-isolated" `
            --output none
        
        Write-Host "  App settings configured for MI access!" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host "  INFRASTRUCTURE PROVISIONING COMPLETE!" -ForegroundColor Magenta
    Write-Host "=============================================" -ForegroundColor Magenta
    Write-Host ""
    
    # Wait for role propagation only if new roles were assigned
    if (-not $existingRole -or -not $existingSbRole) {
        Write-Host "Waiting 30 seconds for role assignments to propagate..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
    } else {
        Write-Host "All roles already assigned, skipping wait." -ForegroundColor Gray
    }
}

######################################################################
# BUILD & DEPLOY
######################################################################
if ($SkipDeploy) {
    Write-Host "Skipping build and deploy (-SkipDeploy specified)" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  BUILD & DEPLOY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

#-----------------------------------------------------------------
# Step 1: Clean (optional)
#-----------------------------------------------------------------
if ($Clean) {
    Write-Host ""
    Write-Host "[Build 1/4] Cleaning build artifacts..." -ForegroundColor Green
    
    $foldersToClean = @("bin", "obj", "publish")
    foreach ($folder in $foldersToClean) {
        $path = Join-Path $ProjectRoot $folder
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force
            Write-Host "  Removed: $folder" -ForegroundColor Gray
        }
    }
    Write-Host "  Clean completed!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[Build 1/4] Skipping clean (use -Clean to enable)" -ForegroundColor Gray
}

#-----------------------------------------------------------------
# Step 2: Restore NuGet packages
#-----------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "[Build 2/4] Restoring NuGet packages..." -ForegroundColor Green
    
    dotnet restore $ProjectFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Package restore failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Restore completed!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[Build 2/4] Skipping restore (SkipBuild enabled)" -ForegroundColor Gray
}

#-----------------------------------------------------------------
# Step 3: Build and Publish
#-----------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "[Build 3/4] Building and publishing (Release)..." -ForegroundColor Green
    
    dotnet publish $ProjectFile -c Release -o $PublishPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Build/publish failed!" -ForegroundColor Red
        exit 1
    }
    
    # Verify functions.metadata exists
    $metadataFile = Join-Path $PublishPath "functions.metadata"
    if (Test-Path $metadataFile) {
        Write-Host "  Build completed!" -ForegroundColor Green
        
        # Show discovered functions
        $metadata = Get-Content $metadataFile | ConvertFrom-Json
        Write-Host "  Functions found:" -ForegroundColor Cyan
        foreach ($func in $metadata) {
            Write-Host "    - $($func.name)" -ForegroundColor White
        }
    } else {
        Write-Host "WARNING: functions.metadata not found!" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "[Build 3/4] Skipping build (SkipBuild enabled)" -ForegroundColor Gray
}

#-----------------------------------------------------------------
# Step 4: Deploy to Azure
#-----------------------------------------------------------------
Write-Host ""
Write-Host "[Build 4/4] Deploying to Azure..." -ForegroundColor Green
Write-Host "  Target: $FunctionAppName" -ForegroundColor Yellow

Push-Location $PublishPath
try {
    func azure functionapp publish $FunctionAppName --dotnet-isolated --force
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Deployment failed!" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

######################################################################
# DONE!
######################################################################
Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Resources:" -ForegroundColor Cyan
Write-Host "  Resource Group:    $ResourceGroup" -ForegroundColor White
Write-Host "  Storage Account:   $StorageAccount (MI auth, no keys)" -ForegroundColor White
Write-Host "  Service Bus:       $ServiceBusNamespace/$ServiceBusQueue" -ForegroundColor White
Write-Host "  Function App:      $FunctionAppName" -ForegroundColor White
Write-Host ""
Write-Host "Function URL:" -ForegroundColor Cyan
Write-Host "  https://$FunctionAppName.azurewebsites.net/api/processordertrigger" -ForegroundColor Yellow
Write-Host ""
Write-Host "Test with:" -ForegroundColor Cyan
Write-Host '  $body = ''{"Id":"ORD-001","Name":"Test Product"}''' -ForegroundColor Gray
Write-Host "  Invoke-RestMethod -Uri `"https://$FunctionAppName.azurewebsites.net/api/processordertrigger`" -Method POST -Body `$body -ContentType `"application/json`"" -ForegroundColor Gray
Write-Host ""
Write-Host "Portal Links:" -ForegroundColor Cyan
Write-Host "  https://portal.azure.com/#@/resource/subscriptions/{sub}/resourceGroups/$ResourceGroup" -ForegroundColor Gray
Write-Host ""
