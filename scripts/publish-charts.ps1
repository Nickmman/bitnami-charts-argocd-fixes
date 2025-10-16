param(
    [string]$RepoUrl  = "https://github.com/nickmman/bitnami-charts-argocd-fixes",
    [string]$PagesUrl = "https://nickmman.github.io/bitnami-charts-argocd-fixes",
    [string]$Branch   = "releases"
)

$ErrorActionPreference = 'Stop'

Write-Host "🏗️ Packaging Helm charts from ./bitnami ..."

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Error "Helm CLI not found. Install Helm and retry."
}

git checkout main | Out-Null

Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path build | Out-Null

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

if (-not (Test-Path build\*.tgz)) {
    Write-Warning "No .tgz packages produced. Aborting publish."
    exit 0
}

git fetch origin $Branch | Out-Null
git checkout $Branch | Out-Null
git pull origin $Branch | Out-Null

Get-ChildItem build\*.tgz | ForEach-Object { Move-Item $_.FullName . -Force }

if (Test-Path "index.yaml") {
    helm repo index . --url $PagesUrl --merge index.yaml
} else {
    helm repo index . --url $PagesUrl
}

if (-not (Test-Path ".nojekyll")) { New-Item -ItemType File -Name ".nojekyll" | Out-Null }

git add .
$commitMsg = "📦 Publish Helm charts $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
git commit -m $commitMsg -q || Write-Host "No changes to commit."
git push origin $Branch

git checkout main | Out-Null

Write-Host "✅ Published. Helm repo index: $PagesUrl/index.yaml"
