#!/usr/bin/env bash
# ==============================================================================
# Automated Git & GitHub Setup Helper (for Git Bash / Linux / macOS)
# ==============================================================================

set -eo pipefail

USERNAME="adityapukhraj1303"
REPO_NAME="iac-quality-gate-pipeline"
REMOTE_URL="https://github.com/${USERNAME}/${REPO_NAME}.git"

echo "=========================================================="
echo " Initializing Git Repository & GitHub Remote Setup"
echo " Target Repo: ${REMOTE_URL}"
echo "=========================================================="

# 1. Initialize git
if [ ! -d ".git" ]; then
    echo "[1/4] Initializing Git repository with branch 'main'..."
    git init -b main
else
    echo "[1/4] Git repository already initialized."
    git branch -M main
fi

# 2. Add files
echo "[2/4] Staging files..."
git add .

# 3. Create initial commit
if git status --porcelain | grep -q .; then
    echo "[3/4] Creating initial commit..."
    git commit -m "feat: complete production-grade IaC Quality Gate & Auto-Deployment Pipeline"
else
    echo "[3/4] Working tree clean, nothing to commit."
fi

# 4. Configure Remote
if git remote | grep -q "^origin$"; then
    echo "[4/4] Updating remote 'origin' to ${REMOTE_URL}..."
    git remote set-url origin "${REMOTE_URL}"
else
    echo "[4/4] Adding remote 'origin' (${REMOTE_URL})..."
    git remote add origin "${REMOTE_URL}"
fi

echo "=========================================================="
echo " Git Repository Initialized Successfully!"
echo "=========================================================="
echo ""
echo "Next Step to Publish to GitHub:"
echo "1. Ensure repository is created at: https://github.com/new"
echo "   Repository name: '${REPO_NAME}' (Uncheck 'Add a README file')"
echo "2. Push your code:"
echo "   git push -u origin main"
echo ""
