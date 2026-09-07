<#
.SYNOPSIS
    Automated Git Repository Initialization and GitHub Remote Push Helper.
.DESCRIPTION
    Initializes git repository, stages all files, creates initial logical commit,
    configures remote origin to https://github.com/adityapukhraj1303/iac-quality-gate-pipeline.git,
    and guides pushing to GitHub.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Username = "adityapukhraj1303",

    [Parameter()]
    [string]$RepoName = "iac-quality-gate-pipeline"
)

$GitExe = "C:\Program Files\Git\cmd\git.exe"
if (-not (Test-Path $GitExe)) {
    $GitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($GitCmd) {
        $GitExe = $GitCmd.Source
    } else {
        Write-Error "Git was not found on this system. Please install Git."
        return
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Initializing Git Repository & GitHub Remote Setup" -ForegroundColor Cyan
Write-Host " Target Repo: https://github.com/$Username/$RepoName.git" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Initialize git
if (-not (Test-Path ".git")) {
    Write-Host "[1/5] Initializing Git repository..." -ForegroundColor Green
    & $GitExe init -b main
} else {
    Write-Host "[1/5] Git repository already initialized." -ForegroundColor Yellow
}

# 2. Add files
Write-Host "[2/5] Staging files..." -ForegroundColor Green
& $GitExe add .

# 3. Create initial commit
$status = & $GitExe status --porcelain
if ($status) {
    Write-Host "[3/5] Creating initial commit..." -ForegroundColor Green
    & $GitExe commit -m "feat: complete production-grade IaC Quality Gate & Auto-Deployment Pipeline"
} else {
    Write-Host "[3/5] Working tree clean, nothing to commit." -ForegroundColor Yellow
}

# 4. Configure Remote
$remoteUrl = "https://github.com/$Username/$RepoName.git"
$existingRemotes = & $GitExe remote
if ($existingRemotes -contains "origin") {
    Write-Host "[4/5] Updating remote 'origin' to $remoteUrl..." -ForegroundColor Green
    & $GitExe remote set-url origin $remoteUrl
} else {
    Write-Host "[4/5] Adding remote 'origin' ($remoteUrl)..." -ForegroundColor Green
    & $GitExe remote add origin $remoteUrl
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Git Repository Initialized Successfully!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next Step to Publish on GitHub:" -ForegroundColor Cyan
Write-Host "1. Go to: https://github.com/new" -ForegroundColor Yellow
Write-Host "2. Create a repository named: '$RepoName'" -ForegroundColor Yellow
Write-Host "   (Leave 'Initialize with README' UNCHECKED)" -ForegroundColor Yellow
Write-Host "3. In this folder, run:" -ForegroundColor Cyan
Write-Host "   git push -u origin main" -ForegroundColor White
Write-Host ""
