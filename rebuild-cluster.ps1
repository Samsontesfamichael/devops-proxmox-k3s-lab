[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$RetryCount = if ($env:RETRY_COUNT) { [int]$env:RETRY_COUNT } else { 3 }
$RetryDelay = if ($env:RETRY_DELAY) { [int]$env:RETRY_DELAY } else { 30 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TerraformDir = Join-Path $ScriptDir "..\terraform"
$AnsibleDir = Join-Path $ScriptDir "ansible"
$InventoryFile = Join-Path $AnsibleDir "hosts.ini"
$Kubeconfig = Join-Path $HOME ".kube\config-proxmox-k3s"
$ENV:KUBECONFIG = $Kubeconfig

function Retry-Command {
  param(
    [int]$Attempts,
    [int]$DelaySeconds,
    [ScriptBlock]$ScriptBlock,
    [string]$Label
  )
  $n = 1
  while ($true) {
    try {
      & $ScriptBlock
      return
    } catch {
      if ($n -ge $Attempts) {
        Write-Host "[ERROR] $Label failed after $Attempts attempts." -ForegroundColor Red
        throw
      }
      Write-Host "[RETRY $n/$Attempts] $Label failed. Retrying in ${DelaySeconds}s..." -ForegroundColor Yellow
      Start-Sleep -Seconds $DelaySeconds
      $n++
    }
  }
}

function Wait-ClusterReady {
  param(
    [string]$Label,
    [int]$TimeoutSeconds = 600,
    [ScriptBlock]$Check
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  Write-Host "[WAIT] $Label" -ForegroundColor Yellow
  while ((Get-Date) -lt $deadline) {
    try {
      & $Check | Out-Null
      Write-Host "[READY] $Label" -ForegroundColor Green
      return
    } catch {}
    Start-Sleep -Seconds 10
  }
  Write-Host "[ERROR] Timeout waiting for: $Label" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Proxmox K3s Cluster Rebuild Pipeline" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path (Join-Path $TerraformDir ".env"))) {
    Write-Host "[ERROR] terraform\.env not found. Create it with TF_VAR_proxmox_api_token, TF_VAR_proxmox_endpoint, TF_VAR_gateway." -ForegroundColor Red
    exit 1
}

Write-Host "[1/6] Destroying old infrastructure..." -ForegroundColor Yellow
Retry-Command -Attempts $RetryCount -DelaySeconds $RetryDelay -Label "terraform destroy" -ScriptBlock {
  Push-Location $TerraformDir
  Get-Content .env | ForEach-Object { if ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] } }
  terraform destroy -auto-approve
  Pop-Location
}

Write-Host "[2/6] Provisioning fresh infrastructure..." -ForegroundColor Yellow
Retry-Command -Attempts $RetryCount -DelaySeconds $RetryDelay -Label "terraform apply" -ScriptBlock {
  Push-Location $TerraformDir
  Get-Content .env | ForEach-Object { if ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] } }
  terraform apply -auto-approve
  Pop-Location
}

Write-Host "[3/6] Generating dynamic Ansible inventory from Terraform outputs..." -ForegroundColor Yellow
Retry-Command -Attempts $RetryCount -DelaySeconds $RetryDelay -Label "generate inventory" -ScriptBlock {
  Push-Location $TerraformDir
  $masterIp = terraform output -raw master_ip
  $workerIpsJson = terraform output -json worker_ips | ConvertFrom-Json
  Pop-Location

  $lines = @("[master]")
  $lines += "${masterIp} ansible_user=root"
  $lines += ""
  $lines += "[workers]"
  foreach ($key in ($workerIpsJson.PSObject.Properties | Sort-Object Name | ForEach-Object { $_.Name })) {
      $ip = $workerIpsJson.$key
      $lines += "${ip} ansible_user=root # worker_$key"
  }
  $lines += ""
  $lines += "[k3s_cluster:children]"
  $lines += "master"
  $lines += "workers"

  $lines | Out-File -FilePath $InventoryFile -Encoding utf8
  Write-Host "  Inventory written to $InventoryFile" -ForegroundColor Green
}

Write-Host "[4/6] Running Ansible automation..." -ForegroundColor Yellow
Retry-Command -Attempts $RetryCount -DelaySeconds $RetryDelay -Label "ansible-playbook playbook.yml" -ScriptBlock {
  Push-Location $AnsibleDir
  ansible-playbook -i $InventoryFile playbook.yml
  Pop-Location
}
Retry-Command -Attempts $RetryCount -DelaySeconds $RetryDelay -Label "ansible-playbook optimize-storage.yml" -ScriptBlock {
  Push-Location $AnsibleDir
  ansible-playbook -i $InventoryFile optimize-storage.yml
  Pop-Location
}

Write-Host "[4.5/6] Waiting for K3s cluster to become Ready..." -ForegroundColor Yellow
Wait-ClusterReady -Label "all kube-system pods Ready" -TimeoutSeconds 600 -Check {
  kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
}
Wait-ClusterReady -Label "all nodes Ready" -TimeoutSeconds 600 -Check {
  kubectl get nodes --no-headers | ForEach-Object { if ($_ -notmatch ' Ready ') { throw "Node not ready" } }
}

Write-Host "[5/6] Installing cluster addons (cert-manager, metrics-server, external-secrets)..." -ForegroundColor Yellow
Retry-Command -Attempts $RetryCount -DelaySeconds $RetryDelay -Label "install addons" -ScriptBlock {
  & "${ScriptDir}\install-addons.ps1"
}

Write-Host "[6/6] Deploying Kubernetes applications..." -ForegroundColor Yellow
Retry-Command -Attempts $RetryCount -DelaySeconds $RetryDelay -Label "apply kubernetes-core" -ScriptBlock {
  kubectl apply --wait --timeout=5m -f (Join-Path $ScriptDir "..\kubernetes-core")
}
kubectl wait --for=condition=Ready clusterissuer/selfsigned-cluster-issuer --timeout=120s | Out-Null
Retry-Command -Attempts $RetryCount -DelaySeconds $RetryDelay -Label "apply kubernetes-architecture" -ScriptBlock {
  kubectl apply --wait --timeout=5m -f (Join-Path $ScriptDir "..\kubernetes-architecture")
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Cluster rebuilt successfully!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
kubectl get nodes -o wide
