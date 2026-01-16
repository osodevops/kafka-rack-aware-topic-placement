#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

CLEAN_VOLUMES=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --clean) CLEAN_VOLUMES=true ;;
        -h|--help)
            echo "Usage: $0 [--clean]"
            echo ""
            echo "Options:"
            echo "  --clean    Remove volumes (deletes all Kafka data)"
            echo "  -h, --help Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
    shift
done

echo "=========================================="
echo " Stopping Kafka Cluster"
echo "=========================================="
echo ""

echo "[1/2] Stopping containers..."
docker compose down

if [ "$CLEAN_VOLUMES" = true ]; then
    echo ""
    echo "[2/2] Removing volumes..."
    docker volume rm kafka-rack-aware-topic-placement_kafka-1-data 2>/dev/null || true
    docker volume rm kafka-rack-aware-topic-placement_kafka-2-data 2>/dev/null || true
    docker volume rm kafka-rack-aware-topic-placement_kafka-3-data 2>/dev/null || true
    docker volume rm kafka-rack-aware-topic-placement_kafka-4-data 2>/dev/null || true
    docker volume rm kafka-rack-aware-topic-placement_kafka-5-data 2>/dev/null || true
    echo "  Volumes removed."
else
    echo ""
    echo "[2/2] Volumes preserved (use --clean to remove)"
fi

echo ""
echo "=========================================="
echo " Cluster stopped"
echo "=========================================="
echo ""
echo "To restart: ./scripts/startup.sh"
echo ""
