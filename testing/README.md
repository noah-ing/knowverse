# KnowVerse Testing Framework

## Overview

This directory contains the KnowVerse testing framework, which focuses on comprehensive testing of the distributed architecture with Raft consensus. The framework is designed to validate fault tolerance, measure performance, and optimize resource usage.

## Contents

- `DISTRIBUTED_TESTING.md` - Comprehensive documentation for the testing framework
- `quick_start.sh` - Quick reference guide with common testing commands

## Features

The testing framework provides several key capabilities:

### 1. Fault Tolerance Testing

Test the system's resilience against:
- Leader node failures
- Network partitions 
- Data corruption
- Cascading failures
- Split-brain scenarios

### 2. Performance Benchmarking

Measure key metrics like:
- Query latency (single-node vs. distributed)
- Maximum throughput
- Concurrent user capacity
- Memory usage at scale

### 3. Simulation Tools

Create controlled test environments with:
- Network partition simulation
- Node crash simulation
- Log corruption simulation
- Large-scale test data generation

### 4. Test Automation

Run tests through convenient interfaces:
- Command-line test runner
- Multi-node development setup
- Rake tasks for specific test cases

## Getting Started

1. **Start a multi-node development environment**:
   ```
   bin/distributed_dev -n 3
   ```
   This starts 3 nodes on ports 3000, 3001, and 3002.

2. **Run fault tolerance tests**:
   ```
   bin/test_distributed --mode fault
   ```

3. **Run performance benchmarks**:
   ```
   bin/test_distributed --mode perf
   ```

4. **View quick reference**:
   ```
   testing/quick_start.sh
   ```

## Directory Structure

- `bin/` - Executable scripts
  - `test_distributed` - Main test runner
  - `distributed_dev` - Multi-node development setup
- `lib/distributed/` - Implementation of testing utilities
  - `testing/` - Fault simulation and metrics
  - `benchmark/` - Performance testing tools
- `spec/services/distributed/` - Test cases
- `lib/tasks/` - Rake tasks for testing

## Documentation

See `testing/DISTRIBUTED_TESTING.md` for comprehensive documentation on using the test framework.
