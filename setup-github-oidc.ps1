######################################################################
# GitHub Actions OIDC Setup Script for Azure
#
# This script creates the Azure AD App Registration and Federated
# Credentials needed for GitHub Actions to authenticate to Azure
# using OpenID Connect (OIDC) - no secrets required!
#
# Usage:
#   .\setup-github-oidc.ps1 -GitHubOrg "your-org" -GitHubRepo "your-repo"
#
# After running this script, add these secrets to your GitHub repo:
#   - AZURE_CLIENT_ID
#   - AZURE_TENANT_ID
#   - AZURE_SUBSCRIPTION_ID
######################################################################

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubOrg,
    
    [Parameter(Mandatory=$true)]
    [string]$GitHubRepo,
    
    [string]$AppName = "github-actions-func-orders-demo",
    [string]$ResourceGroup = "rg-functionapp-demo"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  GitHub Actions OIDC Setup for Azure" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "GitHub Repo: $GitHubOrg/$GitHubRepo" -ForegroundColor Yellow
Write-Host "App Name: $AppName" -ForegroundColor Yellow
Write-Host ""

#-----------------------------------------------------------------
# Step 1: Get current subscription and tenant
#-----------------------------------------------------------------
Write-Host "[1/6] Getting Azure context..." -ForegroundColor Green
$account = az account show | ConvertFrom-Json
$subscriptionId = $account.id
$tenantId = $account.tenantId
Write-Host "  Subscription: $subscriptionId" -ForegroundColor Gray
Write-Host "  Tenant: $tenantId" -ForegroundColor Gray

#-----------------------------------------------------------------
# Step 2: Create Azure AD App Registration
#-----------------------------------------------------------------
Write-Host ""
Write-Host "[2/6] Creating Azure AD App Registration..." -ForegroundColor Green

$existingApp = az ad app list --display-name $AppName --query "[0].appId" -o tsv 2>$null
if ($existingApp) {
    Write-Host "  App Registration already exists, skipping creation." -ForegroundColor Gray
    $appId = $existingApp
} else {
    $appId = (az ad app create --display-name $AppName --query appId -o tsv)
    Write-Host "  Created App Registration: $appId" -ForegroundColor Green
}

#-----------------------------------------------------------------
# Step 3: Create Service Principal
#-----------------------------------------------------------------
Write-Host ""
Write-Host "[3/6] Creating Service Principal..." -ForegroundColor Green

$existingSp = az ad sp show --id $appId --query id -o tsv 2>$null
if ($existingSp) {
    Write-Host "  Service Principal already exists, skipping." -ForegroundColor Gray
    $spObjectId = $existingSp
} else {
    $spObjectId = (az ad sp create --id $appId --query id -o tsv)
    Write-Host "  Created Service Principal: $spObjectId" -ForegroundColor Green
}

#-----------------------------------------------------------------
# Step 4: Assign Contributor role to Resource Group
#-----------------------------------------------------------------
Write-Host ""
Write-Host "[4/6] Assigning Contributor role to Resource Group..." -ForegroundColor Green

$scope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup"
$existingRole = az role assignment list --assignee $spObjectId --role "Contributor" --scope $scope --query "[0].id" -o tsv 2>$null

if ($existingRole) {
    Write-Host "  Contributor role already assigned, skipping." -ForegroundColor Gray
} else {
    az role assignment create `
        --assignee $spObjectId `
        --role "Contributor" `
        --scope $scope `
        --output none
    Write-Host "  Assigned Contributor role to: $ResourceGroup" -ForegroundColor Green
}

#-----------------------------------------------------------------
# Step 5: Create Federated Credential for main branch
#-----------------------------------------------------------------
Write-Host ""
Write-Host "[5/6] Creating Federated Credential for main branch..." -ForegroundColor Green

$masterCredName = "github-master-branch"
$existingMasterCred = az ad app federated-credential list --id $appId --query "[?name=='$masterCredName'].id" -o tsv 2>$null

if ($existingMasterCred) {
    Write-Host "  Federated credential for master branch already exists, skipping." -ForegroundColor Gray
} else {
    $masterCredParams = @{
        name = $masterCredName
        issuer = "https://token.actions.githubusercontent.com"
        subject = "repo:${GitHubOrg}/${GitHubRepo}:ref:refs/heads/master"
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Compress
    
    az ad app federated-credential create --id $appId --parameters $masterCredParams --output none
    Write-Host "  Created federated credential for: master branch" -ForegroundColor Green
}

#-----------------------------------------------------------------
# Step 6: Create Federated Credential for Pull Requests
#-----------------------------------------------------------------
Write-Host ""
Write-Host "[6/6] Creating Federated Credential for Pull Requests..." -ForegroundColor Green

$prCredName = "github-pull-requests"
$existingPrCred = az ad app federated-credential list --id $appId --query "[?name=='$prCredName'].id" -o tsv 2>$null

if ($existingPrCred) {
    Write-Host "  Federated credential for pull requests already exists, skipping." -ForegroundColor Gray
} else {
    $prCredParams = @{
        name = $prCredName
        issuer = "https://token.actions.githubusercontent.com"
        subject = "repo:${GitHubOrg}/${GitHubRepo}:pull_request"
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Compress
    
    az ad app federated-credential create --id $appId --parameters $prCredParams --output none
    Write-Host "  Created federated credential for: pull requests" -ForegroundColor Green
}

#-----------------------------------------------------------------
# Summary
#-----------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  OIDC SETUP COMPLETE!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Add these secrets to your GitHub repository:" -ForegroundColor Cyan
Write-Host "  Settings > Secrets and variables > Actions > New repository secret" -ForegroundColor Gray
Write-Host ""
Write-Host "  AZURE_CLIENT_ID:       $appId" -ForegroundColor Yellow
Write-Host "  AZURE_TENANT_ID:       $tenantId" -ForegroundColor Yellow
Write-Host "  AZURE_SUBSCRIPTION_ID: $subscriptionId" -ForegroundColor Yellow
Write-Host ""
Write-Host "GitHub Repository Settings URL:" -ForegroundColor Cyan
Write-Host "  https://github.com/$GitHubOrg/$GitHubRepo/settings/secrets/actions" -ForegroundColor White
Write-Host ""

# Optional: Create staging slot for PR deployments
Write-Host "Optional: Create staging slot for PR deployments" -ForegroundColor Cyan
Write-Host "  az functionapp deployment slot create --name func-orders-demo --resource-group $ResourceGroup --slot staging" -ForegroundColor Gray
Write-Host ""
