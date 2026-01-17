#!/bin/bash
# =============================================================================
# Kafka Cluster Deployment Script
# =============================================================================
# Deploys the Kafka cluster with NodePools and Cruise Control on Kubernetes.
#
# Prerequisites:
#   - Strimzi operator installed (run ../setup/install.sh first)
#   - kubectl configured to access your cluster
#
# Usage:
#   ./deploy.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="kafka"

echo "=========================================="
echo " Kafka Cluster Deployment"
echo " with KafkaNodePools and Cruise Control"
echo "=========================================="
echo ""

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check Strimzi operator is running
echo "[1/5] Checking Strimzi operator..."
if ! kubectl get pods -n "$NAMESPACE" -l name=strimzi-cluster-operator --no-headers 2>/dev/null | grep -q Running; then
    echo "Error: Strimzi operator is not running in namespace $NAMESPACE"
    echo "Run ../setup/install.sh first"
    exit 1
fi
echo "Strimzi operator is running"
echo ""

# Deploy KafkaNodePools
echo "[2/5] Deploying KafkaNodePools..."
echo "  - Controllers (5 replicas, IDs: 0-4)"
echo "  - POC Brokers (3 replicas, IDs: 100-102)"
echo "  - General Brokers (2 replicas, IDs: 200-201)"
kubectl apply -f "$PROJECT_DIR/kafka/kafka-nodepool-controllers.yaml" -n "$NAMESPACE"
kubectl apply -f "$PROJECT_DIR/kafka/kafka-nodepool-poc-brokers.yaml" -n "$NAMESPACE"
kubectl apply -f "$PROJECT_DIR/kafka/kafka-nodepool-general-brokers.yaml" -n "$NAMESPACE"
echo ""

# Deploy Kafka cluster
echo "[3/5] Deploying Kafka cluster..."
kubectl apply -f "$PROJECT_DIR/kafka/kafka-cluster.yaml" -n "$NAMESPACE"
echo ""

# Wait for cluster to be ready
echo "[4/5] Waiting for Kafka cluster to be ready..."
echo "      This may take 5-10 minutes on first deployment..."
echo ""

# Wait for Kafka resource to be ready
kubectl wait kafka/kafka-poc --for=condition=Ready -n "$NAMESPACE" --timeout=600s || {
    echo ""
    echo "Warning: Kafka cluster not ready within timeout"
    echo "Check status with: kubectl get kafka kafka-poc -n $NAMESPACE"
    echo "Check pods with: kubectl get pods -n $NAMESPACE"
}

echo ""

# Show cluster status
echo "[5/5] Cluster deployment complete!"
echo ""
echo "=========================================="
echo " Cluster Status"
echo "=========================================="
echo ""

echo "Kafka pods:"
kubectl get pods -n "$NAMESPACE" -l strimzi.io/cluster=kafka-poc --no-headers | sort
echo ""

echo "NodePools:"
kubectl get kafkanodepools -n "$NAMESPACE" -l strimzi.io/cluster=kafka-poc
echo ""

echo "Kafka cluster:"
kubectl get kafka -n "$NAMESPACE"
echo ""

echo "=========================================="
echo " Deployment Complete"
echo "=========================================="
echo ""
echo "Broker Sets:"
echo "  POC Brokers:     IDs 100, 101, 102 (for poc_* topics)"
echo "  General Brokers: IDs 200, 201 (for other topics)"
echo ""
echo "Next steps:"
echo "  # Create topics with controlled placement"
echo "  ./create-topics.sh"
echo ""
echo "  # Validate placement"
echo "  ./validate-placement.sh"
echo ""
echo "  # Trigger rebalance"
echo "  ./trigger-rebalance.sh"
echo ""
