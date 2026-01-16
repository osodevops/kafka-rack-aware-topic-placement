# Troubleshooting Guide

Common issues and their solutions when running the Kafka rack-aware topic placement PoC.

## Cluster Startup Issues

### Brokers Won't Start

**Symptom:** `./scripts/startup.sh` hangs or times out

**Causes & Solutions:**

1. **Insufficient Docker resources**
   ```bash
   # Check Docker resource allocation
   docker info | grep -E "CPUs|Memory"

   # Solution: Increase Docker Desktop memory to 8GB+
   # Docker Desktop > Settings > Resources > Memory
   ```

2. **Previous cluster state**
   ```bash
   # Clean up and restart
   ./scripts/teardown.sh --clean
   ./scripts/startup.sh
   ```

3. **Port conflicts**
   ```bash
   # Check if ports are in use
   lsof -i :9091-9095

   # Solution: Stop conflicting services or modify docker-compose.yml
   ```

### Brokers Unhealthy

**Symptom:** Brokers start but health checks fail

```bash
# Check broker logs
docker logs kafka-1 --tail 100
docker logs kafka-2 --tail 100
```

**Common log errors:**

1. **"Timed out waiting for connection"**
   - Network issue between containers
   - Solution: Restart Docker Desktop

2. **"Not enough live brokers"**
   - Quorum cannot be formed
   - Solution: Ensure all 5 brokers are starting

3. **"Cluster ID mismatch"**
   - Mixed state from previous runs
   - Solution: `./scripts/teardown.sh --clean`

### Container Keeps Restarting

```bash
# Check exit code and logs
docker inspect kafka-1 --format='{{.State.ExitCode}}'
docker logs kafka-1 2>&1 | tail -50
```

**Common causes:**
- Memory limit exceeded (increase Docker memory)
- Disk full (clean up Docker volumes)
- Configuration error (check environment variables)

## Topic Creation Issues

### "Topic already exists"

```bash
# List existing topics
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 --list

# Delete if needed
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --delete --topic my_topic
```

### "Replication factor larger than available brokers"

**Cause:** Trying to create topic with RF > number of healthy brokers

```bash
# Check healthy brokers
docker ps --format '{{.Names}} {{.Status}}' | grep kafka

# Solution: Wait for all brokers to be healthy, or reduce RF
```

### Invalid Replica Assignment

**Symptom:** Error creating topic with `--replica-assignment`

**Common causes:**

1. **Invalid broker ID**
   ```
   Error: Broker 6 does not exist
   ```
   Solution: Only use broker IDs 1-5

2. **Inconsistent partition count**
   ```
   Error: Partition assignment does not match partition count
   ```
   Solution: Ensure assignment string has correct number of partitions:
   ```bash
   # 6 partitions = 6 comma-separated groups
   --replica-assignment 1:2:3,2:3:1,3:1:2,1:2:3,2:3:1,3:1:2
   ```

3. **Inconsistent replication factor**
   ```
   Error: Each partition must have the same number of replicas
   ```
   Solution: Ensure each partition group has the same number of brokers

## Validation Failures

### "No poc_* topics found"

**Cause:** Topics haven't been created yet

```bash
# Create topics first
./scripts/create-topics.sh

# Then validate
./scripts/validate-placement.sh
```

### Replicas on Wrong Brokers

**Symptom:** Validation shows replicas on brokers 4 or 5

```bash
# Check topic details
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --describe --topic poc_orders

# Reassign to correct brokers
# Create reassignment.json and execute
docker exec kafka-1 kafka-reassign-partitions \
  --bootstrap-server kafka-1:29092 \
  --reassignment-json-file /tmp/reassignment.json \
  --execute
```

### Python Validator Connection Error

```
Error connecting to Kafka: NoBrokersAvailable
```

**Solutions:**

1. Check cluster is running:
   ```bash
   docker ps | grep kafka
   ```

2. Check bootstrap server is correct:
   ```bash
   python python/topic_validator.py --bootstrap-servers localhost:9091
   ```

3. Install dependencies:
   ```bash
   pip install -r python/requirements.txt
   ```

## Network Issues

### Cannot Connect from Host

**Symptom:** `kafka-console-producer` works from container but not from host

```bash
# Test from container (should work)
docker exec kafka-1 kafka-topics --bootstrap-server kafka-1:29092 --list

# Test from host (might fail)
kafka-topics --bootstrap-server localhost:9092 --list
```

**Solution:** Use the EXTERNAL listener port from host:
```bash
# From host, use localhost:909X
kafka-topics --bootstrap-server localhost:9092 --list
```

### Inter-Broker Communication Failure

```bash
# Check network
docker network inspect kafka-rack-aware-topic-placement_kafka-network

# Verify containers are on the network
docker network inspect kafka-rack-aware-topic-placement_kafka-network \
  --format '{{range .Containers}}{{.Name}} {{end}}'
```

## Performance Issues

### Slow Startup

**First run is slow** due to Docker image download (~1GB)

```bash
# Pre-pull image
docker pull confluentinc/cp-kafka:7.6.0
```

### High Memory Usage

```bash
# Check container memory
docker stats --no-stream

# If too high, reduce heap size in docker-compose.yml:
# KAFKA_HEAP_OPTS: "-Xmx512m -Xms512m"
```

### Disk Space Issues

```bash
# Check Docker disk usage
docker system df

# Clean up unused resources
docker system prune -a --volumes
```

## Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `NotLeaderOrFollower` | Leader election in progress | Wait and retry |
| `UnknownTopicOrPartition` | Topic doesn't exist | Create topic first |
| `InvalidReplicationFactor` | RF > available brokers | Reduce RF or add brokers |
| `TopicExistsException` | Topic already exists | Delete or use different name |
| `BrokerNotAvailableException` | Broker is down | Check broker health |
| `TimeoutException` | Operation timed out | Increase timeout or retry |
| `ClusterAuthorizationException` | (Shouldn't occur in PoC) | No auth configured |

## Getting Help

### Collect Diagnostic Information

```bash
# System info
docker info
docker version

# Container status
docker ps -a | grep kafka

# All broker logs
for i in 1 2 3 4 5; do
  echo "=== kafka-$i ===" >> kafka-logs.txt
  docker logs kafka-$i >> kafka-logs.txt 2>&1
done

# Topic details
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:29092 \
  --describe >> kafka-logs.txt
```

### Reset Everything

When all else fails:

```bash
# Stop all containers
docker compose down

# Remove all volumes
docker volume rm $(docker volume ls -q | grep kafka)

# Remove network
docker network rm kafka-rack-aware-topic-placement_kafka-network

# Start fresh
./scripts/startup.sh
```

## FAQ

**Q: Can I add more brokers?**
A: Yes, but you'll need to update `KAFKA_CONTROLLER_QUORUM_VOTERS` in all broker configs.

**Q: Can I change the rack assignments?**
A: Yes, modify `KAFKA_BROKER_RACK` in `docker-compose.yml` and restart.

**Q: How do I connect my application?**
A: Use `localhost:9091,localhost:9092,localhost:9093,localhost:9094,localhost:9095` as bootstrap servers.

**Q: Is this production-ready?**
A: No, this is a proof-of-concept. Production deployments need security, monitoring, and proper capacity planning.
