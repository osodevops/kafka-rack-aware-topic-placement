#!/bin/bash
# =============================================================================
# Cruise Control Rebalance Trigger Script for Strimzi
# =============================================================================
# Triggers a KafkaRebalance using Strimzi's CRD-based approach.
#
# Usage:
#   ./trigger-rebalance.sh [--approve]
#
# Options:
#   --approve    Automatically approve the rebalance proposal
# =============================================================================

set -e

NAMESPACE="kafka"
REBALANCE_NAME="rebalance-poc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
AUTO_APPROVE=false
if [[ "$1" == "--approve" ]]; then
    AUTO_APPROVE=true
fi

echo "=========================================="
echo " Cruise Control Rebalance (Strimzi)"
echo "=========================================="
echo ""

# Check if KafkaRebalance already exists
EXISTING=$(kubectl get kafkarebalance "$REBALANCE_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null || true)

if [ -n "$EXISTING" ]; then
    echo "Existing KafkaRebalance found:"
    kubectl get kafkarebalance "$REBALANCE_NAME" -n "$NAMESPACE"
    echo ""

    # Get current status
    STATUS=$(kubectl get kafkarebalance "$REBALANCE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")

    case "$STATUS" in
        "ProposalReady")
            echo "Status: Proposal is ready for approval"
            echo ""
            echo "Proposal summary:"
            kubectl get kafkarebalance "$REBALANCE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.optimizationResult}' 2>/dev/null | head -50
            echo ""

            if $AUTO_APPROVE; then
                echo "Auto-approving rebalance..."
                kubectl annotate kafkarebalance "$REBALANCE_NAME" strimzi.io/rebalance=approve -n "$NAMESPACE" --overwrite
                echo "Rebalance approved. Monitor with: kubectl get kafkarebalance $REBALANCE_NAME -n $NAMESPACE -w"
            else
                echo "To approve this proposal, run:"
                echo "  kubectl annotate kafkarebalance $REBALANCE_NAME strimzi.io/rebalance=approve -n $NAMESPACE"
                echo ""
                echo "Or run this script with --approve flag"
            fi
            ;;
        "Rebalancing")
            echo "Status: Rebalance is in progress"
            echo ""
            echo "Monitor progress with:"
            echo "  kubectl get kafkarebalance $REBALANCE_NAME -n $NAMESPACE -w"
            ;;
        "Ready")
            echo "Status: Previous rebalance completed successfully"
            echo ""
            echo "To trigger a new rebalance, delete and recreate the resource:"
            echo "  kubectl delete kafkarebalance $REBALANCE_NAME -n $NAMESPACE"
            echo "  kubectl apply -f ../topics/kafka-rebalance.yaml -n $NAMESPACE"
            ;;
        "NotReady")
            echo "Status: Rebalance failed or not ready"
            echo ""
            echo "Check the error:"
            kubectl get kafkarebalance "$REBALANCE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].message}'
            echo ""
            echo ""
            echo "To retry, delete and recreate the resource:"
            echo "  kubectl delete kafkarebalance $REBALANCE_NAME -n $NAMESPACE"
            echo "  kubectl apply -f ../topics/kafka-rebalance.yaml -n $NAMESPACE"
            ;;
        *)
            echo "Status: $STATUS"
            echo ""
            echo "Waiting for proposal generation..."
            kubectl get kafkarebalance "$REBALANCE_NAME" -n "$NAMESPACE" -w &
            WATCH_PID=$!
            sleep 30
            kill $WATCH_PID 2>/dev/null || true
            ;;
    esac
else
    echo "Creating new KafkaRebalance resource..."
    kubectl apply -f "$PROJECT_DIR/topics/kafka-rebalance.yaml" -n "$NAMESPACE"
    echo ""
    echo "KafkaRebalance created. Waiting for proposal..."
    echo ""

    # Wait for proposal to be ready
    echo "Monitoring status (Ctrl+C to exit)..."
    kubectl get kafkarebalance "$REBALANCE_NAME" -n "$NAMESPACE" -w &
    WATCH_PID=$!

    # Wait up to 2 minutes for proposal
    for i in {1..24}; do
        sleep 5
        STATUS=$(kubectl get kafkarebalance "$REBALANCE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Pending")
        if [ "$STATUS" == "ProposalReady" ]; then
            kill $WATCH_PID 2>/dev/null || true
            echo ""
            echo "Proposal is ready!"
            echo ""

            if $AUTO_APPROVE; then
                echo "Auto-approving rebalance..."
                kubectl annotate kafkarebalance "$REBALANCE_NAME" strimzi.io/rebalance=approve -n "$NAMESPACE" --overwrite
                echo "Rebalance approved."
            else
                echo "To approve, run:"
                echo "  kubectl annotate kafkarebalance $REBALANCE_NAME strimzi.io/rebalance=approve -n $NAMESPACE"
            fi
            break
        fi
    done

    kill $WATCH_PID 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo " Rebalance Status"
echo "=========================================="
kubectl get kafkarebalance -n "$NAMESPACE"
echo ""
