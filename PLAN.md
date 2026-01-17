# Implementation Plan: Multi-Environment Kafka Topic Placement with Cruise Control

## Overview

This plan reorganizes the repository to demonstrate **Cruise Control's BrokerSetAwareGoal** for enforcing topic placement on specific broker subsets. The PoC will include two deployment options:

1. **Docker Compose** - Local development with Cruise Control
2. **Minikube + Strimzi** - Production-like Kubernetes deployment with KRaft mode, 5 dedicated brokers + 5 dedicated controllers

---

## Key Feature: Cruise Control BrokerSetAwareGoal

From [linkedin/cruise-control#1782](https://github.com/linkedin/cruise-control/issues/1782) and PR #1809:

The `BrokerSetAwareGoal` is a **hard goal** that enforces replicas of specific topics to remain within designated broker subsets. This provides:

- **Automatic enforcement** - Unlike manual `--replica-assignment`, Cruise Control continuously ensures topics stay on their designated brokers
- **Self-healing** - If a topic is misconfigured, Cruise Control will propose/execute a rebalance to fix it
- **Scalable** - Works with partition reassignment at scale

### Configuration Requirements

```properties
# cruisecontrol.properties
broker.set.resolver.class=com.linkedin.kafka.cruisecontrol.config.BrokerSetFileResolver
broker.set.config.file=/path/to/broker-sets.json

# Add BrokerSetAwareGoal to hard goals
hard.goals=com.linkedin.kafka.cruisecontrol.analyzer.goals.BrokerSetAwareGoal,...
default.goals=com.linkedin.kafka.cruisecontrol.analyzer.goals.BrokerSetAwareGoal,...
```

### Broker Sets Configuration (broker-sets.json)

```json
{
  "brokerSets": {
    "poc-brokers": [1, 2, 3],
    "general-brokers": [4, 5]
  },
  "topicToBrokerSet": {
    "poc_.*": "poc-brokers"
  }
}
```

---

## Proposed Repository Structure

```
kafka-rack-aware-topic-placement/
├── README.md                    # Updated overview pointing to examples
├── docs/                        # Existing docs (keep)
│   ├── ARCHITECTURE.md
│   ├── OPERATIONS.md
│   ├── QUICK_START.md
│   └── TROUBLESHOOTING.md
├── python/                      # Existing validation tool (keep)
│   ├── topic_validator.py
│   └── requirements.txt
│
├── examples/
│   ├── docker-compose/          # Docker Compose example
│   │   ├── README.md
│   │   ├── docker-compose.yml   # 5 brokers + Cruise Control
│   │   ├── config/
│   │   │   ├── cruisecontrol.properties
│   │   │   ├── broker-sets.json
│   │   │   └── capacity.json
│   │   └── scripts/
│   │       ├── startup.sh
│   │       ├── create-topics.sh
│   │       ├── validate-placement.sh
│   │       ├── trigger-rebalance.sh  # New: trigger CC rebalance
│   │       ├── inspect-cluster.sh
│   │       └── teardown.sh
│   │
│   └── minikube-strimzi/        # Minikube + Strimzi example
│       ├── README.md
│       ├── setup/
│       │   ├── 00-namespace.yaml
│       │   ├── 01-strimzi-operator.yaml
│       │   └── install.sh
│       ├── kafka/
│       │   ├── kafka-cluster.yaml           # Kafka CR with Cruise Control
│       │   ├── kafka-nodepool-controllers.yaml  # 5 controllers
│       │   ├── kafka-nodepool-poc-brokers.yaml  # 3 brokers for poc_* topics
│       │   ├── kafka-nodepool-general-brokers.yaml  # 2 general brokers
│       │   └── cruise-control-config.yaml   # ConfigMap for broker sets
│       ├── topics/
│       │   ├── poc-topics.yaml              # KafkaTopic CRs
│       │   └── kafka-rebalance.yaml         # KafkaRebalance CR
│       └── scripts/
│           ├── deploy.sh
│           ├── validate-placement.sh
│           ├── trigger-rebalance.sh
│           └── cleanup.sh
│
├── .github/workflows/
│   ├── ci.yml                   # Existing (update paths)
│   └── integration-test-docker.yml   # Docker Compose tests
│
└── pyproject.toml               # Existing (keep)
```

---

## Phase 1: Docker Compose Example with Cruise Control

### 1.1 Docker Compose Configuration

**File: `examples/docker-compose/docker-compose.yml`**

Components:
- 5 Kafka brokers (KRaft mode, combined broker+controller)
- 1 Cruise Control container
- Shared config volume

Key changes from current setup:
- Add Cruise Control container
- Mount broker-sets.json and cruisecontrol.properties
- Configure JMX for Cruise Control metrics collection

### 1.2 Cruise Control Configuration

**File: `examples/docker-compose/config/cruisecontrol.properties`**

```properties
# Kafka cluster
bootstrap.servers=kafka-1:29092,kafka-2:29092,kafka-3:29092,kafka-4:29092,kafka-5:29092

# Broker Set Aware Goal configuration
broker.set.resolver.class=com.linkedin.kafka.cruisecontrol.config.BrokerSetFileResolver
broker.set.config.file=/etc/cruise-control/broker-sets.json

# Goals - BrokerSetAwareGoal as hard goal
hard.goals=com.linkedin.kafka.cruisecontrol.analyzer.goals.BrokerSetAwareGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.RackAwareGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.ReplicaCapacityGoal

default.goals=com.linkedin.kafka.cruisecontrol.analyzer.goals.BrokerSetAwareGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.RackAwareGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.ReplicaCapacityGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.DiskCapacityGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.NetworkInboundCapacityGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.NetworkOutboundCapacityGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.ReplicaDistributionGoal,\
  com.linkedin.kafka.cruisecontrol.analyzer.goals.LeaderBytesInDistributionGoal

# Capacity
capacity.config.file=/etc/cruise-control/capacity.json

# Self-healing
anomaly.detection.interval.ms=60000
self.healing.enabled=true
```

**File: `examples/docker-compose/config/broker-sets.json`**

```json
{
  "brokerSets": {
    "poc-brokers": {
      "brokerIds": [1, 2, 3],
      "description": "Brokers designated for poc_* topics with data residency requirements"
    },
    "general-brokers": {
      "brokerIds": [4, 5],
      "description": "Brokers for general-purpose topics"
    }
  },
  "topicToBrokerSet": {
    "poc_.*": "poc-brokers"
  }
}
```

### 1.3 New Scripts

**`trigger-rebalance.sh`** - Demonstrate Cruise Control enforcement:
1. Create a topic incorrectly (on wrong brokers)
2. Trigger Cruise Control rebalance
3. Show topic moved to correct broker set

---

## Phase 2: Minikube + Strimzi Example

### 2.1 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Minikube Cluster                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Strimzi Kafka Cluster                   │   │
│  │                                                          │   │
│  │  ┌──────────────────────┐  ┌──────────────────────┐     │   │
│  │  │   Controller Pool    │  │   Cruise Control     │     │   │
│  │  │   (5 controllers)    │  │                      │     │   │
│  │  │   IDs: 0, 1, 2, 3, 4 │  │  BrokerSetAwareGoal  │     │   │
│  │  └──────────────────────┘  └──────────────────────┘     │   │
│  │                                                          │   │
│  │  ┌──────────────────────┐  ┌──────────────────────┐     │   │
│  │  │   POC Broker Pool    │  │  General Broker Pool │     │   │
│  │  │   (3 brokers)        │  │  (2 brokers)         │     │   │
│  │  │   IDs: 100, 101, 102 │  │  IDs: 200, 201       │     │   │
│  │  │                      │  │                      │     │   │
│  │  │   Topics: poc_*      │  │   Topics: other      │     │   │
│  │  └──────────────────────┘  └──────────────────────┘     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 KafkaNodePool Configurations

**File: `examples/minikube-strimzi/kafka/kafka-nodepool-controllers.yaml`**

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: controllers
  labels:
    strimzi.io/cluster: kafka-poc
  annotations:
    strimzi.io/next-node-ids: "[0-4]"  # Predictable IDs: 0, 1, 2, 3, 4
spec:
  replicas: 5
  roles:
    - controller
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 10Gi
        deleteClaim: true
  resources:
    requests:
      memory: 1Gi
      cpu: 500m
    limits:
      memory: 2Gi
      cpu: 1
```

**File: `examples/minikube-strimzi/kafka/kafka-nodepool-poc-brokers.yaml`**

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: poc-brokers
  labels:
    strimzi.io/cluster: kafka-poc
  annotations:
    strimzi.io/next-node-ids: "[100-102]"  # Predictable IDs: 100, 101, 102
spec:
  replicas: 3
  roles:
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 20Gi
        deleteClaim: true
  template:
    pod:
      metadata:
        labels:
          broker-set: poc
  resources:
    requests:
      memory: 2Gi
      cpu: 500m
    limits:
      memory: 4Gi
      cpu: 2
```

**File: `examples/minikube-strimzi/kafka/kafka-nodepool-general-brokers.yaml`**

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: general-brokers
  labels:
    strimzi.io/cluster: kafka-poc
  annotations:
    strimzi.io/next-node-ids: "[200-201]"  # Predictable IDs: 200, 201
spec:
  replicas: 2
  roles:
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 20Gi
        deleteClaim: true
  template:
    pod:
      metadata:
        labels:
          broker-set: general
  resources:
    requests:
      memory: 2Gi
      cpu: 500m
    limits:
      memory: 4Gi
      cpu: 2
```

**Broker Sets Configuration for Strimzi**

With predictable node IDs, the Cruise Control broker-sets.json becomes:

```json
{
  "brokerSets": {
    "poc-brokers": {
      "brokerIds": [100, 101, 102],
      "description": "POC broker pool for poc_* topics"
    },
    "general-brokers": {
      "brokerIds": [200, 201],
      "description": "General broker pool for other topics"
    }
  },
  "topicToBrokerSet": {
    "poc_.*": "poc-brokers"
  }
}
```

### 2.3 Kafka Cluster with Cruise Control

**File: `examples/minikube-strimzi/kafka/kafka-cluster.yaml`**

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: kafka-poc
  annotations:
    strimzi.io/kraft: enabled
    strimzi.io/node-pools: enabled
spec:
  kafka:
    version: 3.7.0
    metadataVersion: 3.7-IV4
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
  entityOperator:
    topicOperator: {}
    userOperator: {}
  cruiseControl:
    brokerCapacity:
      inboundNetwork: 10000KB/s
      outboundNetwork: 10000KB/s
    config:
      # BrokerSetAwareGoal configuration
      broker.set.resolver.class: com.linkedin.kafka.cruisecontrol.config.BrokerSetFileResolver

      # Goals with BrokerSetAwareGoal as hard goal
      hard.goals: >-
        com.linkedin.kafka.cruisecontrol.analyzer.goals.BrokerSetAwareGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.RackAwareGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.ReplicaCapacityGoal
      default.goals: >-
        com.linkedin.kafka.cruisecontrol.analyzer.goals.BrokerSetAwareGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.RackAwareGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.ReplicaCapacityGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.DiskCapacityGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.NetworkInboundCapacityGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.NetworkOutboundCapacityGoal

      # Self-healing
      anomaly.detection.interval.ms: 60000
      self.healing.enabled: true
    resources:
      requests:
        memory: 512Mi
        cpu: 250m
      limits:
        memory: 1Gi
        cpu: 500m
```

### 2.4 KafkaRebalance for Topic Placement

**File: `examples/minikube-strimzi/topics/kafka-rebalance.yaml`**

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaRebalance
metadata:
  name: enforce-broker-sets
  labels:
    strimzi.io/cluster: kafka-poc
spec:
  mode: full
  goals:
    - com.linkedin.kafka.cruisecontrol.analyzer.goals.BrokerSetAwareGoal
    - com.linkedin.kafka.cruisecontrol.analyzer.goals.ReplicaDistributionGoal
```

---

## Phase 3: Migration Steps

### Step 1: Create Directory Structure
```bash
mkdir -p examples/docker-compose/{config,scripts}
mkdir -p examples/minikube-strimzi/{setup,kafka,topics,scripts}
```

### Step 2: Move Existing Files
```bash
# Move current docker-compose to examples
mv docker-compose.yml examples/docker-compose/
mv scripts/* examples/docker-compose/scripts/
```

### Step 3: Update CI Workflows
- Update paths in `ci.yml` to point to `examples/docker-compose/`
- Update `integration-test.yml` for Docker Compose example

### Step 4: Update Root README
- Point to both examples
- Explain the difference between manual assignment vs Cruise Control enforcement

---

## Testing Plan

### Docker Compose Tests

1. **Startup Test**: All 5 brokers + Cruise Control healthy
2. **Topic Creation Test**: Create `poc_*` topics
3. **Placement Validation**: Verify topics on brokers 1,2,3 only
4. **Enforcement Test**:
   - Manually create topic on wrong brokers
   - Trigger Cruise Control rebalance
   - Verify topic moved to correct brokers
5. **Broker Failure Test**: Stop broker 3, verify replication continues

### Minikube/Strimzi Tests (Run Locally)

1. **Deployment Test**: All pods healthy
2. **NodePool Test**: Verify 5 controllers + 5 brokers running (IDs: 0-4, 100-102, 200-201)
3. **Topic Placement Test**: Create topics, verify placement on correct broker set
4. **KafkaRebalance Test**: Apply rebalance CR, verify Cruise Control enforces broker sets
5. **Document Results**: Capture screenshots/logs for documentation

---

## Resource Requirements

### Docker Compose
- RAM: 10GB minimum (5 brokers + Cruise Control)
- CPU: 4 cores recommended
- Disk: 5GB

### Minikube
- RAM: 16GB minimum
- CPU: 6 cores recommended
- Disk: 40GB
- Minikube driver: docker or hyperkit

---

## Resolved Questions (via Research)

### 1. Cruise Control Version
**Answer: Cruise Control 3.0.0+** includes the `BrokerSetAwareGoal` feature (merged via PR #1809).

For Docker Compose, we'll use the `linkedin/cruise-control:3.0.0` image or later.

### 2. Strimzi Node ID Assignment
**Answer: Use `strimzi.io/next-node-ids` annotation** to control broker IDs per pool.

Strimzi allows predictable node ID assignment using annotations:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: controllers
  annotations:
    strimzi.io/next-node-ids: "[0-4]"  # Controllers get IDs 0-4
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: poc-brokers
  annotations:
    strimzi.io/next-node-ids: "[100-102]"  # POC brokers get IDs 100-102
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: general-brokers
  annotations:
    strimzi.io/next-node-ids: "[200-201]"  # General brokers get IDs 200-201
```

This enables **predictable broker sets for Cruise Control** since each pool uses non-overlapping ID ranges.

---

## Timeline Estimate

| Phase | Tasks | Complexity |
|-------|-------|------------|
| Phase 1 | Docker Compose with Cruise Control | Medium |
| Phase 2 | Minikube + Strimzi setup | High |
| Phase 3 | Migration and documentation | Low |
| Testing | Both environments | Medium |

---

## References

- [Cruise Control BrokerSetAwareGoal PR #1809](https://github.com/linkedin/cruise-control/pull/1809)
- [Original Issue #1782](https://github.com/linkedin/cruise-control/issues/1782)
- [Strimzi KafkaNodePools Documentation](https://strimzi.io/docs/operators/latest/deploying#assembly-node-pools-str)
- [Strimzi Cruise Control Integration](https://strimzi.io/docs/operators/latest/deploying#cruise-control-concepts)
