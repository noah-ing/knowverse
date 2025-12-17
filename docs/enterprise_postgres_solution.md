# KnowVerse Enterprise PostgreSQL Infrastructure

This document outlines a comprehensive enterprise-grade PostgreSQL infrastructure solution for KnowVerse, addressing both immediate connection issues and establishing a scalable, high-availability environment.

## 1. IPv6/IPv4 Connection Issue Analysis

### Current Issues

1. **Connection Termination**: PostgreSQL server accepts initial connections but terminates them immediately
2. **Protocol Conflict**: System attempts IPv6 connections (`::1`) while PostgreSQL expects IPv4 (`127.0.0.1`)
3. **Multi-Layer Problem**: Issues span socket/DNS resolution, ActiveRecord adapters, and connection handlers
4. **Environment Inconsistency**: Problem appears in Windows environments but works in others

### Current Mitigations

1. **Adapter Patches**: Initializer that forces IPv4 for PG and ActiveRecord connections
2. **Retry Logic**: Exponential backoff for failed connections
3. **Configuration Changes**: Explicit 127.0.0.1 usage in database.yml and environment variables

### Root Cause Analysis

The core issue appears to be:
- PostgreSQL server inconsistently handles dual-stack IPv6/IPv4 connections
- Windows-specific socket behavior creates race conditions
- Server configuration permits connections initially but terminates them based on protocol mismatch
- Connection pooling and keepalive settings may be improperly configured

## 2. Enterprise PostgreSQL Architecture

### High-Availability Cluster Design

![PostgreSQL HA Architecture](postgres_ha_diagram.png)

#### Primary-Replica Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│  PostgreSQL     │     │  PostgreSQL     │     │  PostgreSQL     │
│  Primary        │◄────┤  Replica 1      │◄────┤  Replica 2      │
│                 │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        ▲                       ▲                       ▲
        │                       │                       │
        │                       │                       │
┌───────┴───────────────┬───────┴───────────┬──────────┴──────────┐
│                       │                   │                      │
│   pgBouncer           │  Patroni/etcd     │  HAProxy            │
│   Connection Pool     │  Orchestration    │  Load Balancing     │
│                       │                   │                      │
└───────────────────────┴───────────────────┴──────────────────────┘
                ▲                   ▲                  ▲
                │                   │                  │
                └────────┬──────────┘                  │
                         │                             │
┌────────────────────────┴─────────────────────────────┴───┐
│                                                           │
│                 KnowVerse Application                     │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

#### Components

1. **Primary Node**: Main PostgreSQL server handling read/write operations
   - Configuration optimized for vector operations and high concurrency
   - Focus on durability and consistency

2. **Replica Nodes**: Multiple read-replicas for scaling read operations
   - Synchronous commit for critical data
   - Asynchronous replication for other data
   - Automatic failover capability

3. **Connection Pooling**: pgBouncer for efficient connection management
   - Prevents connection thrashing
   - Manages connection lifecycle
   - Handles connection recycling
   - Solves IPv6/IPv4 connection issues at pool level

4. **Orchestration Layer**: Patroni with etcd for cluster management
   - Automatic leader election
   - Health monitoring
   - Failover coordination

5. **Load Balancing**: HAProxy for intelligent request routing
   - Read/write split routing
   - Health-based routing
   - Connection balancing

### Deployment Options

1. **Self-managed Option**:
   - Deploy on dedicated servers or VMs
   - Configure with Infrastructure as Code (Terraform/Ansible)
   - Implement proper network isolation

2. **Cloud-managed Option**:
   - AWS: RDS for PostgreSQL with Multi-AZ
   - Azure: Azure Database for PostgreSQL with HA
   - GCP: Cloud SQL for PostgreSQL with HA

3. **Containerized Option**:
   - Kubernetes with StatefulSets
   - Persistent volume claims for durability
   - Operator-based management (Zalando Postgres Operator)

## 3. Technical Implementation

### Connection Management

Create a comprehensive connection management layer:

```ruby
# lib/database/connection_manager.rb
module Database
  class ConnectionManager
    include Singleton
    
    def initialize
      @pool_config = load_pool_config
      @connection_metrics = ConnectionMetrics.new
    end
    
    def connection
      with_circuit_breaker do
        retrieve_connection
      end
    end
    
    private
    
    def retrieve_connection
      # Force IPv4 using connection pooling
      # Implement protocol verification before returning
    end
    
    def with_circuit_breaker
      # Prevent connection cascading failures
      # Track connection health metrics
    end
  end
end
```

### PostgreSQL Configuration

Optimize PostgreSQL configuration for KnowVerse's vector operations:

```ini
# postgresql.conf key settings
listen_addresses = '0.0.0.0'         # Listen on all IPv4 addresses
max_connections = 200
shared_buffers = 4GB
work_mem = 64MB
maintenance_work_mem = 512MB
effective_io_concurrency = 200  # SSD optimization
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
random_page_cost = 1.1  # SSD optimization
effective_cache_size = 12GB

# Vector search optimizations
max_locks_per_transaction = 128
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05

# Connection stability
tcp_keepalives_idle = 60
tcp_keepalives_interval = 10
tcp_keepalives_count = 6
```

### Connection Pooling Configuration

Configure pgBouncer for optimal connection management:

```ini
# pgbouncer.ini
[databases]
knowverse_production = host=127.0.0.1 port=5432 dbname=knowverse_production

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 100
reserve_pool_size = 25
reserve_pool_timeout = 5
server_reset_query = DISCARD ALL
server_check_query = select 1
server_check_delay = 30
```

### Rails Configuration

Update Rails configuration for connecting through pgBouncer:

```yaml
# config/database.yml
production:
  primary: &primary_production
    adapter: postgresql
    encoding: unicode
    host: <%= ENV.fetch("DB_POOL_HOST") { "pgbouncer.knowverse.internal" } %>
    port: <%= ENV.fetch("DB_POOL_PORT") { 6432 } %>
    database: knowverse_production
    username: <%= ENV["KNOWVERSE_DATABASE_USERNAME"] %>
    password: <%= ENV["KNOWVERSE_DATABASE_PASSWORD"] %>
    pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 25 } %>
    checkout_timeout: 5
    reaping_frequency: 10
    reconnect: true
    prepared_statements: false  # Important for pgBouncer
    advisory_locks: false       # Important for pgBouncer
    variables:
      statement_timeout: <%= ENV.fetch("STATEMENT_TIMEOUT") { 15000 } %>
```

### Network Configuration

Configure pg_hba.conf to properly handle IPv4/IPv6 protocols:

```
# pg_hba.conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# IPv4 local connections:
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             10.0.0.0/8              scram-sha-256

# IPv6 local connections:
host    all             all             ::1/128                 scram-sha-256

# Allow replication connections
host    replication     replicator      10.0.0.0/8              scram-sha-256
```

## 4. Monitoring and Operations

### Key Metrics to Monitor

1. **Connection Metrics**:
   - Active connections
   - Connection latency
   - Connection failures
   - Connection pool usage

2. **Performance Metrics**:
   - Query execution time
   - Transaction throughput
   - Lock contention
   - Index usage efficiency
   - Vector search performance

3. **Replication Metrics**:
   - Replication lag
   - WAL generation rate
   - Replica synchronization status

4. **Resource Metrics**:
   - CPU usage
   - Memory usage
   - Disk I/O
   - Network traffic

### Operational Procedures

#### Backup Strategy

1. **Daily Base Backups**:
   - Full database dumps to object storage
   - Retention period: 30 days

2. **Continuous WAL Archiving**:
   - Archive WAL segments to object storage
   - Retention period: 7 days

3. **Point-in-time Recovery Testing**:
   - Monthly recovery drills
   - Validate restore procedures

#### Maintenance Procedures

1. **Regular VACUUM ANALYZE**:
   - Scheduled maintenance window
   - Target tables with high churn

2. **Index Maintenance**:
   - Rebuild fragmented indexes
   - REINDEX CONCURRENTLY for minimal disruption

3. **Statistics Updates**:
   - Refresh planner statistics
   - Analyze vector tables specifically

#### Failover Procedures

1. **Automatic Failover**:
   - Patroni-managed leader election
   - Health check thresholds

2. **Manual Failover**:
   - Documented step-by-step process
   - Command reference for operators

3. **Post-Failover Validation**:
   - Data integrity checks
   - Application behavior verification

## 5. Implementation Plan

### Phase 1: Immediate Connection Fix

1. Enhance existing IPv4 adapter with better protocol detection
2. Implement connection validation before use
3. Add circuit breaker pattern to prevent cascading failures
4. Create comprehensive connection logging

### Phase 2: Standalone pgBouncer Deployment

1. Set up pgBouncer instance for connection pooling
2. Configure proper pool mode and limits
3. Update application configuration
4. Implement monitoring for connection pool

### Phase 3: High-Availability Cluster

1. Deploy primary PostgreSQL node with optimized configuration
2. Set up replica nodes with replication
3. Implement Patroni/etcd for orchestration
4. Configure HAProxy for load balancing

### Phase 4: Monitoring and Operations

1. Implement comprehensive monitoring
2. Document operational procedures
3. Create runbooks for common scenarios
4. Set up alerting for critical conditions

## 6. Conclusion

This enterprise PostgreSQL solution addresses both the immediate IPv6/IPv4 connectivity issues and provides a scalable, resilient database infrastructure. By implementing connection pooling, proper protocol handling, and a high-availability architecture, KnowVerse will have a robust database foundation for future growth.

The multi-layered approach ensures:
- Immediate resolution of connection issues
- Improved performance through connection pooling
- High availability through replication and automatic failover
- Operational excellence through monitoring and maintenance
- Scalability for increasing data and query loads

Implementation will proceed in phases, starting with immediate connection fixes and progressing to the full high-availability architecture.
