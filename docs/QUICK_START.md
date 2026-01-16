# Quick Start Guide

Get the Kafka rack-aware topic placement PoC running in 5 minutes.

## Prerequisites

- **Docker Desktop 4.x+** with Docker Compose v2
- **8GB RAM** available for Docker
- **Ports 9091-9095** available on localhost

## Step 1: Clone and Navigate

```bash
git clone https://github.com/osodevops/kafka-rack-aware-topic-placement.git
cd kafka-rack-aware-topic-placement
```

## Step 2: Start the Cluster

```bash
./scripts/startup.sh
```

This will:
- Pull the Confluent Kafka Docker image (first run only)
- Start 5 Kafka brokers in KRaft mode
- Wait for all brokers to become healthy
- Display cluster topology

**Expected output:**
```
==========================================
 Kafka Rack-Aware Topic Placement PoC
==========================================

[1/3] Starting 5-broker Kafka cluster...
[2/3] Waiting for brokers to become healthy...
  - kafka-1: healthy
  - kafka-2: healthy
  - kafka-3: healthy
  - kafka-4: healthy
  - kafka-5: healthy

[3/3] Verifying cluster topology...

==========================================
 Cluster is ready!
==========================================
```

## Step 3: Create Topics

```bash
./scripts/create-topics.sh
```

This creates three topics with replicas pinned to brokers 1, 2, 3:
- `poc_orders`
- `poc_payments`
- `poc_inventory`

## Step 4: Validate Placement

```bash
./scripts/validate-placement.sh
```

**Expected output:**
```
==========================================
 Validation Results
==========================================

Topics checked:     3
Partitions checked: 18
Violations found:   0

PASSED: All poc_* topics have replicas only on brokers 1 2 3
```

## Step 5: Explore

### Inspect cluster state
```bash
./scripts/inspect-cluster.sh
```

### Produce a message
```bash
docker exec -it kafka-1 kafka-console-producer \
  --bootstrap-server kafka-1:29092 \
  --topic poc_orders
```

### Consume messages
```bash
docker exec -it kafka-1 kafka-console-consumer \
  --bootstrap-server kafka-1:29092 \
  --topic poc_orders \
  --from-beginning
```

## Step 6: Cleanup

```bash
# Stop cluster (preserves data)
./scripts/teardown.sh

# Stop and remove all data
./scripts/teardown.sh --clean
```

## Next Steps

- Read [ARCHITECTURE.md](ARCHITECTURE.md) for technical details
- Read [OPERATIONS.md](OPERATIONS.md) to learn how to create custom topics
- Read [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if you encounter issues

## Common Issues

| Issue | Solution |
|-------|----------|
| Port already in use | Stop conflicting services or change ports in `docker-compose.yml` |
| Brokers unhealthy | Ensure Docker has 8GB+ RAM allocated |
| Permission denied | Run `chmod +x scripts/*.sh` |
