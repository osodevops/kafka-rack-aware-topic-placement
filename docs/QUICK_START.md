# Quick Start Guide

Get the Kafka rack-aware topic placement PoC running in minutes.

## Choose Your Deployment

| Method | Prerequisites | Best For |
|--------|--------------|----------|
| [Docker Compose](#docker-compose) | Docker Desktop | Local development, quick testing |
| [Minikube + Strimzi](#minikube--strimzi) | Minikube, kubectl | Production-like K8s environment |

---

## Docker Compose

### Prerequisites

- **Docker Desktop 4.x+** with Docker Compose v2
- **8GB RAM** available for Docker
- **Ports 9091-9095** available on localhost

### Step 1: Clone and Navigate

```bash
git clone https://github.com/osodevops/kafka-rack-aware-topic-placement.git
cd kafka-rack-aware-topic-placement/examples/docker-compose
```

### Step 2: Start the Cluster

```bash
./scripts/startup.sh
```

This will:
- Pull the Apache Kafka Docker image (first run only)
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

Topology:
  DC1 (rack: dc1): Brokers 1, 2, 3, 4
  DC2 (rack: dc2): Broker 5

Broker Sets (for topic placement):
  poc-brokers:     Brokers 1, 2, 3 (for poc_* topics)
  general-brokers: Brokers 4, 5 (for other topics)
```

### Step 3: Create Topics

```bash
./scripts/create-topics.sh
```

This creates three topics with replicas pinned to brokers 1, 2, 3:
- `poc_orders`
- `poc_payments`
- `poc_inventory`

### Step 4: Validate Placement

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

### Step 5: Explore

#### Inspect cluster state
```bash
./scripts/inspect-cluster.sh
```

#### Produce a message
```bash
docker exec -it kafka-1 /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka-1:9092 \
  --topic poc_orders
```

#### Consume messages
```bash
docker exec -it kafka-1 /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-1:9092 \
  --topic poc_orders \
  --from-beginning
```

### Step 6: Cleanup

```bash
# Stop cluster (preserves data)
./scripts/teardown.sh

# Stop and remove all data
./scripts/teardown.sh --clean
```

---

## Minikube + Strimzi

### Prerequisites

- **Minikube** v1.30+
- **kubectl** configured
- **4 CPUs and 8GB RAM** available for Minikube

### Step 1: Clone and Navigate

```bash
git clone https://github.com/osodevops/kafka-rack-aware-topic-placement.git
cd kafka-rack-aware-topic-placement/examples/minikube-strimzi
```

### Step 2: Start Minikube

```bash
minikube start --cpus=4 --memory=8192
```

### Step 3: Install Strimzi Operator

```bash
./setup/install.sh
```

**Expected output:**
```
==========================================
 Strimzi Operator Installation
==========================================

[1/4] Checking cluster connectivity...
Connected to cluster

[2/4] Creating namespace...
namespace/kafka created

[3/4] Installing Strimzi operator...
...

[4/4] Waiting for Strimzi operator to be ready...
pod/strimzi-cluster-operator condition met

==========================================
 Strimzi Operator Installed Successfully
==========================================
```

### Step 4: Deploy Kafka Cluster

```bash
./scripts/deploy.sh
```

This deploys:
- 5 Controllers (IDs: 0-4)
- 3 POC Brokers (IDs: 100, 101, 102)
- 2 General Brokers (IDs: 200, 201)
- Cruise Control
- Entity Operator

### Step 5: Create Topics

```bash
./scripts/create-topics.sh
```

Creates three topics with replicas on POC brokers only:
- `poc-orders`
- `poc-payments`
- `poc-inventory`

### Step 6: Validate Placement

```bash
./scripts/validate-placement.sh
```

**Expected output:**
```
==========================================
 Validating Topic Placement (Strimzi)
==========================================

Rule: All poc-* topics must have replicas only on brokers: 100 101 102

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

### Step 7: Explore

#### Check cluster status
```bash
kubectl get kafka -n kafka
kubectl get kafkanodepools -n kafka
kubectl get pods -n kafka
```

#### Access Cruise Control
```bash
kubectl port-forward svc/kafka-poc-cruise-control -n kafka 9090:9090
# Then open http://localhost:9090
```

### Step 8: Cleanup

```bash
./scripts/cleanup.sh

# Stop Minikube
minikube stop
```

---

## Next Steps

- Read [ARCHITECTURE.md](ARCHITECTURE.md) for technical details
- Read [OPERATIONS.md](OPERATIONS.md) to learn how to create custom topics
- Read [TEST_RESULTS.md](TEST_RESULTS.md) to see actual test output
- Read [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if you encounter issues

## Common Issues

| Issue | Solution |
|-------|----------|
| Port already in use | Stop conflicting services or change ports in `docker-compose.yml` |
| Brokers unhealthy | Ensure Docker has 8GB+ RAM allocated |
| Permission denied | Run `chmod +x scripts/*.sh` |
| Minikube OOM | Increase memory: `minikube start --memory=10240` |
| Strimzi operator not ready | Wait longer or check logs: `kubectl logs -n kafka -l name=strimzi-cluster-operator` |
