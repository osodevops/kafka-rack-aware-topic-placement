#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Allowed brokers for poc_* topics
ALLOWED_BROKERS="1 2 3"

echo "=========================================="
echo " Validating poc_* Topic Placement"
echo "=========================================="
echo ""
echo "Rule: All poc_* topics must have replicas only on brokers: $ALLOWED_BROKERS"
echo ""

# Get all topics matching poc_*
POC_TOPICS=$(docker exec kafka-1 kafka-topics \
    --bootstrap-server kafka-1:29092 \
    --list 2>/dev/null | grep "^poc_" || true)

if [ -z "$POC_TOPICS" ]; then
    echo "No poc_* topics found."
    echo "Run ./scripts/create-topics.sh first."
    exit 0
fi

VIOLATIONS=0
TOTAL_PARTITIONS=0

for topic in $POC_TOPICS; do
    echo "Checking topic: $topic"

    # Get partition details
    DESCRIBE_OUTPUT=$(docker exec kafka-1 kafka-topics \
        --bootstrap-server kafka-1:29092 \
        --describe \
        --topic "$topic" 2>/dev/null)

    # Parse each partition line
    while IFS= read -r line; do
        if echo "$line" | grep -q "Partition:"; then
            TOTAL_PARTITIONS=$((TOTAL_PARTITIONS + 1))

            # Extract partition number and replicas
            PARTITION=$(echo "$line" | sed -n 's/.*Partition: *\([0-9]*\).*/\1/p')
            REPLICAS=$(echo "$line" | sed -n 's/.*Replicas: *\([0-9,]*\).*/\1/p')

            # Check each replica broker
            for broker in $(echo "$REPLICAS" | tr ',' ' '); do
                VALID=false
                for allowed in $ALLOWED_BROKERS; do
                    if [ "$broker" = "$allowed" ]; then
                        VALID=true
                        break
                    fi
                done

                if [ "$VALID" = false ]; then
                    echo "  VIOLATION: Partition $PARTITION has replica on broker $broker"
                    VIOLATIONS=$((VIOLATIONS + 1))
                fi
            done
        fi
    done <<< "$DESCRIBE_OUTPUT"
done

echo ""
echo "=========================================="
echo " Validation Results"
echo "=========================================="
echo ""
echo "Topics checked:     $(echo "$POC_TOPICS" | wc -w | tr -d ' ')"
echo "Partitions checked: $TOTAL_PARTITIONS"
echo "Violations found:   $VIOLATIONS"
echo ""

if [ $VIOLATIONS -eq 0 ]; then
    echo "PASSED: All poc_* topics have replicas only on brokers $ALLOWED_BROKERS"
    exit 0
else
    echo "FAILED: Found $VIOLATIONS placement violations"
    exit 1
fi
