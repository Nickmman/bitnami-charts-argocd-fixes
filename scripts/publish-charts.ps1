param(
    [string]$RepoUrl  = "https://github.com/nickmman/bitnami-charts-argocd-fixes",
    [string]$PagesUrl = "https://nickmman.github.io/bitnami-charts-argocd-fixes",
    [string]$Branch   = "releases",
    [string]$Chart    = ""   # Optional, e.g. "redis"
)

$ErrorActionPreference = 'Stop'

Write-Host "🏗️ Packaging Helm charts..."

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Error "Helm CLI not found. Please install Helm and retry."
}

# Always start from main
git checkout main | Out-Null

# Clean build folder
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path build | Out-Null

# Determine which charts to package
if ($Chart -ne "") {
    $chartPath = Join-Path "bitnami" $Chart
    if (-not (Test-Path "$chartPath\Chart.yaml")) {
        Write-Error "Chart not found: $chartPath"
        exit 1
    }
    Write-Host "📦 Packaging single chart: $chartPath"
    helm dependency update $chartPath | Out-Null
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

# Abort if no packages were created
if (-not (Test-Path build\*.tgz)) {
    Write-Warning "No .tgz packages produced. Aborting publish."
    exit 0
}

# Checkout the releases branch
git fetch origin $Branch | Out-Null
git checkout $Branch | Out-Null
git pull origin $Branch | Out-Null

# Move packaged charts to root
Get-ChildItem build\*.tgz | ForEach-Object { Move-Item $_.FullName . -Force }

# Generate or update index.yaml
if (Test-Path "index.yaml") {
    helm repo index . --url $PagesUrl --merge index.yaml
} else {
    helm repo index . --url $PagesUrl
}

# Ensure .nojekyll exists
if (-not (Test-Path ".nojekyll")) { New-Item -ItemType File -Name ".nojekyll" | Out-Null }

# Commit and push changes
git add .
$commitMsg = if ($Chart -ne "") { "📦 Publish $Chart chart $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" } else { "📦 Publish all charts $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" }
git commit -m $commitMsg -q || Write-Host "No changes to commit."
git push origin $Branch

# Return to main
git checkout main | Out-Null

Write-Host "✅ Published. Helm repo index: $PagesUrl/index.yaml"
