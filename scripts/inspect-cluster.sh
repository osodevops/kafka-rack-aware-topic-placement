#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=========================================="
echo " Kafka Cluster Inspection"
echo "=========================================="
echo ""

# Check if cluster is running
if ! docker ps --format '{{.Names}}' | grep -q "kafka-1"; then
    echo "Error: Cluster is not running."
    echo "Start it with: ./scripts/startup.sh"
    exit 1
fi

echo "=== Container Status ==="
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|kafka-"
echo ""

echo "=== Broker Topology ==="
echo ""
echo "Broker ID | Rack | External Port | Status"
echo "----------|------|---------------|-------"
for i in 1 2 3 4 5; do
    if [ $i -le 4 ]; then
        rack="dc1"
    else
        rack="dc2"
    fi
    port="909$i"
    status=$(docker inspect --format='{{.State.Health.Status}}' "kafka-$i" 2>/dev/null || echo "unknown")
    printf "    %d     | %s |     %s      | %s\n" "$i" "$rack" "$port" "$status"
done
echo ""

echo "=== Topics ==="
echo ""
docker exec kafka-1 kafka-topics \
    --bootstrap-server kafka-1:29092 \
    --list 2>/dev/null | grep -v "^__" | sort || echo "(no user topics)"
echo ""

echo "=== poc_* Topic Details ==="
echo ""

POC_TOPICS=$(docker exec kafka-1 kafka-topics \
    --bootstrap-server kafka-1:29092 \
    --list 2>/dev/null | grep "^poc_" || true)

if [ -z "$POC_TOPICS" ]; then
    echo "(no poc_* topics found)"
else
    for topic in $POC_TOPICS; do
        echo "--- $topic ---"
        docker exec kafka-1 kafka-topics \
            --bootstrap-server kafka-1:29092 \
            --describe \
            --topic "$topic" 2>/dev/null | grep -E "Topic:|Partition:"
        echo ""
    done
fi

echo "=== Broker Distribution Summary ==="
echo ""

if [ -n "$POC_TOPICS" ]; then
    echo "Broker | Partitions as Leader | Partitions as Replica"
    echo "-------|---------------------|----------------------"

    for broker_id in 1 2 3 4 5; do
        leader_count=0
        replica_count=0

        for topic in $POC_TOPICS; do
            # Count leadership
            leaders=$(docker exec kafka-1 kafka-topics \
                --bootstrap-server kafka-1:29092 \
                --describe \
                --topic "$topic" 2>/dev/null | grep "Leader: $broker_id" | wc -l)
            leader_count=$((leader_count + leaders))

            # Count replica membership
            replicas=$(docker exec kafka-1 kafka-topics \
                --bootstrap-server kafka-1:29092 \
                --describe \
                --topic "$topic" 2>/dev/null | grep -E "Replicas:.*\b$broker_id\b" | wc -l)
            replica_count=$((replica_count + replicas))
        done

        printf "   %d   |          %d          |          %d\n" "$broker_id" "$leader_count" "$replica_count"
    done
else
    echo "(create poc_* topics first to see distribution)"
fi

echo ""
echo "=========================================="
