#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Allowed brokers for poc_* topics (DC1 subset)
ALLOWED_BROKERS="1,2,3"

# Replica assignment for 6 partitions with RF=3 on brokers 1,2,3
# Format: partition0_replicas,partition1_replicas,...
# Each partition's replicas are colon-separated broker IDs
# Leadership is distributed: 1->2->3->1->2->3
REPLICA_ASSIGNMENT="1:2:3,2:3:1,3:1:2,1:2:3,2:3:1,3:1:2"

echo "=========================================="
echo " Creating poc_* Topics"
echo "=========================================="
echo ""
echo "Target brokers: $ALLOWED_BROKERS (DC1 only)"
echo "Partitions: 6, Replication Factor: 3"
echo ""

# Topics to create
TOPICS="poc_orders poc_payments poc_inventory"

for topic in $TOPICS; do
    echo "Creating topic: $topic"

    # Check if topic already exists
    if docker exec kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-1:9092 --list 2>/dev/null | grep -q "^${topic}$"; then
        echo "  - Topic already exists, skipping"
        continue
    fi

    docker exec kafka-1 /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server kafka-1:9092 \
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
    docker exec kafka-1 /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server kafka-1:9092 \
        --describe \
        --topic "$topic" | grep -E "Topic:|Partition:" | head -7
    echo ""
done

echo "=========================================="
echo " Topics Created Successfully"
echo "=========================================="
echo ""
echo "All poc_* topics are assigned to brokers 1, 2, 3 only."
echo ""
echo "Next steps:"
echo "  ./scripts/validate-placement.sh  - Verify placement rules"
echo "  ./scripts/inspect-cluster.sh     - View full cluster state"
echo ""
