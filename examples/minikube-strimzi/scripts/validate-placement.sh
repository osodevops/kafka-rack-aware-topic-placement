#!/bin/bash
# =============================================================================
# Topic Placement Validation Script for Strimzi
# =============================================================================
# Validates that poc_* topics have replicas only on POC brokers (100, 101, 102).
#
# Usage:
#   ./validate-placement.sh
# =============================================================================

set -e

NAMESPACE="kafka"
ALLOWED_BROKERS="100 101 102"
TOPIC_PREFIX="poc-"

echo "=========================================="
echo " Validating Topic Placement (Strimzi)"
echo "=========================================="
echo ""
echo "Rule: All $TOPIC_PREFIX* topics must have replicas only on brokers: $ALLOWED_BROKERS"
echo ""

# Get a Kafka broker pod for running commands (select from poc-brokers pool)
KAFKA_POD=$(kubectl get pods -n "$NAMESPACE" -l strimzi.io/cluster=kafka-poc,strimzi.io/pool-name=poc-brokers -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$KAFKA_POD" ]; then
    echo "Error: No Kafka broker pod found"
    echo "Make sure the cluster is deployed: ./deploy.sh"
    exit 1
fi

echo "Using Kafka pod: $KAFKA_POD"
echo ""

# Get list of topics matching prefix
TOPICS=$(kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -- \
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-poc-kafka-bootstrap:9092 --list 2>/dev/null | \
    grep "^$TOPIC_PREFIX" || true)

if [ -z "$TOPICS" ]; then
    echo "No topics found matching prefix '$TOPIC_PREFIX'"
    echo ""
    echo "Create topics with: kubectl apply -f ../topics/poc-topics.yaml -n kafka"
    exit 0
fi

TOPICS_CHECKED=0
PARTITIONS_CHECKED=0
VIOLATIONS=0

# Check each topic
for topic in $TOPICS; do
    echo "Checking topic: $topic"
    TOPICS_CHECKED=$((TOPICS_CHECKED + 1))

    # Get topic description
    DESCRIPTION=$(kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -- \
        /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-poc-kafka-bootstrap:9092 --describe --topic "$topic" 2>/dev/null)

    # Parse partition information
    while IFS= read -r line; do
        if echo "$line" | grep -q "Partition:"; then
            PARTITIONS_CHECKED=$((PARTITIONS_CHECKED + 1))

            # Extract partition number and replicas (using sed for macOS compatibility)
            PARTITION=$(echo "$line" | sed -n 's/.*Partition: *\([0-9]*\).*/\1/p')
            REPLICAS=$(echo "$line" | sed -n 's/.*Replicas: *\([0-9,]*\).*/\1/p')

            # Check each replica
            for replica in $(echo "$REPLICAS" | tr ',' ' '); do
                FOUND=0
                for allowed in $ALLOWED_BROKERS; do
                    if [ "$replica" = "$allowed" ]; then
                        FOUND=1
                        break
                    fi
                done

                if [ $FOUND -eq 0 ]; then
                    echo "  VIOLATION: Partition $PARTITION has replica on broker $replica (not in allowed list)"
                    VIOLATIONS=$((VIOLATIONS + 1))
                fi
            done
        fi
    done <<< "$DESCRIPTION"
done

echo ""
echo "=========================================="
echo " Validation Results"
echo "=========================================="
echo ""
echo "Topics checked:     $TOPICS_CHECKED"
echo "Partitions checked: $PARTITIONS_CHECKED"
echo "Violations found:   $VIOLATIONS"
echo ""

if [ $VIOLATIONS -eq 0 ]; then
    echo "PASSED: All $TOPIC_PREFIX* topics have replicas only on brokers $ALLOWED_BROKERS"
    exit 0
else
    echo "FAILED: Found $VIOLATIONS placement violations"
    echo ""
    echo "To fix, trigger a rebalance: ./trigger-rebalance.sh"
    exit 1
fi
