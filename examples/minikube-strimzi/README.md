# Minikube + Strimzi Example: Kafka with KafkaNodePools

This example demonstrates rack-aware topic placement using Strimzi on Kubernetes with dedicated controller and broker node pools, plus Cruise Control for rebalancing.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 Strimzi Kafka Cluster                    │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │           Controller NodePool (KRaft)             │   │   │
│  │  │  5 dedicated controllers (IDs: 0, 1, 2, 3, 4)     │   │   │
│  │  │  Manages cluster metadata via Raft consensus      │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │              POC Broker NodePool                  │   │   │
│  │  │  3 brokers (IDs: 100, 101, 102)                  │   │   │
│  │  │  Topics: poc-orders, poc-payments, poc-inventory │   │   │
│  │  │  Label: broker-set=poc                           │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │           General Broker NodePool                 │   │   │
│  │  │  2 brokers (IDs: 200, 201)                       │   │   │
│  │  │  Topics: general-purpose workloads               │   │   │
│  │  │  Label: broker-set=general                       │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │                Cruise Control                     │   │   │
│  │  │  Cluster monitoring and rebalancing              │   │   │
│  │  │  KafkaRebalance CRD for GitOps workflows         │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Strimzi Cluster Operator                    │   │
│  │  Manages Kafka, KafkaNodePool, KafkaTopic, etc.         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Minikube or other Kubernetes cluster (v1.25+)
- kubectl configured to access your cluster
- 8GB RAM minimum (for Minikube)
- 4 CPU cores recommended

### Starting Minikube

```bash
# Start Minikube with sufficient resources
minikube start --cpus=4 --memory=8192 --driver=docker

# Verify cluster is running
kubectl cluster-info
```

## Quick Start

```bash
# 1. Install Strimzi operator
./setup/install.sh

# 2. Deploy Kafka cluster with NodePools
./scripts/deploy.sh

# 3. Create topics with controlled placement
./scripts/create-topics.sh

# 4. Validate topic placement
./scripts/validate-placement.sh

# 5. Trigger rebalance (if needed)
./scripts/trigger-rebalance.sh

# 6. Cleanup
./scripts/cleanup.sh
```

## Node ID Assignment

Strimzi uses the `strimzi.io/next-node-ids` annotation to assign predictable node IDs:

| NodePool | Node IDs | Purpose |
|----------|----------|---------|
| `controllers` | 0, 1, 2, 3, 4 | KRaft metadata management |
| `poc-brokers` | 100, 101, 102 | Topics matching `poc-*` pattern |
| `general-brokers` | 200, 201 | All other topics |

This predictable ID assignment enables precise Cruise Control broker set configuration.

## KafkaNodePools

### Controllers

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: controllers
  annotations:
    strimzi.io/next-node-ids: "[0-4]"
spec:
  replicas: 5
  roles:
    - controller
```

### POC Brokers

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: poc-brokers
  annotations:
    strimzi.io/next-node-ids: "[100-102]"
spec:
  replicas: 3
  roles:
    - broker
  template:
    pod:
      metadata:
        labels:
          broker-set: poc
```

### General Brokers

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: general-brokers
  annotations:
    strimzi.io/next-node-ids: "[200-201]"
spec:
  replicas: 2
  roles:
    - broker
  template:
    pod:
      metadata:
        labels:
          broker-set: general
```

## Topic Placement

> **Note**: Strimzi's KafkaTopic CRD does not support explicit replica assignments. Topics with controlled placement must be created using `kafka-topics.sh` with the `--replica-assignment` flag.

The `create-topics.sh` script creates topics with explicit replica assignments:

```bash
# Example: Creating a topic with replica assignment to POC brokers
kubectl exec -n kafka kafka-poc-poc-brokers-100 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka-poc-kafka-bootstrap:9092 \
  --create \
  --topic poc-orders \
  --replica-assignment "100:101:102,101:102:100,102:100:101,100:101:102,101:102:100,102:100:101"
```

This ensures:
- 6 partitions per topic
- Replication factor of 3
- All replicas on POC brokers (100, 101, 102) only
- Leadership evenly distributed

## Cruise Control Integration

Strimzi integrates Cruise Control via the `KafkaRebalance` Custom Resource:

### Workflow

1. **Create KafkaRebalance CR**
   ```bash
   kubectl apply -f topics/kafka-rebalance.yaml -n kafka
   ```

2. **Wait for Proposal**
   ```bash
   kubectl get kafkarebalance -n kafka -w
   ```

3. **Review Proposal**
   ```bash
   kubectl get kafkarebalance rebalance-poc -n kafka -o yaml
   ```

4. **Approve Rebalance**
   ```bash
   kubectl annotate kafkarebalance rebalance-poc \
     strimzi.io/rebalance=approve -n kafka
   ```

5. **Monitor Progress**
   ```bash
   kubectl get kafkarebalance rebalance-poc -n kafka -w
   ```

### KafkaRebalance States

| State | Description |
|-------|-------------|
| `New` | Resource created, waiting for Cruise Control |
| `PendingProposal` | Cruise Control generating proposal |
| `ProposalReady` | Proposal ready for review/approval |
| `Rebalancing` | Rebalance in progress |
| `Ready` | Rebalance completed successfully |
| `NotReady` | Error occurred |

## Directory Structure

```
minikube-strimzi/
├── setup/
│   ├── 00-namespace.yaml       # Kafka namespace
│   └── install.sh              # Strimzi operator installation
├── kafka/
│   ├── kafka-cluster.yaml      # Kafka CR with Cruise Control
│   ├── kafka-nodepool-controllers.yaml
│   ├── kafka-nodepool-poc-brokers.yaml
│   └── kafka-nodepool-general-brokers.yaml
├── topics/
│   ├── poc-topics.yaml         # KafkaTopic reference (docs only)
│   └── kafka-rebalance.yaml    # KafkaRebalance CR
└── scripts/
    ├── deploy.sh               # Deploy Kafka cluster
    ├── create-topics.sh        # Create topics with replica assignment
    ├── validate-placement.sh   # Validate topic placement
    ├── trigger-rebalance.sh    # Manage KafkaRebalance
    └── cleanup.sh              # Remove all resources
```

## Validating Placement

```bash
$ ./scripts/validate-placement.sh

==========================================
 Validating Topic Placement (Strimzi)
==========================================

Rule: All poc-* topics must have replicas only on brokers: 100 101 102

Using Kafka pod: kafka-poc-poc-brokers-100

Checking topic: poc-inventory
Checking topic: poc-orders
Checking topic: poc-payments

==========================================
 Validation Results
==========================================

Topics checked:     3
Partitions checked: 18
Violations found:   0

PASSED: All poc-* topics have replicas only on brokers 100 101 102
```

## Useful Commands

```bash
# Check Kafka cluster status
kubectl get kafka -n kafka

# List all pods
kubectl get pods -n kafka

# Check NodePool status
kubectl get kafkanodepools -n kafka

# View Cruise Control logs
kubectl logs -f deployment/kafka-poc-cruise-control -n kafka

# Port-forward Cruise Control API
kubectl port-forward svc/kafka-poc-cruise-control 9090:9090 -n kafka

# Access Cruise Control API
curl http://localhost:9090/kafkacruisecontrol/state

# Describe a topic
kubectl exec -n kafka kafka-poc-poc-brokers-100 -- \
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-poc-kafka-bootstrap:9092 \
  --describe --topic poc-orders

# List all topics
kubectl exec -n kafka kafka-poc-poc-brokers-100 -- \
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-poc-kafka-bootstrap:9092 --list
```

## Troubleshooting

### Pods stuck in Pending

Check if there are enough resources:
```bash
kubectl describe pod <pod-name> -n kafka
minikube dashboard  # Check resource usage
```

### Kafka version not supported

Strimzi 0.43.0 supports Kafka 4.x only. Check the kafka-cluster.yaml version:
```yaml
spec:
  kafka:
    version: 4.0.0
    metadataVersion: 4.0-IV0
```

### Cruise Control not generating proposals

Cruise Control needs time to collect metrics. Also ensure the metrics ConfigMap exists:
```bash
# Create metrics ConfigMap if missing
kubectl get configmap cruise-control-metrics -n kafka

# Check Cruise Control state
kubectl port-forward svc/kafka-poc-cruise-control 9090:9090 -n kafka
curl http://localhost:9090/kafkacruisecontrol/state
```

### KafkaRebalance stuck in NotReady

Check the error message:
```bash
kubectl get kafkarebalance rebalance-poc -n kafka -o jsonpath='{.status.conditions[0].message}'
```

## Resource Requirements

| Component | Replicas | CPU Request | Memory Request |
|-----------|----------|-------------|----------------|
| Controllers | 5 | 250m each | 512Mi each |
| POC Brokers | 3 | 250m each | 1Gi each |
| General Brokers | 2 | 250m each | 1Gi each |
| Cruise Control | 1 | 250m | 512Mi |
| Entity Operator | 1 | 200m | 512Mi |
| **Total** | 12 | ~3 cores | ~8Gi |
