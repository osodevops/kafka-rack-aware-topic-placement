#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=========================================="
echo " Kafka Rack-Aware Topic Placement PoC"
echo "=========================================="
echo ""

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker Desktop and try again."
    exit 1
fi

echo "[1/3] Starting 5-broker Kafka cluster..."
docker compose up -d

echo ""
echo "[2/3] Waiting for brokers to become healthy..."
echo "      This may take 30-60 seconds on first run..."
echo ""

# Wait for all brokers to be healthy
BROKERS="kafka-1 kafka-2 kafka-3 kafka-4 kafka-5"
MAX_RETRIES=30
RETRY_INTERVAL=5

for broker in $BROKERS; do
    retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$broker" 2>/dev/null || echo "not_found")

        if [ "$status" = "healthy" ]; then
            echo "  - $broker: healthy"
            break
        fi

        if [ "$status" = "not_found" ]; then
            echo "  - $broker: waiting for container..."
        else
            echo "  - $broker: $status (attempt $((retries + 1))/$MAX_RETRIES)"
        fi

        retries=$((retries + 1))
        sleep $RETRY_INTERVAL
    done

    if [ $retries -eq $MAX_RETRIES ]; then
        echo ""
        echo "Error: $broker failed to become healthy after $MAX_RETRIES attempts"
        echo "Check logs with: docker logs $broker"
        exit 1
    fi
done

echo ""
echo "[3/3] Verifying cluster topology..."
echo ""

# Show broker information
docker exec kafka-1 kafka-metadata --snapshot /tmp/kraft-combined-logs/__cluster_metadata-0/00000000000000000000.log --command "broker" 2>/dev/null || true

echo ""
echo "=========================================="
echo " Cluster is ready!"
echo "=========================================="
echo ""
echo "Topology:"
echo "  DC1 (rack: dc1): Brokers 1, 2, 3, 4"
echo "  DC2 (rack: dc2): Broker 5"
echo ""
echo "Bootstrap servers:"
echo "  localhost:9091 (broker-1)"
echo "  localhost:9092 (broker-2)"
echo "  localhost:9093 (broker-3)"
echo "  localhost:9094 (broker-4)"
echo "  localhost:9095 (broker-5)"
echo ""
echo "Next steps:"
echo "  ./scripts/create-topics.sh    - Create poc_* topics"
echo "  ./scripts/inspect-cluster.sh  - View cluster state"
echo ""
