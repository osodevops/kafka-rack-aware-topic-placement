#!/usr/bin/env python3
"""
Kafka Topic Placement Validator

Validates that all poc_* topics have replicas only on the allowed broker set.
"""

import argparse
import sys

from confluent_kafka.admin import AdminClient
from tabulate import tabulate


# Default configuration
DEFAULT_BOOTSTRAP_SERVERS = "localhost:9092"
DEFAULT_ALLOWED_BROKERS = {1, 2, 3}
DEFAULT_TOPIC_PREFIX = "poc_"


def get_admin_client(bootstrap_servers: str) -> AdminClient:
    """Create and return a Kafka AdminClient."""
    conf = {
        "bootstrap.servers": bootstrap_servers,
        "socket.timeout.ms": 5000,
    }
    return AdminClient(conf)


def get_cluster_metadata(admin: AdminClient):
    """Fetch cluster metadata."""
    return admin.list_topics(timeout=10)


def get_broker_info(metadata) -> list[dict]:
    """Extract broker information from cluster metadata."""
    brokers = []
    for broker_id, broker in metadata.brokers.items():
        brokers.append(
            {
                "id": broker_id,
                "host": broker.host,
                "port": broker.port,
            }
        )
    return sorted(brokers, key=lambda x: x["id"])


def validate_topic_placement(
    metadata,
    topic_prefix: str,
    allowed_brokers: set[int],
) -> dict:
    """
    Validate that all topics matching the prefix have replicas only on allowed brokers.

    Returns a dictionary with validation results.
    """
    results = {
        "topics_checked": 0,
        "partitions_checked": 0,
        "violations": [],
        "topic_details": [],
        "passed": True,
    }

    for topic_name, topic_metadata in metadata.topics.items():
        # Skip internal topics and non-matching topics
        if topic_name.startswith("__") or not topic_name.startswith(topic_prefix):
            continue

        results["topics_checked"] += 1
        topic_info = {
            "name": topic_name,
            "partitions": [],
            "has_violations": False,
        }

        for partition_id, partition in topic_metadata.partitions.items():
            results["partitions_checked"] += 1

            replicas = set(partition.replicas)
            leader = partition.leader
            isr = set(partition.isrs)

            partition_info = {
                "id": partition_id,
                "leader": leader,
                "replicas": sorted(replicas),
                "isr": sorted(isr),
                "violations": [],
            }

            # Check for violations
            invalid_brokers = replicas - allowed_brokers
            if invalid_brokers:
                violation = {
                    "topic": topic_name,
                    "partition": partition_id,
                    "invalid_brokers": sorted(invalid_brokers),
                    "all_replicas": sorted(replicas),
                }
                results["violations"].append(violation)
                partition_info["violations"] = sorted(invalid_brokers)
                topic_info["has_violations"] = True
                results["passed"] = False

            topic_info["partitions"].append(partition_info)

        # Sort partitions by ID
        topic_info["partitions"].sort(key=lambda x: x["id"])
        results["topic_details"].append(topic_info)

    return results


def print_broker_info(brokers: list[dict]):
    """Print broker information in a table."""
    print("\n=== Cluster Brokers ===\n")
    table_data = [[b["id"], b["host"], b["port"]] for b in brokers]
    print(tabulate(table_data, headers=["ID", "Host", "Port"], tablefmt="simple"))


def print_validation_results(results: dict, allowed_brokers: set[int]):
    """Print validation results."""
    print("\n=== Validation Results ===\n")

    print(f"Allowed brokers: {sorted(allowed_brokers)}")
    print(f"Topics checked:  {results['topics_checked']}")
    print(f"Partitions checked: {results['partitions_checked']}")
    print(f"Violations found: {len(results['violations'])}")

    if results["topic_details"]:
        print("\n=== Topic Details ===\n")

        for topic in results["topic_details"]:
            status = "PASS" if not topic["has_violations"] else "FAIL"
            print(f"\nTopic: {topic['name']} [{status}]")

            table_data = []
            for p in topic["partitions"]:
                violation_str = ""
                if p["violations"]:
                    violation_str = f"Invalid: {p['violations']}"

                table_data.append(
                    [
                        p["id"],
                        p["leader"],
                        ",".join(map(str, p["replicas"])),
                        ",".join(map(str, p["isr"])),
                        violation_str,
                    ]
                )

            print(
                tabulate(
                    table_data,
                    headers=["Partition", "Leader", "Replicas", "ISR", "Violations"],
                    tablefmt="simple",
                )
            )

    if results["violations"]:
        print("\n=== Violations Detail ===\n")
        for v in results["violations"]:
            print(f"  - Topic: {v['topic']}, Partition: {v['partition']}")
            print(f"    Replicas: {v['all_replicas']}")
            print(f"    Invalid brokers: {v['invalid_brokers']}")

    print("\n" + "=" * 50)
    if results["passed"]:
        print("VALIDATION PASSED")
        print(f"All {results['topics_checked']} topics use only brokers {sorted(allowed_brokers)}")
    else:
        print("VALIDATION FAILED")
        print(f"Found {len(results['violations'])} placement violations")
    print("=" * 50 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Validate Kafka topic placement for rack-aware assignment"
    )
    parser.add_argument(
        "--bootstrap-servers",
        default=DEFAULT_BOOTSTRAP_SERVERS,
        help=f"Kafka bootstrap servers (default: {DEFAULT_BOOTSTRAP_SERVERS})",
    )
    parser.add_argument(
        "--prefix",
        default=DEFAULT_TOPIC_PREFIX,
        help=f"Topic prefix to validate (default: {DEFAULT_TOPIC_PREFIX})",
    )
    parser.add_argument(
        "--allowed-brokers",
        default=",".join(map(str, DEFAULT_ALLOWED_BROKERS)),
        help=f"Comma-separated list of allowed broker IDs (default: {','.join(map(str, DEFAULT_ALLOWED_BROKERS))})",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Only output pass/fail result",
    )

    args = parser.parse_args()

    # Parse allowed brokers
    allowed_brokers = {int(b.strip()) for b in args.allowed_brokers.split(",")}

    try:
        admin = get_admin_client(args.bootstrap_servers)
        metadata = get_cluster_metadata(admin)
    except Exception as e:
        print(f"Error connecting to Kafka: {e}", file=sys.stderr)
        sys.exit(2)

    if not args.quiet:
        brokers = get_broker_info(metadata)
        print_broker_info(brokers)

    results = validate_topic_placement(metadata, args.prefix, allowed_brokers)

    if results["topics_checked"] == 0:
        if not args.quiet:
            print(f"\nNo topics found with prefix '{args.prefix}'")
            print("Run ./scripts/create-topics.sh to create sample topics.")
        sys.exit(0)

    if args.quiet:
        if results["passed"]:
            print("PASSED")
            sys.exit(0)
        else:
            print(f"FAILED: {len(results['violations'])} violations")
            sys.exit(1)
    else:
        print_validation_results(results, allowed_brokers)
        sys.exit(0 if results["passed"] else 1)


if __name__ == "__main__":
    main()
