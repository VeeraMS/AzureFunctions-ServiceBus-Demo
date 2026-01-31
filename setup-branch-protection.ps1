#!/usr/bin/env pwsh
#############################################################################
# GitHub Branch Protection & Security Setup Script
#
# This script configures:
# 1. Branch protection rules for master branch
# 2. Required PR reviews and approvals
# 3. Required status checks (CI must pass)
# 4. GitHub Advanced Security features
#
# Prerequisites:
# - GitHub CLI (gh) installed: winget install GitHub.cli
# - Authenticated: gh auth login
# - Repository admin access
#############################################################################

param(
    [string]$Owner = "VeeraMS",
    [string]$Repo = "AzureFunctions-ServiceBus-Demo",
    [string]$Branch = "master"
)

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "GitHub Branch Protection & Security Setup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check if gh CLI is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "❌ GitHub CLI (gh) is not installed." -ForegroundColor Red
    Write-Host "Install it with: winget install GitHub.cli" -ForegroundColor Yellow
    exit 1
}

# Check authentication
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Not authenticated to GitHub CLI." -ForegroundColor Red
    Write-Host "Run: gh auth login" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ GitHub CLI authenticated" -ForegroundColor Green
Write-Host ""

#############################################################################
# STEP 1: Configure Branch Protection Rules
#############################################################################
Write-Host "📋 STEP 1: Configuring Branch Protection for '$Branch'..." -ForegroundColor Yellow

# Create branch protection rule using GitHub API
$protectionPayload = @{
    required_status_checks = @{
        strict = $true  # Require branches to be up to date before merging
        contexts = @(
            "Build Function App"  # Must match job name in workflow
        )
    }
    enforce_admins = $false  # Don't enforce for admins (allows emergency fixes)
    required_pull_request_reviews = @{
        dismiss_stale_reviews = $true  # Dismiss approvals when new commits are pushed
        require_code_owner_reviews = $false  # Set to $true if you have CODEOWNERS file
        required_approving_review_count = 1  # Minimum 1 approval required
        require_last_push_approval = $true  # The last pusher cannot approve their own PR
    }
    restrictions = $null  # No restrictions on who can push (set for protected repos)
    required_linear_history = $false  # Allow merge commits
    allow_force_pushes = $false  # Prevent force pushes
    allow_deletions = $false  # Prevent branch deletion
    block_creations = $false
    required_conversation_resolution = $true  # All conversations must be resolved
} | ConvertTo-Json -Depth 10

Write-Host "Applying branch protection rules..." -ForegroundColor Cyan

try {
    # Using gh api to set branch protection
    $result = gh api `
        --method PUT `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2022-11-28" `
        "/repos/$Owner/$Repo/branches/$Branch/protection" `
        --input - <<< $protectionPayload 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Branch protection rules applied successfully!" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Could not apply via API, trying gh CLI..." -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ API method failed, using alternative approach..." -ForegroundColor Yellow
}

#############################################################################
# STEP 2: Enable GitHub Advanced Security Features
#############################################################################
Write-Host ""
Write-Host "🔒 STEP 2: Enabling GitHub Advanced Security..." -ForegroundColor Yellow

# Enable security features via API
Write-Host "Enabling Dependabot alerts..." -ForegroundColor Cyan
gh api --method PUT "/repos/$Owner/$Repo/vulnerability-alerts" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Dependabot alerts enabled" -ForegroundColor Green
} else {
    Write-Host "⚠️ Dependabot alerts may already be enabled or requires admin" -ForegroundColor Yellow
}

Write-Host "Enabling Dependabot security updates..." -ForegroundColor Cyan
gh api --method PUT "/repos/$Owner/$Repo/automated-security-fixes" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Dependabot security updates enabled" -ForegroundColor Green
} else {
    Write-Host "⚠️ Dependabot security updates may already be enabled" -ForegroundColor Yellow
}

#############################################################################
# STEP 3: Create CODEOWNERS file (optional)
#############################################################################
Write-Host ""
Write-Host "📝 STEP 3: CODEOWNERS file..." -ForegroundColor Yellow

$codeownersPath = ".github/CODEOWNERS"
$codeownersContent = @"
# CODEOWNERS - Define who must review changes to specific files
# https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners

# Default owners for everything in the repo
* @$Owner

# Infrastructure and deployment files require review
.github/** @$Owner
deploy.ps1 @$Owner
*.bicep @$Owner

# Function code
*.cs @$Owner
"@

Write-Host "CODEOWNERS file content prepared (create manually if needed)" -ForegroundColor Cyan

#############################################################################
# STEP 4: Display Manual Steps
#############################################################################
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "📋 MANUAL STEPS REQUIRED IN GITHUB UI" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1️⃣  Go to: https://github.com/$Owner/$Repo/settings/branches" -ForegroundColor White
Write-Host "    - Click 'Add branch protection rule'" -ForegroundColor Gray
Write-Host "    - Branch name pattern: master" -ForegroundColor Gray
Write-Host "    - ✅ Require a pull request before merging" -ForegroundColor Gray
Write-Host "    - ✅ Require approvals (1)" -ForegroundColor Gray
Write-Host "    - ✅ Dismiss stale pull request approvals" -ForegroundColor Gray
Write-Host "    - ✅ Require status checks to pass (select 'Build Function App')" -ForegroundColor Gray
Write-Host "    - ✅ Require conversation resolution" -ForegroundColor Gray
Write-Host ""
Write-Host "2️⃣  Go to: https://github.com/$Owner/$Repo/settings/security_analysis" -ForegroundColor White
Write-Host "    - Enable 'Dependency graph'" -ForegroundColor Gray
Write-Host "    - Enable 'Dependabot alerts'" -ForegroundColor Gray
Write-Host "    - Enable 'Dependabot security updates'" -ForegroundColor Gray
Write-Host "    - Enable 'Code scanning' (if available)" -ForegroundColor Gray
Write-Host "    - Enable 'Secret scanning'" -ForegroundColor Gray
Write-Host ""
Write-Host "3️⃣  Go to: https://github.com/$Owner/$Repo/settings/environments" -ForegroundColor White
Write-Host "    - Configure 'production' environment" -ForegroundColor Gray
Write-Host "    - Add required reviewers" -ForegroundColor Gray
Write-Host "    - Add deployment branch restrictions (master only)" -ForegroundColor Gray
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "✅ Setup script complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Create a Pull Request from 'dev' to 'master':" -ForegroundColor Yellow
Write-Host "gh pr create --base master --head dev --title 'feat: DI-based ServiceBusClient' --body 'Adds dependency injection for Service Bus with environment-aware configuration'" -ForegroundColor Cyan
