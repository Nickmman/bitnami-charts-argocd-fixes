param(
    [string]$RepoUrl  = "https://github.com/nickmman/bitnami-charts-argocd-fixes",
    [string]$PagesUrl = "https://nickmman.github.io/bitnami-charts-argocd-fixes",
    [string]$Branch   = "releases",
    [string]$Chart    = ""   # Optional, e.g. "redis"
)

$ErrorActionPreference = 'Stop'

Write-Host "🏗️  Packaging Helm charts..."

# --- Check prerequisites ---
if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Error "Helm CLI not found. Please install Helm and retry."
    exit 1
}

# --- Always start from main ---
git checkout main | Out-Null

# --- Clean build folder ---
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path build | Out-Null

# --- Determine which chart(s) to package ---
if ($Chart -ne "") {
    $chartPath = Join-Path "bitnami" $Chart
    if (-not (Test-Path "$chartPath\Chart.yaml")) {
        Write-Error "Chart not found: $chartPath"
        exit 1
    }
    Write-Host "📦 Packaging single chart: $chartPath"
    try {
        helm dependency update $chartPath | Out-Null
    } catch {
        Write-Warning "Dependency update failed or not needed for $chartPath. Continuing."
    }
    helm package $chartPath -d build | Out-Null
}
else {
    Write-Host "📦 Packaging all charts under ./bitnami ..."
    $charts = Get-ChildItem -Recurse -Path bitnami -Filter Chart.yaml
    if ($charts.Count -eq 0) {
        Write-Warning "No charts found under ./bitnami. Nothing to publish."
        exit 0
    }
    foreach ($chartYaml in $charts) {
        $chartDir = Split-Path $chartYaml.FullName
        Write-Host "📦 Packaging: $chartDir"
        try {
            helm dependency update $chartDir | Out-Null
        } catch {
            Write-Warning "Dependency update failed or not needed for $chartDir. Continuing."
        }
        helm package $chartDir -d build | Out-Null
    }
}

# --- Abort if nothing was packaged ---
if (-not (Test-Path build\*.tgz)) {
    Write-Warning "No .tgz packages produced. Aborting publish."
    exit 0
}

# --- Prepare to switch branches ---
Write-Host "🔁 Preparing to switch to '$Branch' branch..."

# Stash local changes (Chart.lock updates, etc.)
$hasChanges = (git status --porcelain)
if ($hasChanges) {
    Write-Host "💾 Stashing local changes..."
    git stash push -m "temp stash before switching to $Branch" | Out-Null
}

# --- Switch to releases branch ---
git fetch origin $Branch | Out-Null
git checkout $Branch | Out-Null

# --- Move packaged charts ---
Get-ChildItem build\*.tgz | ForEach-Object { Move-Item $_.FullName . -Force }

# --- Generate or update index.yaml ---
if (Test-Path "index.yaml") {
    helm repo index . --url $PagesUrl --merge index.yaml
} else {
    helm repo index . --url $PagesUrl
}

# --- Ensure .nojekyll exists ---
if (-not (Test-Path ".nojekyll")) {
    New-Item -ItemType File -Name ".nojekyll" | Out-Null
}

# --- Commit and push ---
git add .
$commitMsg = if ($Chart -ne "") { 
    "📦 Publish $Chart chart $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 
} else { 
    "📦 Publish all charts $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 
}
git commit -m $commitMsg -q || Write-Host "No changes to commit."
git push origin $Branch

# --- Return to main ---
git checkout main | Out-Null

# --- Restore stashed changes ---
if ($hasChanges) {
    Write-Host "🔄 Restoring stashed changes..."
    git stash pop | Out-Null
}

Write-Host "✅ Published successfully!"
Write-Host "📂 Helm repo index: $PagesUrl/index.yaml"
