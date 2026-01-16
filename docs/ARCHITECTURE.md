# Architecture

Technical deep-dive into the Kafka rack-aware topic placement proof-of-concept.

## Overview

This PoC demonstrates controlled topic placement in Apache Kafka using manual replica assignment. It proves that specific topics can be constrained to specific broker subsets, enabling data residency, cost optimization, and compliance requirements.

## Cluster Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kafka Cluster (KRaft Mode)                    │
├─────────────────────────────────┬───────────────────────────────┤
│         Datacenter 1            │        Datacenter 2           │
│        (Rack: "dc1")            │       (Rack: "dc2")           │
├─────────────────────────────────┼───────────────────────────────┤
│                                 │                               │
│  ┌─────────┐    ┌─────────┐    │    ┌─────────┐                │
│  │Broker 1 │    │Broker 2 │    │    │Broker 5 │                │
│  │ :9091   │    │ :9092   │    │    │ :9095   │                │
│  │  ID: 1  │    │  ID: 2  │    │    │  ID: 5  │                │
│  └─────────┘    └─────────┘    │    └─────────┘                │
│                                 │                               │
│  ┌─────────┐    ┌─────────┐    │                               │
│  │Broker 3 │    │Broker 4 │    │                               │
│  │ :9093   │    │ :9094   │    │                               │
│  │  ID: 3  │    │  ID: 4  │    │                               │
│  └─────────┘    └─────────┘    │                               │
│                                 │                               │
└─────────────────────────────────┴───────────────────────────────┘

                         ALLOWED BROKERS
                    ┌─────────────────────┐
 poc_* topics  ───► │  Brokers 1, 2, 3    │ ◄─── Explicit assignment
                    └─────────────────────┘

                         EXCLUDED BROKERS
                    ┌─────────────────────┐
 poc_* topics  ─X─► │  Brokers 4, 5       │ ◄─── Never receive poc_* data
                    └─────────────────────┘
```

## KRaft Mode

This PoC uses **KRaft (Kafka Raft)** mode, which eliminates the ZooKeeper dependency. All 5 brokers run in combined mode, serving as both broker and controller.

### Controller Quorum

```
KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka-1:29093,2@kafka-2:29093,3@kafka-3:29093,4@kafka-4:29093,5@kafka-5:29093
```

All brokers participate in the controller quorum, providing high availability for metadata management.

### Listener Configuration

Each broker exposes three listeners:

| Listener | Port | Purpose |
|----------|------|---------|
| `CONTROLLER` | 29093 | KRaft consensus between controllers |
| `PLAINTEXT` | 29092 | Inter-broker communication |
| `EXTERNAL` | 909X | Client connections from host |

## Replica Assignment Strategy

### Manual Assignment Format

The `--replica-assignment` flag uses a specific format:

```
partition0_replicas,partition1_replicas,partition2_replicas,...
```

Each partition's replicas are colon-separated broker IDs:

```
1:2:3,2:3:1,3:1:2,1:2:3,2:3:1,3:1:2
└─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘
  │     │     │     │     │     └── Partition 5: leader=3, replicas=[3,1,2]
  │     │     │     │     └──────── Partition 4: leader=2, replicas=[2,3,1]
  │     │     │     └────────────── Partition 3: leader=1, replicas=[1,2,3]
  │     │     └──────────────────── Partition 2: leader=3, replicas=[3,1,2]
  │     └────────────────────────── Partition 1: leader=2, replicas=[2,3,1]
  └──────────────────────────────── Partition 0: leader=1, replicas=[1,2,3]
```

### Leadership Distribution

The assignment rotates the first broker ID to distribute leadership evenly:
- Partitions 0, 3: Leader = Broker 1
- Partitions 1, 4: Leader = Broker 2
- Partitions 2, 5: Leader = Broker 3

This prevents any single broker from becoming a bottleneck.

## Data Flow

```
                    ┌──────────────────┐
                    │    Producer      │
                    └────────┬─────────┘
                             │
                             ▼
              ┌──────────────────────────┐
              │     Bootstrap Servers    │
              │  localhost:9091-9095     │
              └──────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌─────────┐        ┌─────────┐        ┌─────────┐
    │Broker 1 │        │Broker 2 │        │Broker 3 │
    │ Leader  │◄──────►│ Follower│◄──────►│ Follower│
    │  P0,P3  │        │  P1,P4  │        │  P2,P5  │
    └─────────┘        └─────────┘        └─────────┘
         │                   │                   │
         └───────────────────┴───────────────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │    Consumer      │
                    └──────────────────┘
```

## Why Not Use Rack-Aware Auto-Assignment?

Kafka's built-in rack awareness (`broker.rack`) distributes replicas across different racks for fault tolerance, but it doesn't:

1. **Restrict topics to specific broker subsets** - All brokers are candidates
2. **Guarantee placement** - Kafka makes best-effort decisions
3. **Support complex policies** - No way to express "only these brokers"

Manual replica assignment provides **deterministic control** over exactly which brokers host each partition.

## Configuration Reference

### Broker Environment Variables

| Variable | Description |
|----------|-------------|
| `KAFKA_NODE_ID` | Unique broker identifier (1-5) |
| `KAFKA_BROKER_RACK` | Rack identifier for topology awareness |
| `KAFKA_PROCESS_ROLES` | `broker,controller` for combined mode |
| `KAFKA_LISTENERS` | Protocol bindings for each listener type |
| `KAFKA_ADVERTISED_LISTENERS` | Addresses clients use to connect |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | List of controller nodes |
| `CLUSTER_ID` | Unique cluster identifier (must match all brokers) |

### Topic Defaults

| Setting | Value | Reason |
|---------|-------|--------|
| Partitions | 6 | Enough to demonstrate distribution |
| Replication Factor | 3 | Standard production setting |
| Min ISR | 2 | Fault tolerance with ack=all |

## Docker Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    kafka-network (bridge)                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  kafka-1 ──────────────────────────────────────── :29092    │
│     │                                                       │
│  kafka-2 ──────────────────────────────────────── :29092    │
│     │                                                       │
│  kafka-3 ──────────────────────────────────────── :29092    │
│     │                                                       │
│  kafka-4 ──────────────────────────────────────── :29092    │
│     │                                                       │
│  kafka-5 ──────────────────────────────────────── :29092    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Port mapping
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Host                                 │
├─────────────────────────────────────────────────────────────┤
│  localhost:9091 ──► kafka-1:9091                            │
│  localhost:9092 ──► kafka-2:9092                            │
│  localhost:9093 ──► kafka-3:9093                            │
│  localhost:9094 ──► kafka-4:9094                            │
│  localhost:9095 ──► kafka-5:9095                            │
└─────────────────────────────────────────────────────────────┘
```

## Validation Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Validation Pipeline                        │
└─────────────────────────────────────────────────────────────┘

     ┌─────────────┐         ┌─────────────┐
     │   Shell     │         │   Python    │
     │  Validator  │         │  Validator  │
     └──────┬──────┘         └──────┬──────┘
            │                       │
            ▼                       ▼
     ┌─────────────┐         ┌─────────────┐
     │kafka-topics │         │ AdminClient │
     │  --describe │         │   API       │
     └──────┬──────┘         └──────┬──────┘
            │                       │
            └───────────┬───────────┘
                        │
                        ▼
              ┌─────────────────┐
              │ Topic Metadata  │
              │   (Partitions,  │
              │    Replicas,    │
              │    Leaders)     │
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ Check: replicas │
              │ ⊆ {1, 2, 3}     │
              └────────┬────────┘
                       │
            ┌──────────┴──────────┐
            │                     │
            ▼                     ▼
     ┌─────────────┐       ┌─────────────┐
     │   PASSED    │       │   FAILED    │
     │  (exit 0)   │       │  (exit 1)   │
     └─────────────┘       └─────────────┘
```

## Future Considerations

This PoC demonstrates the core concept. Production implementations might add:

1. **Admission Control** - Webhook to reject topics violating placement policies
2. **Continuous Monitoring** - Prometheus metrics for placement compliance
3. **Auto-Remediation** - Automatic reassignment when violations detected
4. **Policy Engine** - DSL for expressing complex placement rules
5. **Multi-Cluster** - Cross-cluster replication with placement constraints
