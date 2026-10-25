<#
Applies this repository to the EKS cluster by hand and points the domain at the load balancer.

Releases normally deploy themselves: the app repository's CI/CD builds the images, sets their tag in
kustomization.yaml and applies it. This script is for the first deployment, the DNS records, and re-applying
after a change in this repository (for example in cluster.env).

  1. applies the manifests (`kubectl apply -k`) and waits for the rollout
  2. points <domain> and www.<domain> at the ALB (Route 53 ALIAS records)

Usage (after `aws sso login` and `terraform apply` in the infra repo):
  .\deploy.ps1 -InfraDir ..\virology-lab-hackathon-infra
#>
param(
    [Parameter(Mandatory)] [string] $InfraDir
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

function Invoke-Checked([scriptblock] $Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Failed: $Command" }
}

# The cluster's values (the same file the manifests are built from)
$cluster = @{}
foreach ($line in Get-Content (Join-Path $here "cluster.env")) {
    if ($line -match '^\s*([A-Z_]+)=(.*)$') { $cluster[$Matches[1]] = $Matches[2].Trim() }
}
$region = $cluster.AWS_REGION
$domain = $cluster.DOMAIN
$clusterName = $cluster.EKS_CLUSTER

# 1. Manifests
Invoke-Checked { aws eks update-kubeconfig --region $region --name $clusterName }
Invoke-Checked { kubectl apply -k $here }
Invoke-Checked { kubectl -n virology-lab rollout status deployment/backend '--timeout=10m' }
Invoke-Checked { kubectl -n virology-lab rollout status deployment/frontend '--timeout=5m' }

$address = ""
for ($i = 0; $i -lt 60 -and -not $address; $i++) {
    $address = kubectl -n virology-lab get ingress virology-lab -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
    if (-not $address) { Start-Sleep 5 }
}
if (-not $address) { throw "The ALB has no address yet: kubectl -n virology-lab describe ingress virology-lab" }

# 2. DNS: <domain> and www.<domain> → the ALB (ALIAS records, so they follow the ALB if its IPs change)
Push-Location $InfraDir   # (not -chdir=: Windows PowerShell 5.1 mangles "-flag=value" arguments to native tools)
try { $hostedZone = (Invoke-Checked { terraform output -raw hosted_zone_id }) } finally { Pop-Location }
$albZone = Invoke-Checked { aws elbv2 describe-load-balancers --region $region --query "LoadBalancers[?DNSName=='$address'].CanonicalHostedZoneId" --output text }
$changes = foreach ($name in @($domain, "www.$domain")) {
    @{ Action = "UPSERT"; ResourceRecordSet = @{ Name = $name; Type = "A"
        AliasTarget = @{ HostedZoneId = "$albZone".Trim(); DNSName = "dualstack.$address"; EvaluateTargetHealth = $false } } }
}
$batch = Join-Path ([System.IO.Path]::GetTempPath()) "virology-lab-dns-change.json"
[System.IO.File]::WriteAllText($batch, (@{ Changes = @($changes) } | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
Invoke-Checked { aws route53 change-resource-record-sets --hosted-zone-id $hostedZone --change-batch "file://$batch" --query "ChangeInfo.Status" --output text }

Write-Host "`nThe system: https://$domain   (open to: $($cluster.ALLOWED_CIDRS))"
