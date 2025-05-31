#!/bin/bash
# KnowVerse Distributed Architecture Testing Quick Start Guide
# This script provides examples of the most common testing commands

echo "KnowVerse Distributed Architecture Testing Quick Start"
echo "======================================================"
echo

echo "1. Start a single distributed server node (with all components)"
echo "   Command: bin/distributed_server"
echo "   This starts a server with the distributed architecture enabled"
echo
echo "2. Start a 3-node distributed development cluster (in separate terminals)"
echo "   Command: bin/distributed_dev -n 3"
echo "   This starts 3 nodes on ports 3000, 3001, and 3002"
echo
echo "3. Use the standard Rails development server with distributed mode"
echo "   Command: DISTRIBUTED_NODE_ID=test-node-1 DISTRIBUTED_AUTO_START=true bin/dev"
echo "   This uses the standard development server with distributed architecture"
echo

echo "4. Run a basic fault tolerance test"
echo "   Command: bin/test_distributed --mode fault --nodes 5"
echo "   This tests the resilience of a 5-node cluster"
echo

echo "5. Run performance benchmarks with 1 million vectors"
echo "   Command: bin/test_distributed --mode perf --vectors 1000000 --queries 1000"
echo "   This measures performance with 1 million vectors and 1000 queries"
echo

echo "6. Test specific aspects:"
echo "   - Latency: bin/test_distributed --mode latency"
echo "   - Throughput: bin/test_distributed --mode throughput"
echo "   - Memory usage: bin/test_distributed --mode memory"
echo "   - Sharding: bin/test_distributed --mode sharding"
echo

echo "7. Simulate specific failure conditions:"
echo "   - Network partition: bundle exec rake distributed:simulate:network_partition[node1,node2]"
echo "   - Node crash: bundle exec rake distributed:simulate:node_crash[node1]"
echo "   - Log corruption: bundle exec rake distributed:simulate:log_corruption[node1,severe]"
echo

echo "8. Generate test data:"
echo "   Command: bundle exec rake distributed:simulate:generate_data[5,10000]"
echo "   This creates 5 test organizations with 10,000 documents each"
echo

echo "9. Run more targeted tests:"
echo "   - Test specific dimensions: bin/test_distributed --dimensions 384,1536,2048"
echo "   - More concurrent users: bin/test_distributed --mode throughput --organizations 20"
echo

echo "10. For detailed documentation, see testing/DISTRIBUTED_TESTING.md"
echo

# Uncomment to actually execute commands
# read -p "Would you like to start a 3-node distributed cluster now? (y/n) " -n 1 -r
# echo
# if [[ $REPLY =~ ^[Yy]$ ]]
# then
#     bin/distributed_dev -n 3
# fi
