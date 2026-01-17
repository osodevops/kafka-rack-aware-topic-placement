#!/bin/bash
# =============================================================================
# Topic Creation Script for Strimzi
# =============================================================================
# Creates poc_* topics with explicit replica assignments to POC brokers.
#
# Usage:
#   ./create-topics.sh
# =============================================================================

set -e

NAMESPACE="kafka"

# POC Broker IDs (from KafkaNodePool configuration)
POC_BROKERS="100:101:102"

# Replica assignment for 6 partitions with RF=3 on POC brokers
# Leadership is distributed: 100->101->102->100->101->102
REPLICA_ASSIGNMENT="100:101:102,101:102:100,102:100:101,100:101:102,101:102:100,102:100:101"

# Topics to create
TOPICS="poc-orders poc-payments poc-inventory"

echo "=========================================="
echo " Creating POC Topics (Strimzi)"
echo "=========================================="
echo ""
echo "Target brokers: 100, 101, 102 (POC Broker Pool)"
echo "Partitions: 6, Replication Factor: 3"
echo ""

# Get a Kafka broker pod for running commands
KAFKA_POD=$(kubectl get pods -n "$NAMESPACE" -l strimzi.io/cluster=kafka-poc,strimzi.io/pool-name=poc-brokers -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$KAFKA_POD" ]; then
    echo "Error: No Kafka broker pod found"
    echo "Make sure the cluster is deployed: ./deploy.sh"
    exit 1
fi

echo "Using Kafka pod: $KAFKA_POD"
echo ""

for topic in $TOPICS; do
    echo "Creating topic: $topic"

    # Check if topic already exists
    if kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -- \
        /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-poc-kafka-bootstrap:9092 --list 2>/dev/null | grep -q "^${topic}$"; then
        echo "  - Topic already exists, skipping"
        continue
    fi

    kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -- \
        /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server kafka-poc-kafka-bootstrap:9092 \
        --create \
        --topic "$topic" \
        --replica-assignment "$REPLICA_ASSIGNMENT"

    echo "  - Created successfully"
done

echo ""
echo "=========================================="
echo " Verifying Topic Placement"
echo "=========================================="
echo ""

for topic in $TOPICS; do
    echo "Topic: $topic"
    kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -- \
        /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server kafka-poc-kafka-bootstrap:9092 \
        --describe \
        --topic "$topic" | grep -E "Topic:|Partition:" | head -7
    echo ""
done

echo "=========================================="
echo " Topics Created Successfully"
echo "=========================================="
echo ""
echo "All poc-* topics are assigned to brokers 100, 101, 102 only."
echo ""
echo "Next steps:"
echo "  ./validate-placement.sh  - Verify placement rules"
echo "  ./trigger-rebalance.sh   - Use Cruise Control for rebalancing"
echo ""
