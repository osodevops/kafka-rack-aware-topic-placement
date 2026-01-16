# Kafka Rack-Aware Topic Placement Proof-of-Concept

**Product Requirements Document**

**Version:** 1.0  
**Date:** January 2026  
**Author:** Engineering Team  
**Status:** Design Phase

---

## 1. Executive Summary

This document outlines the requirements for a proof-of-concept (PoC) system that validates Apache Kafka's rack-awareness capabilities for topic placement across distributed datacenters. The PoC will demonstrate that Kafka can successfully place topics and their partitions on specific brokers while respecting rack/datacenter boundaries, enabling fault-tolerance strategies and infrastructure optimization.

**Key Objective:** Prove that topics with a specific naming prefix can be reliably assigned to specific broker sets (brokers 1, 2, 3 in this case) across a 5-broker cluster distributed across 2 datacenters using Docker Compose.

---

## 2. Problem Statement

### Current Challenges

1. **Uncontrolled Topic Distribution:** By default, Kafka distributes partitions across all brokers using automatic round-robin assignment, making it difficult to enforce topology-specific placement policies.

2. **Lack of Visibility:** Existing Docker Compose examples don't demonstrate rack-aware replica assignment or verify partition placement across infrastructure boundaries.

3. **No Proof-of-Concept Tooling:** Teams lack documented, reproducible examples showing how to:
   - Configure brokers with rack identifiers
   - Assign topics to specific broker subsets
   - Validate the resulting replica distribution
   - Maintain consistent placement through the topic lifecycle

4. **Operational Complexity:** Manual partition reassignment using JSON-based tools (`kafka-reassign-partitions.sh`) requires manual JSON generation and lacks automation.

### Business Impact

- **Infrastructure Optimization:** Needed to validate cost-optimization strategies (e.g., pinning high-throughput topics to specific hardware tiers)
- **Compliance:** Required to demonstrate compliance with data residency requirements (e.g., data must stay in specific zones)
- **Disaster Recovery:** Essential for validating that critical topics can be isolated to specific datacenters for regulatory or latency reasons

---

## 3. Scope & Objectives

### In Scope

1. **Docker Compose Cluster Setup**
   - 5 Kafka brokers distributed across 2 datacenters (DC1: brokers 1,2,3,4 / DC2: broker 5)
   - KRaft mode (no ZooKeeper) for modern architecture
   - Explicit rack configuration via environment variables
   - Proper networking and port mapping

2. **Rack-Aware Topic Placement**
   - Create topics with prefix `poc_` that are constrained to brokers 1, 2, 3 only
   - Validate replica assignment respects rack boundaries
   - Implement manual replica assignment via JSON-based tools

3. **Automation & Validation**
   - Shell scripts to programmatically create topics with specific assignments
   - Python scripts to validate partition placement
   - Monitoring/inspection utilities to visualize broker distribution
   - Dashboard showing current state of topics and replicas

4. **Documentation & Reproducibility**
   - Complete setup guide with prerequisites
   - Step-by-step instructions to spin up the cluster
   - Explanation of each configuration parameter
   - Troubleshooting guide for common issues

### Out of Scope

1. **Confluent Cloud Integration** - This is a local Docker-based PoC only
2. **Performance Benchmarking** - Not focused on throughput/latency metrics
3. **Security (SASL/SSL)** - Base configuration without authentication
4. **Multi-cluster Replication** - Single cluster only
5. **Advanced Tiered Storage** - Standard broker log directories only

---

## 4. Architecture

### 4.1 Cluster Topology

```
┌─────────────────────────────────────────┐
│        Kafka Cluster (5 Brokers)        │
├────────────────────┬────────────────────┤
│   Datacenter 1     │   Datacenter 2     │
│  (Rack: "dc1")     │   (Rack: "dc2")    │
├────────────────────┼────────────────────┤
│ Broker 1 (ID: 1)   │ Broker 5 (ID: 5)   │
│ Broker 2 (ID: 2)   │                    │
│ Broker 3 (ID: 3)   │                    │
│ Broker 4 (ID: 4)   │                    │
└────────────────────┴────────────────────┘

Topics with prefix "poc_" →  Brokers 1, 2, 3 only
                             (Primary DC only)

Other topics →              All brokers (default distribution)
```

### 4.2 Docker Compose Structure

- **5 KRaft brokers** (confluent/cp-kafka:latest)
- **Shared Docker network** for inter-broker communication
- **Volume mounts** for persistent broker state
- **Port mappings** for external client access
- **Health checks** for startup verification

### 4.3 Configuration Details

**Broker Configuration:**
- `KAFKA_NODE_ID`: Unique identifier (1-5)
- `KAFKA_BROKER_RACK`: Rack identifier ("dc1" for brokers 1-4, "dc2" for broker 5)
- `KAFKA_LISTENERS`: Controller and broker listeners
- `KAFKA_ADVERTISED_LISTENERS`: For client connectivity
- `KAFKA_CONTROLLER_QUORUM_VOTERS`: KRaft voting set

**Topic Configuration:**
- Default replication factor: 3
- Default partitions: 6 (to test distribution)
- Rack-aware replica assignment enabled

---

## 5. Technical Approach

### 5.1 Topic Creation Strategy

**Two approaches will be implemented:**

#### Approach A: Manual Replica Assignment (Recommended)

Use `kafka-topics.sh --replica-assignment` to explicitly specify which brokers host each replica:

```bash
kafka-topics.sh --create \
  --topic poc_example \
  --replica-assignment \
    0:1:2,1:2:3,2:3:1,3:1:2,4:2:3,5:3:1
```

**Advantages:**
- Complete control over replica placement
- Deterministic assignments
- Easy to validate and reproduce
- Supports complex placement policies

**Process:**
1. Generate broker list and partition count
2. Create Python script to generate replica assignments
3. Execute via shell wrapper around kafka-topics CLI

#### Approach B: Rack-Aware Auto Assignment (Supplementary)

Leverage Kafka's built-in rack awareness during topic creation:

```bash
kafka-topics.sh --create \
  --topic poc_rack_aware \
  --partitions 6 \
  --replication-factor 3 \
  --bootstrap-server localhost:9092
```

**Note:** This only works if:
- All brokers have `broker.rack` configured
- New topic uses only brokers from the constrained set (requires advanced configuration)

### 5.2 Partition Reassignment Workflow

For existing topics or complex placement changes:

1. **Generate Current State**
   ```bash
   kafka-reassign-partitions.sh --describe \
     --bootstrap-server localhost:9092 \
     --topics-to-move-json-file topics.json
   ```

2. **Create Assignment JSON**
   ```json
   {
     "version": 1,
     "partitions": [
       {
         "topic": "poc_orders",
         "partition": 0,
         "replicas": [1, 2, 3],
         "log_dirs": ["any", "any", "any"]
       }
     ]
   }
   ```

3. **Execute Reassignment**
   ```bash
   kafka-reassign-partitions.sh --execute \
     --bootstrap-server localhost:9092 \
     --reassignment-json-file reassignment.json
   ```

4. **Monitor Progress**
   ```bash
   kafka-reassign-partitions.sh --verify \
     --bootstrap-server localhost:9092 \
     --reassignment-json-file reassignment.json
   ```

### 5.3 Validation & Monitoring

**Partition Inspection Tool:**
```bash
kafka-topics.sh --describe --topic poc_* \
  --bootstrap-server localhost:9092
```

Expected output shows each partition's leader and replicas assigned to brokers 1-3 only.

**Python Validation Script:**
- Parse topic metadata from Kafka
- Verify all `poc_*` topics have replicas only on brokers [1,2,3]
- Flag any violations
- Generate HTML report with distribution visualization

---

## 6. Deliverables

### 6.1 Repository Structure

```
kafka-rack-placement-poc/
├── README.md                           # Setup and usage guide
├── docker-compose.yml                  # 5-broker cluster definition
├── cluster-config/
│   ├── broker-configs.env              # Broker environment variables
│   └── kraft-metadata.json             # KRaft quorum setup (if needed)
├── scripts/
│   ├── 01-startup.sh                   # Spin up cluster
│   ├── 02-create-topics.sh             # Create topics with placement
│   ├── 03-validate-placement.sh        # Verify replica assignments
│   ├── 04-inspect-cluster.sh           # Query cluster metadata
│   ├── 05-reassign-topics.sh           # Batch reassignment utility
│   └── teardown.sh                     # Clean up cluster
├── python/
│   ├── requirements.txt                # Dependencies
│   ├── topic_validator.py              # Verify topic placement
│   ├── assignment_generator.py         # Generate JSON assignments
│   └── visualizer.py                   # Dashboard/HTML report
├── json-templates/
│   ├── topics-to-move.json             # Topic selector template
│   ├── reassignment-template.json      # Reassignment JSON template
│   └── examples/
│       ├── poc_orders_assignment.json
│       ├── poc_payments_assignment.json
│       └── poc_inventory_assignment.json
└── docs/
    ├── ARCHITECTURE.md
    ├── QUICK_START.md
    ├── FAQ.md
    └── TROUBLESHOOTING.md
```

### 6.2 Key Files Description

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Complete 5-broker cluster with KRaft, rack config, health checks |
| `01-startup.sh` | Validates Docker, starts services, waits for readiness |
| `02-create-topics.sh` | Creates poc_* topics with manual replica assignment |
| `03-validate-placement.sh` | Verifies all poc_* topics only use brokers 1-3 |
| `topic_validator.py` | Python implementation of validation logic with detailed reporting |
| `assignment_generator.py` | Generates JSON reassignment files from configuration |
| `visualizer.py` | Creates HTML dashboard showing topic distribution |

### 6.3 Documentation

**Markdown files to be created:**

1. **README.md** - Quick start and overview
2. **QUICK_START.md** - 5-minute setup guide
3. **ARCHITECTURE.md** - Deep dive into design decisions
4. **CONFIGURATION.md** - Parameter reference
5. **OPERATIONS.md** - How to create/modify/monitor topics
6. **TROUBLESHOOTING.md** - Common issues and solutions
7. **FAQ.md** - Frequently asked questions

---

## 7. Implementation Details

### 7.1 Docker Compose Configuration Example

```yaml
version: '3.8'

services:
  # Brokers 1-4 in DC1
  kafka-1:
    image: confluentinc/cp-kafka:7.6.0
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_BROKER_RACK: "dc1"
      KAFKA_PROCESS_ROLES: 'broker,controller'
      KAFKA_LISTENERS: 'CONTROLLER://kafka-1:29093,PLAINTEXT://kafka-1:29092,EXTERNAL://0.0.0.0:9091'
      KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://kafka-1:29092,EXTERNAL://localhost:9091'
      KAFKA_CONTROLLER_LISTENER_NAMES: 'CONTROLLER'
      KAFKA_INTER_BROKER_LISTENER_NAME: 'PLAINTEXT'
      KAFKA_CONTROLLER_QUORUM_VOTERS: '1@kafka-1:29093,2@kafka-2:29093,3@kafka-3:29093,4@kafka-4:29093,5@kafka-5:29093'
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      CLUSTER_ID: 'MkQkRDd8T6ePR7qusEPILQ'
    ports:
      - "9091:9091"
    healthcheck:
      test: ["CMD", "kafka-broker-api-versions.sh", "--bootstrap-server", "localhost:9091"]
      interval: 5s
      timeout: 10s
      retries: 5
    networks:
      - kafka-network
    volumes:
      - kafka-1-data:/var/lib/kafka/data

  kafka-2:
    # Similar configuration, KAFKA_NODE_ID: 2, port: 9092, EXTERNAL: 9092
    
  # ... kafka-3, kafka-4 (DC1)
  
  # kafka-5 with KAFKA_BROKER_RACK: "dc2", port: 9095
  
networks:
  kafka-network:
    driver: bridge

volumes:
  kafka-1-data:
  kafka-2-data:
  kafka-3-data:
  kafka-4-data:
  kafka-5-data:
```

### 7.2 Topic Creation Script Example

```bash
#!/bin/bash
set -e

BOOTSTRAP_SERVER="localhost:9092"

# Create topic poc_orders with replicas on brokers 1,2,3
kafka-topics.sh --create \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --topic poc_orders \
  --partitions 6 \
  --replica-assignment \
    0:1:2:3,1:2:3:1,2:3:1:2,3:1:2:3,4:2:3:1,5:3:1:2

echo "Topic poc_orders created with replicas on brokers 1,2,3"

# Verify
kafka-topics.sh --describe --topic poc_orders \
  --bootstrap-server "$BOOTSTRAP_SERVER"
```

### 7.3 Validation Script Example (Python)

```python
#!/usr/bin/env python3
"""
Validate that all poc_* topics have replicas only on brokers 1-3
"""

from kafka.admin import KafkaAdminClient
from kafka.admin import ConfigResource, ConfigResourceType
import json

ALLOWED_BROKERS = {1, 2, 3}
BOOTSTRAP_SERVERS = ['localhost:9092']

admin_client = KafkaAdminClient(
    bootstrap_servers=BOOTSTRAP_SERVERS,
    request_timeout_ms=5000
)

# Get all topics
topics = admin_client.list_topics()
poc_topics = [t for t in topics if t.startswith('poc_')]

violations = []
for topic in poc_topics:
    partitions = admin_client.describe_topics([topic])[topic].partitions
    
    for partition_id, partition_info in partitions.items():
        replicas = set(partition_info.replicas)
        
        if not replicas.issubset(ALLOWED_BROKERS):
            violations.append({
                'topic': topic,
                'partition': partition_id,
                'replicas': list(replicas),
                'unexpected_brokers': list(replicas - ALLOWED_BROKERS)
            })

if violations:
    print("❌ VALIDATION FAILED")
    print(json.dumps(violations, indent=2))
    exit(1)
else:
    print("✅ VALIDATION PASSED")
    print(f"All {len(poc_topics)} poc_* topics use only brokers {ALLOWED_BROKERS}")
    exit(0)
```

---

## 8. Testing & Validation Strategy

### 8.1 Test Scenarios

| Scenario | Expected Result | Validation Method |
|----------|-----------------|-------------------|
| **Single topic creation** | poc_orders created with 6 partitions, all replicas on brokers 1-3 | `kafka-topics.sh --describe` |
| **Multiple topics** | Create poc_orders, poc_payments, poc_inventory | Batch create script |
| **Rack awareness** | No partition has replicas from same rack | Inspect partition distribution |
| **Broker failure simulation** | Remaining replicas handle load | Kill broker, verify ISR (in-sync replicas) |
| **Topic reassignment** | Move existing topic from brokers 1-5 to 1-3 | Execute reassignment JSON, verify state |
| **Validation tool** | Detect violations of placement policy | Intentionally violate, run validator |

### 8.2 Success Criteria

✅ Cluster starts successfully with all 5 brokers healthy  
✅ All `poc_*` topics have replicas exclusively on brokers 1, 2, 3  
✅ No `poc_*` partition has replicas on brokers 4 or 5  
✅ Rack identifiers properly configured ("dc1" and "dc2")  
✅ Replica assignment respects rack boundaries where possible  
✅ Topics can be created via CLI and programmatic API  
✅ Validation script detects and reports placement violations  
✅ Documentation is complete and reproducible on fresh environment  

---

## 9. Success Metrics

1. **Reproducibility:** PoC can be fully set up in <5 minutes from fresh environment
2. **Accuracy:** 100% of `poc_*` topics have replicas only on intended brokers
3. **Documentation Quality:** Any engineer can understand and extend the system without support
4. **Automation:** Zero manual broker configuration needed beyond initial docker-compose
5. **Validation:** Automated tool catches 100% of placement policy violations

---

## 10. Timeline & Milestones

| Phase | Deliverable | Duration |
|-------|-------------|----------|
| **Phase 1** | Docker Compose setup, basic 5-broker cluster | Day 1 |
| **Phase 2** | Topic creation scripts with manual assignment | Day 1-2 |
| **Phase 3** | Validation and monitoring scripts (Python) | Day 2 |
| **Phase 4** | Comprehensive documentation & examples | Day 2-3 |
| **Phase 5** | Testing, refinement, and GitHub repo setup | Day 3 |

**Total Duration:** 3 days  
**Effort:** ~30-40 engineering hours

---

## 11. Open Questions & Decisions

### Questions to Resolve

1. **Question:** Should we include Confluent Control Center UI for visualization?
   - **Current Decision:** No - adds complexity; Python dashboard sufficient for PoC
   - **Alternative:** Include optional docker-compose extension

2. **Question:** Should the validation run continuously or on-demand?
   - **Current Decision:** On-demand shell script + Python CLI tool
   - **Alternative:** Add optional cron job or monitoring sidecar

3. **Question:** Do we need to demonstrate broker failure handling?
   - **Current Decision:** Yes, include in documentation/testing
   - **Alternative:** Out of scope for initial PoC

### Design Decisions Made

1. ✅ **KRaft mode (no ZooKeeper)** - Simpler, modern, fewer moving parts
2. ✅ **Manual replica assignment** - More control, clearer demonstration of placement
3. ✅ **Python for tooling** - Standard for data/infra teams, easier to extend
4. ✅ **2 racks (2 DCs)** - Meaningful but not overly complex topology
5. ✅ **Prefix-based topic selection** - Easy to implement and understand

---

## 12. Risk Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Docker resource constraints | Medium | High | Document min. requirements (8 cores, 16GB RAM) |
| Port conflicts on host | Medium | Medium | Use configurable port mapping in docker-compose |
| Network issues in Docker | Low | High | Use explicit network definition, health checks |
| Kafka version incompatibility | Low | Medium | Pin image versions, test on latest stable |
| Script portability (Linux vs Mac) | Medium | Low | Use bash strict mode, test on both OS |

---

## 13. Future Enhancements (Out of Scope)

- **Tier-based placement:** Assign topics based on SLA (hot/warm/cold brokers)
- **Constraint satisfaction solver:** More complex placement policies (node affinity, anti-affinity)
- **Metrics integration:** Export placement metrics to Prometheus
- **Admission control:** Prevent topic creation that violates policies
- **Multi-cluster federation:** Extend to multiple Kafka clusters
- **Kubernetes support:** Convert Docker Compose to Helm charts

---

## 14. Appendix: Key References

### Kafka Documentation
- [KRaft Configuration Reference](https://kafka.apache.org/documentation/#configuration)
- [Rack Awareness Feature](https://kafka.apache.org/documentation/#basic_ops_racks)
- [Topic Management Tools](https://kafka.apache.org/documentation/#tools)
- [Partition Reassignment Tool](https://kafka.apache.org/documentation/#basic_ops_cluster_expansion)

### Docker & Tooling
- [Confluent Platform Docker Images](https://hub.docker.com/r/confluentinc/cp-kafka)
- [Docker Compose Best Practices](https://docs.docker.com/compose/)
- [Kafka Python Client](https://github.com/dpkp/kafka-python)

### Related Tools & Projects
- [topicmappr](https://github.com/DataDog/topicmappr) - Advanced partition assignment tool
- [kafkactl](https://github.com/deviceinsight/kafkactl) - Kafka CLI wrapper
- [kcat/kafkacat](https://github.com/edenhill/kcat) - Kafka cat utility

---

## 15. Glossary

| Term | Definition |
|------|-----------|
| **Broker** | A Kafka server that stores topic partitions and serves client requests |
| **Partition** | A unit of parallelism; topics are divided into partitions distributed across brokers |
| **Replica** | A copy of a partition on a broker; provides redundancy and fault tolerance |
| **Rack** | Logical grouping of brokers (typically representing physical racks, datacenters, or AZs) |
| **Leader** | The broker that currently serves read/write requests for a partition |
| **KRaft** | Kafka Raft - replaces ZooKeeper for metadata management; modern Kafka (3.0+) |
| **Replica Assignment** | Specification of which brokers hold which partition replicas |
| **Rack-Aware Assignment** | Replica placement that respects rack boundaries (different racks preferred) |
| **In-Sync Replica (ISR)** | Replicas that are fully caught up with the leader |

---

**Document Approval:**
- [ ] Engineering Lead
- [ ] Infrastructure Lead
- [ ] Product Manager

**Last Updated:** January 16, 2026  
**Next Review:** Upon completion of Phase 2
