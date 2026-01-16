# Operations Guide

How to create, modify, and monitor topics with rack-aware placement.

## Creating Topics with Custom Placement

### Understanding Replica Assignment

The `--replica-assignment` flag specifies exactly which brokers host each partition's replicas.

**Format:** `partition0,partition1,partition2,...`

Each partition is a colon-separated list of broker IDs: `leader:follower1:follower2`

### Example: Create a Topic on Brokers 1, 2, 3

```bash
# 4 partitions, RF=3, all on brokers 1,2,3
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --create \
  --topic my_constrained_topic \
  --replica-assignment 1:2:3,2:3:1,3:1:2,1:2:3
```

### Example: Create a Topic on Brokers 4, 5 Only

```bash
# 3 partitions, RF=2, only on brokers 4,5 (DC2)
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --create \
  --topic dc2_only_topic \
  --replica-assignment 4:5,5:4,4:5
```

### Example: Spread Across All Brokers

```bash
# 5 partitions, RF=3, spread across all 5 brokers
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --create \
  --topic distributed_topic \
  --replica-assignment 1:2:3,2:3:4,3:4:5,4:5:1,5:1:2
```

## Generating Replica Assignments

### Using the Assignment Pattern

For N partitions with replication factor R on brokers B1, B2, B3:

```bash
# Pattern generator (bash)
BROKERS=(1 2 3)
PARTITIONS=6
RF=3

for ((p=0; p<PARTITIONS; p++)); do
  start=$((p % ${#BROKERS[@]}))
  assignment=""
  for ((r=0; r<RF; r++)); do
    idx=$(((start + r) % ${#BROKERS[@]}))
    assignment+="${BROKERS[$idx]}"
    if [ $r -lt $((RF-1)) ]; then
      assignment+=":"
    fi
  done
  echo "Partition $p: $assignment"
done
```

### Python Helper

```python
def generate_assignment(brokers: list, partitions: int, rf: int) -> str:
    """Generate replica assignment string for kafka-topics CLI."""
    assignments = []
    for p in range(partitions):
        start = p % len(brokers)
        replicas = [str(brokers[(start + r) % len(brokers)]) for r in range(rf)]
        assignments.append(":".join(replicas))
    return ",".join(assignments)

# Example: 6 partitions, RF=3, on brokers 1,2,3
print(generate_assignment([1, 2, 3], 6, 3))
# Output: 1:2:3,2:3:1,3:1:2,1:2:3,2:3:1,3:1:2
```

## Reassigning Existing Topics

### Step 1: Get Current Assignment

```bash
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --describe \
  --topic my_topic
```

### Step 2: Create Reassignment JSON

```json
{
  "version": 1,
  "partitions": [
    {"topic": "my_topic", "partition": 0, "replicas": [1, 2, 3]},
    {"topic": "my_topic", "partition": 1, "replicas": [2, 3, 1]},
    {"topic": "my_topic", "partition": 2, "replicas": [3, 1, 2]}
  ]
}
```

Save as `reassignment.json`.

### Step 3: Execute Reassignment

```bash
# Copy JSON to container
docker cp reassignment.json kafka-1:/tmp/

# Execute
docker exec kafka-1 kafka-reassign-partitions \
  --bootstrap-server kafka-1:29092 \
  --reassignment-json-file /tmp/reassignment.json \
  --execute
```

### Step 4: Monitor Progress

```bash
docker exec kafka-1 kafka-reassign-partitions \
  --bootstrap-server kafka-1:29092 \
  --reassignment-json-file /tmp/reassignment.json \
  --verify
```

## Monitoring Topic Placement

### List All Topics

```bash
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --list
```

### Describe a Topic

```bash
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --describe \
  --topic poc_orders
```

**Output:**
```
Topic: poc_orders	TopicId: abc123	PartitionCount: 6	ReplicationFactor: 3
	Topic: poc_orders	Partition: 0	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_orders	Partition: 1	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_orders	Partition: 2	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2
	...
```

### Check All poc_* Topics

```bash
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --describe \
  --topic 'poc_.*'
```

### Use Python Validator

```bash
# Detailed report
python python/topic_validator.py

# Quick pass/fail
python python/topic_validator.py --quiet

# Custom broker set
python python/topic_validator.py --allowed-brokers 4,5

# Different prefix
python python/topic_validator.py --prefix "prod_"
```

## Inspecting Broker State

### View Broker Metadata

```bash
docker exec kafka-1 kafka-broker-api-versions \
  --bootstrap-server kafka-1:29092
```

### Check Cluster Metadata (KRaft)

```bash
docker exec kafka-1 kafka-metadata \
  --snapshot /tmp/kraft-combined-logs/__cluster_metadata-0/00000000000000000000.log \
  --command "broker"
```

### View Consumer Groups

```bash
docker exec kafka-1 kafka-consumer-groups \
  --bootstrap-server kafka-1:29092 \
  --list
```

## Producing and Consuming

### Console Producer

```bash
docker exec -it kafka-1 kafka-console-producer \
  --bootstrap-server kafka-1:29092 \
  --topic poc_orders
```

### Console Consumer

```bash
# From beginning
docker exec -it kafka-1 kafka-console-consumer \
  --bootstrap-server kafka-1:29092 \
  --topic poc_orders \
  --from-beginning

# With consumer group
docker exec -it kafka-1 kafka-console-consumer \
  --bootstrap-server kafka-1:29092 \
  --topic poc_orders \
  --group my-consumer-group
```

### Produce with Key

```bash
docker exec -it kafka-1 kafka-console-producer \
  --bootstrap-server kafka-1:29092 \
  --topic poc_orders \
  --property "parse.key=true" \
  --property "key.separator=:"
```

Then enter: `key1:value1`

## Deleting Topics

```bash
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --delete \
  --topic my_topic
```

## Modifying Topic Configuration

### Add Partitions

```bash
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --alter \
  --topic my_topic \
  --partitions 12
```

**Note:** New partitions won't automatically follow the same placement constraints. Use `kafka-reassign-partitions` to assign them to specific brokers.

### Change Topic Config

```bash
docker exec kafka-1 kafka-configs \
  --bootstrap-server kafka-1:29092 \
  --entity-type topics \
  --entity-name poc_orders \
  --alter \
  --add-config retention.ms=604800000
```

## Best Practices

1. **Always validate after changes** - Run `validate-placement.sh` after any topic modification

2. **Document placement policies** - Keep a record of which topics should be on which brokers

3. **Use consistent naming** - Prefix topics by their placement policy (e.g., `dc1_`, `dc2_`)

4. **Monitor ISR** - Ensure all replicas are in-sync before considering placement complete

5. **Test failover** - Verify topics remain accessible when individual brokers fail
