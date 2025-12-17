# KnowVerse Distributed Architecture Testing Framework

This testing framework provides comprehensive tools for evaluating the fault tolerance, performance, and scalability of KnowVerse's distributed architecture with Raft consensus.

## Overview

The framework consists of several components:

1. **Fault Tolerance Testing**: Test resilience against node failures, network partitions, and data corruption.
2. **Performance Benchmarking**: Measure query latency, throughput, and memory usage at scale.
3. **Memory Profiling**: Analyze memory consumption patterns for vector operations.
4. **Simulation Tools**: Simulate failures and adverse conditions in a controlled environment.

## Getting Started

### Prerequisites

- Ruby 3.2+ with bundler
- Rails 8.0+
- PostgreSQL with pgvector extension
- Memory profiling gems (installed via Gemfile)

### Installation

All required dependencies are included in the Gemfile. Run:

```bash
bundle install
```

## Fault Tolerance Testing

The fault tolerance test suite evaluates the distributed system's ability to maintain consistency and availability during failure conditions.

### Running the Tests

```bash
# Run with default settings (5 nodes)
bundle exec rake distributed:test:fault_tolerance

# Run with custom node count
DISTRIBUTED_NODE_COUNT=7 bundle exec rake distributed:test:fault_tolerance

# Run and display detailed report
DISPLAY_REPORT=true bundle exec rake distributed:test:fault_tolerance
```

### Test Scenarios

The test suite includes the following scenarios:

1. **Leader Failure**: Tests the system's ability to elect a new leader when the current leader fails.
2. **Operation During Election**: Verifies operations continue during leader transitions.
3. **Network Partitions**: Tests both minority and majority partitions.
4. **Data Corruption**: Tests recovery from corrupted logs and state files.
5. **Cascading Failures**: Tests recovery from multiple simultaneous node failures.

### Test Reports

A detailed Markdown report is generated at `tmp/fault_tolerance_report.md` with:
- Summary statistics across all tests
- Recovery time metrics
- Data consistency measurements
- Detailed scenario results

## Performance Benchmarking

The performance benchmarking suite measures search performance, throughput, and memory usage at scale.

### Running Benchmarks

```bash
# Run all benchmarks with default settings
bundle exec rake distributed:test:performance

# Run specific benchmark type
BENCHMARK_TYPE=latency bundle exec rake distributed:test:performance
BENCHMARK_TYPE=throughput bundle exec rake distributed:test:performance
BENCHMARK_TYPE=memory bundle exec rake distributed:test:performance
BENCHMARK_TYPE=sharding bundle exec rake distributed:test:performance

# Configure benchmark parameters
DISTRIBUTED_NODE_COUNT=5 VECTOR_COUNT=1000000 QUERY_COUNT=1000 bundle exec rake distributed:test:performance

# Test specific vector dimensions
DIMENSIONS=384,1536,2048 bundle exec rake distributed:test:performance

# Run benchmark and display report
DISPLAY_REPORT=true bundle exec rake distributed:test:performance
```

### Benchmark Metrics

Benchmarks measure and report:

1. **Latency**: 
   - Average, P95, and P99 query latency
   - Latency comparisons between single-node and distributed architecture
   - Latency by vector dimensions

2. **Throughput**:
   - Maximum queries per second
   - Throughput with different concurrent user counts
   - Throughput vs. latency tradeoffs

3. **Memory Usage**:
   - Memory per vector by dimension
   - Memory usage per organization
   - Projection of memory requirements for large-scale deployments

4. **Sharding Efficiency**:
   - Shard distribution across nodes
   - Rebalancing time when nodes join/leave
   - Hot spot identification and analysis

### Benchmark Reports

Two reports are generated:
- `tmp/benchmarks/performance_results.json`: Raw benchmark data
- `tmp/benchmarks/performance_report.md`: Formatted Markdown report

## Simulation Tools

The simulation tools allow for controlled failure testing in development and staging environments.

### Available Simulations

```bash
# Network partition simulation
bundle exec rake distributed:simulate:network_partition[node1,node2]

# Node crash simulation
bundle exec rake distributed:simulate:node_crash[node1]

# Log corruption simulation
bundle exec rake distributed:simulate:log_corruption[node1,severe]

# Generate test data
bundle exec rake distributed:simulate:generate_data[5,10000]
```

## Memory Profiling

The memory profiler analyzes memory usage patterns, particularly for vector operations at scale.

### Using the Memory Profiler

```ruby
# In a Rails console or test
profiler = Distributed::Benchmark::MemoryProfiler.new

# Profile a specific operation
profiler.profile("load_organization") do
  service.distributed_index_store.load_organization(org_id)
end

# Profile memory usage per organization
results = profiler.profile_organization_memory(print_report: true)

# Generate a report
report = profiler.generate_report
File.write("memory_report.md", report)
```

## Creating Custom Tests

You can extend the testing framework with custom scenarios:

1. Add test cases to `spec/services/distributed/fault_tolerance_spec.rb`
2. Create custom benchmark configurations in `lib/distributed/benchmark`
3. Add new simulation tools in `lib/tasks/distributed_test.rake`

## Best Practices

- Run tests in a dedicated test environment
- Start with small-scale tests before scaling up
- Run memory-intensive tests on machines with sufficient RAM
- Use benchmark results to guide optimization efforts
- Set up monitoring for long-running tests

## Example Workflow

A typical testing workflow might include:

1. Run fault tolerance tests to verify basic resilience
2. Use simulation tools to test specific failure modes
3. Run performance benchmarks with increasing scale
4. Monitor memory usage with the profiler
5. Analyze reports to identify optimization opportunities
6. Make improvements and repeat the cycle

## Understanding Reports

The testing framework generates comprehensive reports for both fault tolerance and performance testing. Key metrics to watch:

- **Recovery time**: How quickly the system recovers from failures
- **Data consistency**: Whether data remains consistent after recovery
- **Query latency**: Response time for search queries
- **Maximum throughput**: Queries per second at scale
- **Memory efficiency**: Memory usage per vector/document
- **Sharding balance**: Distribution of data across nodes

## Troubleshooting

If you encounter issues:

- Check log files for detailed error messages
- Ensure all nodes are properly configured
- Verify environment variables are correctly set
- Ensure sufficient memory for large vector indexes
- Increase timeouts for long-running tests
