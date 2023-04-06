@echo off
setlocal enabledelayedexpansion
cd bitnami/%1
helm dependency update .
cd ..\..
helm package bitnami/%1 -d docs/
helm repo index .\docs\ --url https://nickmman.github.io/bitnami-charts-argocd-fixes