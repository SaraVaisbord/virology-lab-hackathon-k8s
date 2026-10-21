<#
Deploys the forms-validation app to the EKS cluster created by virology-lab-hackathon-infra.

  1. reads the infrastructure values (ECR, bucket, IAM role, region) from `terraform output`
  2. builds the backend and frontend images and pushes them to ECR (skip with -SkipBuild)
  3. fills the ${...} placeholders in the manifests and applies them, then prints the public address

Usage (after `aws sso login` and `terraform apply` in the infra repo):
  .\deploy.ps1 -InfraDir ..\virology-lab-hackathon-infra -AppDir ..\..\Downloads\האקתון
#>
param(
    [Parameter(Mandatory)] [string] $InfraDir,
    [Parameter(Mandatory)] [string] $AppDir,
    [string] $Tag = (Get-Date -Format "yyyyMMdd-HHmm"),
    [string] $AllowedCidrs = "",      # comma-separated; default: this computer's public address only
    [ValidateSet("true", "false")] [string] $LlmEnabled = "true",
    [switch] $SkipBuild
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

function Invoke-Checked([scriptblock] $Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Failed: $Command" }
}

# 1. Infrastructure values
Push-Location $InfraDir   # (not -chdir=: Windows PowerShell 5.1 mangles "-flag=value" arguments to native tools)
try { $out = Invoke-Checked { terraform output -json } | ConvertFrom-Json } finally { Pop-Location }
$region = ($out.cluster_connect.value -split "--region ")[1].Split(" ")[0]
$cluster = ($out.cluster_connect.value -split "--name ")[1].Trim()
$backendRepo = $out.ecr_repositories.value.backend
$frontendRepo = $out.ecr_repositories.value.frontend
$secretPrefix = $out.secret_names.value.db -replace "/db$", ""
if (-not $AllowedCidrs) {
    $AllowedCidrs = (Invoke-RestMethod https://checkip.amazonaws.com).Trim() + "/32"
}

# 2. Images → ECR
if (-not $SkipBuild) {
    $registry = $backendRepo.Split("/")[0]
    Invoke-Checked { aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry }
    Invoke-Checked { docker build -t "${backendRepo}:$Tag" (Join-Path $AppDir "backend") }
    Invoke-Checked { docker build -t "${frontendRepo}:$Tag" --build-arg VITE_API_BASE_URL=/api (Join-Path $AppDir "frontend") }
    Invoke-Checked { docker push "${backendRepo}:$Tag" }
    Invoke-Checked { docker push "${frontendRepo}:$Tag" }
}

# 3. Manifests
Invoke-Checked { aws eks update-kubeconfig --region $region --name $cluster }
$values = @{
    AWS_REGION       = $region
    SECRET_PREFIX    = $secretPrefix
    BACKEND_ROLE_ARN = $out.backend_role_arn.value
    FILES_BUCKET     = $out.files_bucket.value
    BACKEND_IMAGE    = "${backendRepo}:$Tag"
    FRONTEND_IMAGE   = "${frontendRepo}:$Tag"
    ALLOWED_CIDRS    = $AllowedCidrs
    LLM_ENABLED      = $LlmEnabled
}
$rendered = Join-Path ([System.IO.Path]::GetTempPath()) "virology-lab-manifests"
Remove-Item -Recurse -Force $rendered -ErrorAction SilentlyContinue
foreach ($file in Get-ChildItem $here -Recurse -Filter *.yaml) {
    $text = Get-Content $file.FullName -Raw
    foreach ($name in $values.Keys) { $text = $text.Replace('${' + $name + '}', $values[$name]) }
    if ($text -match '\$\{[A-Z_]+\}') { throw "Unfilled placeholder $($Matches[0]) in $($file.Name)" }
    $target = Join-Path $rendered $file.FullName.Substring($here.Length + 1)
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    [System.IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding $false))  # UTF-8 without BOM
}
foreach ($part in @("namespace.yaml", "operators", "backend", "frontend", "ingress.yaml")) {
    Invoke-Checked { kubectl apply -f (Join-Path $rendered $part) }
}
Invoke-Checked { kubectl -n virology-lab rollout status deployment/backend '--timeout=10m' }
Invoke-Checked { kubectl -n virology-lab rollout status deployment/frontend '--timeout=5m' }

$address = ""
for ($i = 0; $i -lt 60 -and -not $address; $i++) {
    $address = kubectl -n virology-lab get ingress virology-lab -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
    if (-not $address) { Start-Sleep 5 }
}
Write-Host "`nThe system: http://$address   (open to: $AllowedCidrs)"
