#!/bin/bash
# =============================================================================
# Cleanup Script for Strimzi Kafka Deployment
# =============================================================================
# Removes all Kafka resources from the cluster.
#
# Usage:
#   ./cleanup.sh [--all]
#
# Options:
#   --all    Also remove the Strimzi operator and namespace
# =============================================================================

set -e

NAMESPACE="kafka"

# Parse arguments
REMOVE_ALL=false
if [[ "$1" == "--all" ]]; then
    REMOVE_ALL=true
fi

echo "=========================================="
echo " Cleanup Kafka Deployment"
echo "=========================================="
echo ""

# Delete KafkaRebalance
echo "[1/5] Deleting KafkaRebalance resources..."
kubectl delete kafkarebalance --all -n "$NAMESPACE" --ignore-not-found
echo ""

# Delete KafkaTopics
echo "[2/5] Deleting KafkaTopic resources..."
kubectl delete kafkatopic --all -n "$NAMESPACE" --ignore-not-found
echo ""

# Delete Kafka cluster
echo "[3/5] Deleting Kafka cluster..."
kubectl delete kafka kafka-poc -n "$NAMESPACE" --ignore-not-found
echo ""

# Delete KafkaNodePools
echo "[4/5] Deleting KafkaNodePools..."
kubectl delete kafkanodepool --all -n "$NAMESPACE" --ignore-not-found
echo ""

# Wait for pods to terminate
echo "[5/5] Waiting for pods to terminate..."
kubectl wait --for=delete pod -l strimzi.io/cluster=kafka-poc -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
echo ""

if $REMOVE_ALL; then
    echo "=========================================="
    echo " Removing Strimzi Operator"
    echo "=========================================="
    echo ""

    echo "Deleting Strimzi operator..."
    kubectl delete -f "https://strimzi.io/install/latest?namespace=$NAMESPACE" -n "$NAMESPACE" --ignore-not-found
    echo ""

    echo "Deleting namespace..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found
    echo ""
fi

echo "=========================================="
echo " Cleanup Complete"
echo "=========================================="
echo ""

if $REMOVE_ALL; then
    echo "All Kafka and Strimzi resources have been removed."
else
    echo "Kafka cluster removed. Strimzi operator is still running."
    echo ""
    echo "To also remove the operator, run: ./cleanup.sh --all"
fi
echo ""
