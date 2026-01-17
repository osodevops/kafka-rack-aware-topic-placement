# Docker Compose Example: Kafka Rack-Aware Topic Placement

This example demonstrates rack-aware topic placement using a 5-broker Kafka cluster with KRaft mode and manual replica assignment.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Docker Compose Cluster                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     Kafka Cluster (KRaft)                │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │              POC Broker Set (dc1)                 │   │   │
│  │  │  Broker 1 (:9091)  Broker 2 (:9092)  Broker 3    │   │   │
│  │  │                                       (:9093)     │   │   │
│  │  │  Topics: poc_orders, poc_payments, poc_inventory  │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │           General Broker Set                      │   │   │
│  │  │  Broker 4 (:9094, dc1)    Broker 5 (:9095, dc2)  │   │   │
│  │  │  Topics: general-purpose workloads               │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Docker Desktop 4.x+ (with Docker Compose v2)
- 8GB RAM minimum available for Docker
- Ports available: 9091-9095

## Quick Start

```bash
# 1. Start the cluster (5 brokers in KRaft mode)
./scripts/startup.sh

# 2. Create sample topics with controlled placement
./scripts/create-topics.sh

# 3. Validate topic placement
./scripts/validate-placement.sh

# 4. Inspect cluster state
./scripts/inspect-cluster.sh

# 5. Stop the cluster
./scripts/teardown.sh
```

## Broker Sets Configuration

Topics are placed on specific broker subsets using manual replica assignment:

| Broker Set | Broker IDs | Rack | Purpose |
|------------|------------|------|---------|
| `poc-brokers` | 1, 2, 3 | dc1 | Topics matching `poc_*` pattern |
| `general-brokers` | 4, 5 | dc1, dc2 | All other topics |

## Topic Placement

Topics prefixed with `poc_` are created with explicit replica assignment to ensure all replicas reside only on brokers 1, 2, 3:

```bash
# Replica assignment format: partition0:replicas,partition1:replicas,...
--replica-assignment 1:2:3,2:3:1,3:1:2,1:2:3,2:3:1,3:1:2
```

This ensures:
- 6 partitions per topic
- Replication factor of 3
- All replicas on brokers 1, 2, 3 only
- Leadership evenly distributed

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/startup.sh` | Start the cluster and wait for all brokers to be healthy |
| `scripts/create-topics.sh` | Create `poc_*` topics with controlled placement |
| `scripts/validate-placement.sh` | Verify topics are on correct brokers |
| `scripts/inspect-cluster.sh` | Display cluster topology and topic info |
| `scripts/teardown.sh` | Stop the cluster (use `--clean` to remove data) |

## Configuration

| File | Description |
|------|-------------|
| `docker-compose.yml` | Container definitions for 5-broker Kafka cluster |

## Validating Placement

After creating topics, verify placement rules are enforced:

```bash
$ ./scripts/validate-placement.sh

==========================================
 Validating poc_* Topic Placement
==========================================

Rule: All poc_* topics must have replicas only on brokers: 1 2 3

Checking topic: poc_orders
Checking topic: poc_payments
Checking topic: poc_inventory

==========================================
 Validation Results
==========================================

Topics checked:     3
Partitions checked: 18
Violations found:   0

PASSED: All poc_* topics have replicas only on brokers 1 2 3
```

## Broker Distribution

After creating topics, you can inspect the broker distribution:

```bash
$ ./scripts/inspect-cluster.sh

=== Broker Distribution Summary ===

Broker | Partitions as Leader | Partitions as Replica
-------|---------------------|----------------------
   1   |          6          |          18
   2   |          6          |          18
   3   |          6          |          18
   4   |          0          |          0
   5   |          0          |          0
```

This confirms that all POC topic partitions are exclusively on brokers 1, 2, 3.

## Troubleshooting

### Brokers not starting

Check Docker resources and logs:

```bash
# Check broker logs
docker logs kafka-1

# Verify containers are running
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### Port conflicts

If ports are in use, modify `docker-compose.yml`:

```yaml
ports:
  - "19091:9091"  # Change external port
```

## Resource Requirements

| Component | CPU | Memory |
|-----------|-----|--------|
| Each Kafka Broker | 0.5 core | 1.5GB |
| **Total** | 2.5 cores | 7.5GB |
