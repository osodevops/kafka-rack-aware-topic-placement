#!/bin/bash
# =============================================================================
# Strimzi Operator Installation Script
# =============================================================================
# This script installs the Strimzi Kafka operator on a Kubernetes cluster.
#
# Prerequisites:
#   - kubectl configured to access your cluster
#   - Minikube or other Kubernetes cluster running
#
# Usage:
#   ./install.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRIMZI_VERSION="0.43.0"
NAMESPACE="kafka"

echo "=========================================="
echo " Strimzi Operator Installation"
echo "=========================================="
echo ""
echo "Strimzi Version: $STRIMZI_VERSION"
echo "Namespace: $NAMESPACE"
echo ""

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
echo "[1/4] Checking cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    echo "Make sure your cluster is running and kubectl is configured"
    exit 1
fi
echo "Connected to cluster"
echo ""

# Create namespace
echo "[2/4] Creating namespace..."
kubectl apply -f "$SCRIPT_DIR/00-namespace.yaml"
echo ""

# Install Strimzi operator
echo "[3/4] Installing Strimzi operator..."
echo "Downloading and applying Strimzi installation files..."

kubectl create -f "https://strimzi.io/install/latest?namespace=$NAMESPACE" -n "$NAMESPACE" 2>/dev/null || \
kubectl replace -f "https://strimzi.io/install/latest?namespace=$NAMESPACE" -n "$NAMESPACE"

echo ""

# Wait for operator to be ready
echo "[4/4] Waiting for Strimzi operator to be ready..."
kubectl wait --for=condition=Ready pod -l name=strimzi-cluster-operator -n "$NAMESPACE" --timeout=300s

echo ""
echo "=========================================="
echo " Strimzi Operator Installed Successfully"
echo "=========================================="
echo ""
echo "Operator pod:"
kubectl get pods -n "$NAMESPACE" -l name=strimzi-cluster-operator
echo ""
echo "Next steps:"
echo "  cd ../kafka && kubectl apply -f . -n kafka"
echo "  cd ../topics && kubectl apply -f . -n kafka"
echo ""
