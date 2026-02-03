#!/bin/bash
# Argo CD POC Setup Script for Langfuse
# Run this script step by step to set up the POC

set -e

echo "=============================================="
echo "  Argo CD POC Setup for Langfuse"
echo "=============================================="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        echo -e "${RED}helm not found. Please install Helm 3.x first.${NC}"
        exit 1
    fi

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
        exit 1
    fi

    echo -e "${GREEN}All prerequisites met!${NC}"
    echo
}

# Step 1: Install Argo CD
install_argocd() {
    echo -e "${YELLOW}Step 1: Installing Argo CD...${NC}"

    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # Install Argo CD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "Waiting for Argo CD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

    echo -e "${GREEN}Argo CD installed successfully!${NC}"
    echo
}

# Step 2: Get Argo CD admin password
get_argocd_password() {
    echo -e "${YELLOW}Step 2: Getting Argo CD admin password...${NC}"

    PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo -e "${GREEN}Admin password: ${PASSWORD}${NC}"
    echo
    echo "Save this password! You'll need it to log in."
    echo
}

# Step 3: Create Langfuse namespace and secrets
create_secrets() {
    echo -e "${YELLOW}Step 3: Creating Langfuse namespace and secrets...${NC}"

    # Check if secrets file has been customized
    if grep -q "REPLACE_ME" langfuse/base/secrets-example.yaml 2>/dev/null; then
        echo -e "${RED}WARNING: You need to customize langfuse/base/secrets-example.yaml first!${NC}"
        echo "Edit the file and replace all placeholder values before continuing."
        echo
        read -p "Have you customized the secrets file? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Please customize the secrets file first, then run this step again."
            return 1
        fi
    fi

    kubectl apply -f langfuse/base/secrets-example.yaml

    echo -e "${GREEN}Secrets created successfully!${NC}"
    echo
}

# Step 4: Deploy Langfuse with Argo CD (simple version)
deploy_langfuse_simple() {
    echo -e "${YELLOW}Step 4: Deploying Langfuse (simple POC version)...${NC}"

    kubectl apply -f langfuse/applications/langfuse-dev-simple.yaml

    echo "Waiting for Argo CD to sync..."
    sleep 10

    echo -e "${GREEN}Langfuse application created!${NC}"
    echo
    echo "Check status with: kubectl get applications -n argocd"
    echo
}

# Step 5: Port forward to access Argo CD UI
port_forward_argocd() {
    echo -e "${YELLOW}Step 5: Port forwarding Argo CD UI...${NC}"
    echo
    echo "Run this command in a separate terminal:"
    echo -e "${GREEN}kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
    echo
    echo "Then access the UI at: https://localhost:8080"
    echo "Username: admin"
    echo "Password: (from Step 2)"
    echo
}

# Step 6: Check deployment status
check_status() {
    echo -e "${YELLOW}Checking deployment status...${NC}"
    echo

    echo "=== Argo CD Applications ==="
    kubectl get applications -n argocd
    echo

    echo "=== Langfuse Pods ==="
    kubectl get pods -n langfuse 2>/dev/null || echo "Namespace langfuse not found yet"
    echo

    echo "=== Langfuse Services ==="
    kubectl get svc -n langfuse 2>/dev/null || echo "No services yet"
    echo

    echo "=== Langfuse Ingress ==="
    kubectl get ingress -n langfuse 2>/dev/null || echo "No ingress yet"
    echo
}

# Main menu
show_menu() {
    echo "=============================================="
    echo "  Choose an action:"
    echo "=============================================="
    echo "  0. Check prerequisites"
    echo "  1. Install Argo CD"
    echo "  2. Get Argo CD admin password"
    echo "  3. Create Langfuse secrets"
    echo "  4. Deploy Langfuse (simple POC)"
    echo "  5. Show port-forward instructions"
    echo "  6. Check deployment status"
    echo "  A. Run ALL steps (1-5)"
    echo "  Q. Quit"
    echo "=============================================="
    echo
}

# Parse command line arguments
if [ "$1" == "--all" ]; then
    check_prerequisites
    install_argocd
    get_argocd_password
    create_secrets
    deploy_langfuse_simple
    port_forward_argocd
    check_status
    exit 0
fi

# Interactive menu
while true; do
    show_menu
    read -p "Enter your choice: " choice
    echo

    case $choice in
        0) check_prerequisites ;;
        1) install_argocd ;;
        2) get_argocd_password ;;
        3) create_secrets ;;
        4) deploy_langfuse_simple ;;
        5) port_forward_argocd ;;
        6) check_status ;;
        [Aa])
            check_prerequisites
            install_argocd
            get_argocd_password
            create_secrets
            deploy_langfuse_simple
            port_forward_argocd
            check_status
            ;;
        [Qq])
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            ;;
    esac

    echo
    read -p "Press Enter to continue..."
    echo
done
