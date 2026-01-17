# Test Results

This document contains the actual output from testing both deployment examples. Tests were performed on January 17, 2026.

## Docker Compose Example

### Environment
- Docker Desktop on macOS (Darwin 25.2.0)
- Apache Kafka 3.7.0 (official `apache/kafka:3.7.0` image)
- 5-broker KRaft cluster

### Cluster Startup

```
$ ./scripts/startup.sh

==========================================
 Kafka Rack-Aware Topic Placement PoC
==========================================

[1/3] Starting 5-broker Kafka cluster...

[2/3] Waiting for brokers to become healthy...
      This may take 30-60 seconds on first run...

  - kafka-1: healthy
  - kafka-2: healthy
  - kafka-3: healthy
  - kafka-4: healthy
  - kafka-5: healthy

[3/3] Verifying cluster topology...

Cluster ID:
Cluster ID: MkU3OEVBNTcwNTJENDM2Qk

==========================================
 Cluster is ready!
==========================================

Topology:
  DC1 (rack: dc1): Brokers 1, 2, 3, 4
  DC2 (rack: dc2): Broker 5

Broker Sets (for topic placement):
  poc-brokers:     Brokers 1, 2, 3 (for poc_* topics)
  general-brokers: Brokers 4, 5 (for other topics)

Bootstrap servers:
  localhost:9091 (broker-1)
  localhost:9092 (broker-2)
  localhost:9093 (broker-3)
  localhost:9094 (broker-4)
  localhost:9095 (broker-5)

Next steps:
  ./scripts/create-topics.sh      - Create poc_* topics
  ./scripts/validate-placement.sh - Verify topic placement
  ./scripts/inspect-cluster.sh    - View cluster state
```

### Topic Creation

```
$ ./scripts/create-topics.sh

==========================================
 Creating poc_* Topics
==========================================

Target brokers: 1,2,3 (DC1 only)
Partitions: 6, Replication Factor: 3

Creating topic: poc_orders
  - Created successfully
Creating topic: poc_payments
  - Created successfully
Creating topic: poc_inventory
  - Created successfully

==========================================
 Verifying Topic Placement
==========================================

Topic: poc_orders
Topic: poc_orders	TopicId: saVa-RgdROibvYl6WARUzA	PartitionCount: 6	ReplicationFactor: 3
	Topic: poc_orders	Partition: 0	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_orders	Partition: 1	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_orders	Partition: 2	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2
	Topic: poc_orders	Partition: 3	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_orders	Partition: 4	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_orders	Partition: 5	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2

==========================================
 Topics Created Successfully
==========================================

All poc_* topics are assigned to brokers 1, 2, 3 only.
```

### Placement Validation

```
$ ./scripts/validate-placement.sh

==========================================
 Validating poc_* Topic Placement
==========================================

Rule: All poc_* topics must have replicas only on brokers: 1 2 3

Checking topic: poc_inventory
Checking topic: poc_orders
Checking topic: poc_payments

==========================================
 Validation Results
==========================================

Topics checked:     3
Partitions checked: 18
Violations found:   0

PASSED: All poc_* topics have replicas only on brokers 1 2 3
```

### Cluster Inspection

```
$ ./scripts/inspect-cluster.sh

==========================================
 Kafka Cluster Inspection
==========================================

=== Container Status ===

NAMES     STATUS                   PORTS
kafka-2   Up 3 minutes (healthy)   0.0.0.0:9092->9094/tcp
kafka-1   Up 3 minutes (healthy)   0.0.0.0:9091->9091/tcp
kafka-5   Up 3 minutes (healthy)   0.0.0.0:9095->9097/tcp
kafka-3   Up 3 minutes (healthy)   0.0.0.0:9093->9095/tcp
kafka-4   Up 3 minutes (healthy)   0.0.0.0:9094->9096/tcp

=== Broker Topology ===

Broker ID | Rack | External Port | Status
----------|------|---------------|-------
    1     | dc1 |     9091      | healthy
    2     | dc1 |     9092      | healthy
    3     | dc1 |     9093      | healthy
    4     | dc1 |     9094      | healthy
    5     | dc2 |     9095      | healthy

=== Topics ===

poc_inventory
poc_orders
poc_payments

=== poc_* Topic Details ===

--- poc_inventory ---
Topic: poc_inventory	TopicId: LMiravpJRMq9aWNw_YUqFA	PartitionCount: 6	ReplicationFactor: 3
	Topic: poc_inventory	Partition: 0	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_inventory	Partition: 1	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_inventory	Partition: 2	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2
	Topic: poc_inventory	Partition: 3	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_inventory	Partition: 4	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_inventory	Partition: 5	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2

--- poc_orders ---
Topic: poc_orders	TopicId: saVa-RgdROibvYl6WARUzA	PartitionCount: 6	ReplicationFactor: 3
	Topic: poc_orders	Partition: 0	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_orders	Partition: 1	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_orders	Partition: 2	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2
	Topic: poc_orders	Partition: 3	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_orders	Partition: 4	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_orders	Partition: 5	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2

--- poc_payments ---
Topic: poc_payments	TopicId: 8PJeJFPiTOCe-nPQVoGL8w	PartitionCount: 6	ReplicationFactor: 3
	Topic: poc_payments	Partition: 0	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_payments	Partition: 1	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_payments	Partition: 2	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2
	Topic: poc_payments	Partition: 3	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: poc_payments	Partition: 4	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
	Topic: poc_payments	Partition: 5	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2

=== Broker Distribution Summary ===

Broker | Partitions as Leader | Partitions as Replica
-------|---------------------|----------------------
   1   |          6          |          18
   2   |          6          |          18
   3   |          6          |          18
   4   |          0          |          0
   5   |          0          |          0

==========================================
```

---

## Minikube/Strimzi Example

### Environment
- Minikube v1.37.0 with Docker driver
- Strimzi Operator 0.43.0 (latest)
- Apache Kafka 4.0.0
- KRaft mode with KafkaNodePools

### Strimzi Operator Installation

```
$ ./setup/install.sh

==========================================
 Strimzi Operator Installation
==========================================

Strimzi Version: 0.43.0
Namespace: kafka

[1/4] Checking cluster connectivity...
Connected to cluster

[2/4] Creating namespace...
namespace/kafka created

[3/4] Installing Strimzi operator...
Downloading and applying Strimzi installation files...
customresourcedefinition.apiextensions.k8s.io/kafkabridges.kafka.strimzi.io created
customresourcedefinition.apiextensions.k8s.io/kafkas.kafka.strimzi.io created
customresourcedefinition.apiextensions.k8s.io/kafkanodepools.kafka.strimzi.io created
...

[4/4] Waiting for Strimzi operator to be ready...
pod/strimzi-cluster-operator-8457d7566-9cmrh condition met

==========================================
 Strimzi Operator Installed Successfully
==========================================

Operator pod:
NAME                                       READY   STATUS    RESTARTS   AGE
strimzi-cluster-operator-8457d7566-9cmrh   1/1     Running   0          50s
```

### Kafka Cluster Deployment

```
$ kubectl get pods -n kafka

NAME                                         READY   STATUS    RESTARTS   AGE
kafka-poc-controllers-0                      1/1     Running   0          2m2s
kafka-poc-controllers-1                      1/1     Running   0          2m1s
kafka-poc-controllers-2                      1/1     Running   0          2m1s
kafka-poc-controllers-3                      1/1     Running   0          2m1s
kafka-poc-controllers-4                      1/1     Running   0          2m1s
kafka-poc-cruise-control-f8c489b69-j5nfq     1/1     Running   0          51s
kafka-poc-entity-operator-86bbb4fcf7-fsz5v   2/2     Running   0          55s
kafka-poc-general-brokers-200                1/1     Running   0          2m1s
kafka-poc-general-brokers-201                1/1     Running   0          2m1s
kafka-poc-poc-brokers-100                    1/1     Running   0          2m1s
kafka-poc-poc-brokers-101                    1/1     Running   0          2m1s
kafka-poc-poc-brokers-102                    1/1     Running   0          2m1s
strimzi-cluster-operator-8457d7566-9cmrh     1/1     Running   0          13m
```

### KafkaNodePools Status

```
$ kubectl get kafkanodepools -n kafka

NAME              DESIRED REPLICAS   ROLES            NODEIDS
controllers       5                  ["controller"]   [0,1,2,3,4]
general-brokers   2                  ["broker"]       [200,201]
poc-brokers       3                  ["broker"]       [100,101,102]
```

### Kafka Cluster Status

```
$ kubectl get kafka kafka-poc -n kafka

NAME        READY   METADATA STATE   WARNINGS
kafka-poc   True
```

### Topic Creation

```
$ ./scripts/create-topics.sh

==========================================
 Creating POC Topics (Strimzi)
==========================================

Target brokers: 100, 101, 102 (POC Broker Pool)
Partitions: 6, Replication Factor: 3

Using Kafka pod: kafka-poc-poc-brokers-100

Creating topic: poc-orders
  - Created successfully
Creating topic: poc-payments
  - Created successfully
Creating topic: poc-inventory
  - Created successfully
```

### Topic Placement Details

```
$ kubectl exec -n kafka kafka-poc-poc-brokers-100 -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka-poc-kafka-bootstrap:9092 \
    --describe \
    --topic poc-orders,poc-payments,poc-inventory

Topic: poc-inventory	TopicId: gtuZ3n7ATQmUigpacaAYZQ	PartitionCount: 6	ReplicationFactor: 3
	Topic: poc-inventory	Partition: 0	Leader: 100	Replicas: 100,101,102	Isr: 100,101,102
	Topic: poc-inventory	Partition: 1	Leader: 101	Replicas: 101,102,100	Isr: 101,102,100
	Topic: poc-inventory	Partition: 2	Leader: 102	Replicas: 102,100,101	Isr: 102,100,101
	Topic: poc-inventory	Partition: 3	Leader: 100	Replicas: 100,101,102	Isr: 100,101,102
	Topic: poc-inventory	Partition: 4	Leader: 101	Replicas: 101,102,100	Isr: 101,102,100
	Topic: poc-inventory	Partition: 5	Leader: 102	Replicas: 102,100,101	Isr: 102,100,101
Topic: poc-payments	TopicId: NBXN2lP1RBy0b-sLSwpBUA	PartitionCount: 6	ReplicationFactor: 3
	Topic: poc-payments	Partition: 0	Leader: 100	Replicas: 100,101,102	Isr: 100,101,102
	Topic: poc-payments	Partition: 1	Leader: 101	Replicas: 101,102,100	Isr: 101,102,100
	Topic: poc-payments	Partition: 2	Leader: 102	Replicas: 102,100,101	Isr: 102,100,101
	Topic: poc-payments	Partition: 3	Leader: 100	Replicas: 100,101,102	Isr: 100,101,102
	Topic: poc-payments	Partition: 4	Leader: 101	Replicas: 101,102,100	Isr: 101,102,100
	Topic: poc-payments	Partition: 5	Leader: 102	Replicas: 102,100,101	Isr: 102,100,101
Topic: poc-orders	TopicId: xdTDlabITBi_mZnkP-4_aA	PartitionCount: 6	ReplicationFactor: 3
	Topic: poc-orders	Partition: 0	Leader: 100	Replicas: 100,101,102	Isr: 100,101,102
	Topic: poc-orders	Partition: 1	Leader: 101	Replicas: 101,102,100	Isr: 101,102,100
	Topic: poc-orders	Partition: 2	Leader: 102	Replicas: 102,100,101	Isr: 102,100,101
	Topic: poc-orders	Partition: 3	Leader: 100	Replicas: 100,101,102	Isr: 100,101,102
	Topic: poc-orders	Partition: 4	Leader: 101	Replicas: 101,102,100	Isr: 101,102,100
	Topic: poc-orders	Partition: 5	Leader: 102	Replicas: 102,100,101	Isr: 102,100,101
```

### Placement Validation

```
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

---

## Summary

| Test | Docker Compose | Minikube/Strimzi |
|------|----------------|------------------|
| Cluster Startup | PASSED | PASSED |
| All Brokers Healthy | PASSED (5/5) | PASSED (10/10 pods) |
| Topic Creation | PASSED (3 topics) | PASSED (3 topics) |
| Placement Validation | PASSED (0 violations) | PASSED (0 violations) |
| Cruise Control | N/A | PASSED (running) |

### Key Observations

1. **Docker Compose**: Simple, fast startup. Uses official Apache Kafka image. No Cruise Control (no official Docker image available).

2. **Minikube/Strimzi**: Production-like setup with KafkaNodePools for separate controller and broker management. Includes Cruise Control for ongoing monitoring and rebalancing.

3. **Topic Placement**: Both examples successfully enforce topic placement rules:
   - Docker: Brokers 1, 2, 3 for `poc_*` topics
   - Strimzi: Brokers 100, 101, 102 for `poc-*` topics

4. **Leadership Distribution**: Evenly distributed across allowed brokers (6 partitions each per topic, 2 per broker).
