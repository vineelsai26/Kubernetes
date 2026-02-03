# Argo CD POC Setup Script for Langfuse (PowerShell version)
# Run this script step by step to set up the POC

$ErrorActionPreference = "Stop"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Argo CD POC Setup for Langfuse" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

function Check-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor Yellow

    # Check kubectl
    try {
        $null = kubectl version --client 2>&1
    } catch {
        Write-Host "kubectl not found. Please install kubectl first." -ForegroundColor Red
        exit 1
    }

    # Check helm
    try {
        $null = helm version 2>&1
    } catch {
        Write-Host "helm not found. Please install Helm 3.x first." -ForegroundColor Red
        exit 1
    }

    # Check cluster connection
    try {
        $null = kubectl cluster-info 2>&1
    } catch {
        Write-Host "Cannot connect to Kubernetes cluster. Please check your kubeconfig." -ForegroundColor Red
        exit 1
    }

    Write-Host "All prerequisites met!" -ForegroundColor Green
    Write-Host ""
}

function Install-ArgoCD {
    Write-Host "Step 1: Installing Argo CD..." -ForegroundColor Yellow

    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # Install Argo CD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    Write-Host "Waiting for Argo CD to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

    Write-Host "Argo CD installed successfully!" -ForegroundColor Green
    Write-Host ""
}

function Get-ArgoCDPassword {
    Write-Host "Step 2: Getting Argo CD admin password..." -ForegroundColor Yellow

    $encodedPassword = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
    $password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedPassword))

    Write-Host "Admin password: $password" -ForegroundColor Green
    Write-Host ""
    Write-Host "Save this password! You'll need it to log in."
    Write-Host ""

    return $password
}

function Create-Secrets {
    Write-Host "Step 3: Creating Langfuse namespace and secrets..." -ForegroundColor Yellow

    $secretsFile = Join-Path $PSScriptRoot "langfuse\base\secrets-example.yaml"

    if (Select-String -Path $secretsFile -Pattern "REPLACE_ME" -Quiet) {
        Write-Host "WARNING: You need to customize langfuse/base/secrets-example.yaml first!" -ForegroundColor Red
        Write-Host "Edit the file and replace all placeholder values before continuing."
        Write-Host ""
        $response = Read-Host "Have you customized the secrets file? (y/n)"
        if ($response -notmatch "^[Yy]$") {
            Write-Host "Please customize the secrets file first, then run this step again."
            return
        }
    }

    kubectl apply -f $secretsFile

    Write-Host "Secrets created successfully!" -ForegroundColor Green
    Write-Host ""
}

function Deploy-Langfuse {
    Write-Host "Step 4: Deploying Langfuse (simple POC version)..." -ForegroundColor Yellow

    $appFile = Join-Path $PSScriptRoot "langfuse\applications\langfuse-dev-simple.yaml"
    kubectl apply -f $appFile

    Write-Host "Waiting for Argo CD to start syncing..."
    Start-Sleep -Seconds 10

    Write-Host "Langfuse application created!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Check status with: kubectl get applications -n argocd"
    Write-Host ""
}

function Show-PortForwardInstructions {
    Write-Host "Step 5: Port forwarding Argo CD UI..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run this command in a separate PowerShell window:"
    Write-Host "kubectl port-forward svc/argocd-server -n argocd 8080:443" -ForegroundColor Green
    Write-Host ""
    Write-Host "Then access the UI at: https://localhost:8080"
    Write-Host "Username: admin"
    Write-Host "Password: (from Step 2)"
    Write-Host ""
}

function Check-Status {
    Write-Host "Checking deployment status..." -ForegroundColor Yellow
    Write-Host ""

    Write-Host "=== Argo CD Applications ===" -ForegroundColor Cyan
    kubectl get applications -n argocd
    Write-Host ""

    Write-Host "=== Langfuse Pods ===" -ForegroundColor Cyan
    try {
        kubectl get pods -n langfuse
    } catch {
        Write-Host "Namespace langfuse not found yet"
    }
    Write-Host ""

    Write-Host "=== Langfuse Services ===" -ForegroundColor Cyan
    try {
        kubectl get svc -n langfuse
    } catch {
        Write-Host "No services yet"
    }
    Write-Host ""
}

function Show-Menu {
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "  Choose an action:" -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "  0. Check prerequisites"
    Write-Host "  1. Install Argo CD"
    Write-Host "  2. Get Argo CD admin password"
    Write-Host "  3. Create Langfuse secrets"
    Write-Host "  4. Deploy Langfuse (simple POC)"
    Write-Host "  5. Show port-forward instructions"
    Write-Host "  6. Check deployment status"
    Write-Host "  A. Run ALL steps (1-5)"
    Write-Host "  Q. Quit"
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
}

# Main script
Set-Location $PSScriptRoot

# Check for --all flag
if ($args -contains "--all") {
    Check-Prerequisites
    Install-ArgoCD
    Get-ArgoCDPassword
    Create-Secrets
    Deploy-Langfuse
    Show-PortForwardInstructions
    Check-Status
    exit 0
}

# Interactive menu
while ($true) {
    Show-Menu
    $choice = Read-Host "Enter your choice"
    Write-Host ""

    switch ($choice.ToUpper()) {
        "0" { Check-Prerequisites }
        "1" { Install-ArgoCD }
        "2" { Get-ArgoCDPassword }
        "3" { Create-Secrets }
        "4" { Deploy-Langfuse }
        "5" { Show-PortForwardInstructions }
        "6" { Check-Status }
        "A" {
            Check-Prerequisites
            Install-ArgoCD
            Get-ArgoCDPassword
            Create-Secrets
            Deploy-Langfuse
            Show-PortForwardInstructions
            Check-Status
        }
        "Q" {
            Write-Host "Goodbye!"
            exit 0
        }
        default {
            Write-Host "Invalid choice. Please try again." -ForegroundColor Red
        }
    }

    Write-Host ""
    Read-Host "Press Enter to continue..."
    Write-Host ""
}
