# XWiki Cluster Architecture

Detailed architecture documentation for the XWiki high-availability cluster setup.

## Architecture Diagram

```
┌───────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL ACCESS                              │
│                                                                           │
│                        http://localhost:8080                              │
└───────────────────────────────────┬───────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Nginx Load Balancer                           │
│                                                                         │
│  • Layer 7 (HTTP/HTTPS) reverse proxy and load balancing               │
│  • Session cookie hash sticky sessions (JSESSIONID)                    │
│  • Health checks via max_fails (3) and fail_timeout (30s)              │
│  • Automatic failover on node failure                                  │
│  • Status page on :8081/nginx_status                                   │
│                                                                         │
│  Algorithm: Session cookie hash (consistent hashing)                   │
│  Backends: xwiki-node1, xwiki-node2, xwiki-node3                       │
└────────┬──────────────────────┬──────────────────────┬─────────────────┘
         │                      │                      │
         │ Balance              │ Balance              │ Balance
         │ Requests             │ Requests             │ Requests
         ▼                      ▼                      ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  XWiki Node 1   │    │  XWiki Node 2   │    │  XWiki Node 3   │
│                 │    │                 │    │                 │
│  Tomcat 10      │    │  Tomcat 10      │    │  Tomcat 10      │
│  Java 21        │    │  Java 21        │    │  Java 21        │
│  Port: 8080     │    │  Port: 8080     │    │  Port: 8080     │
│                 │    │                 │    │                 │
│  JVM: 2GB heap  │    │  JVM: 2GB heap  │    │  JVM: 2GB heap  │
│                 │    │                 │    │                 │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         │                      │                      │
         └──────────┬───────────┴───────────┬──────────┘
                    │                       │
                    │ JGroups Cluster       │
                    │ Communication         │
                    │ (TCP Port 7800)       │
                    │                       │
         ┌──────────▼───────────────────────▼──────────┐
         │          Cluster Synchronization            │
         │                                             │
         │  • Cache invalidation events                │
         │  • Wiki events (page changes, etc.)         │
         │  • Cluster membership management            │
         │  • State synchronization                    │
         │                                             │
         │  Protocol: JGroups TCP                      │
         │  Discovery: TCPPING (static node list)      │
         │  Transport: TCP on port 7800                │
         └─────────────────────────────────────────────┘
                    │                       │
         ┌──────────┴───────┬───────────────┴──────────┐
         │                  │                          │
         ▼                  ▼                          ▼
┌─────────────────┐ ┌──────────────────┐    ┌────────────────┐
│   PostgreSQL    │ │   Apache Solr    │    │ Shared Storage │
│   Database      │ │   Search Engine  │    │                │
│                 │ │                  │    │  XWiki Data    │
│  Port: 5432     │ │  Port: 8983      │    │  Attachments   │
│  Version: 17    │ │  Version: 9      │    │  Extensions    │
│                 │ │                  │    │  Config Files  │
│  Connections:   │ │  Index: xwiki    │    │                │
│    max: 200     │ │  Heap: 1-2GB     │    │  Volume:       │
│    active: ~60  │ │                  │    │  xwiki-data    │
│    (20/node)    │ │  Cores:          │    │  -shared       │
│                 │ │    • xwiki       │    │                │
│  Database:      │ │                  │    │  Access Mode:  │
│    • xwiki      │ │  Features:       │    │  Read/Write    │
│    • UTF-8      │ │    • Full-text   │    │  from all      │
│    • C.UTF-8    │ │    • Faceting    │    │  nodes         │
│                 │ │    • Suggestions │    │                │
└─────────────────┘ └──────────────────┘    └────────────────┘
         │                  │                          │
         │                  │                          │
         ▼                  ▼                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Docker Network Bridge                    │
│                  (xwiki-cluster-network)                    │
│                                                             │
│  Network: 172.x.x.x/16                                      │
│  DNS: Automatic container name resolution                  │
│  Isolation: Internal cluster communication only            │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Nginx Load Balancer

**Purpose:**
- Distribute incoming HTTP/HTTPS requests across XWiki nodes
- Maintain session affinity (sticky sessions)
- Monitor node health and route around failures
- Provide observability through status page

**Configuration:**
```
Location: nginx/

nginx.conf:
  - Main configuration (workers, logging, gzip)
  - Global settings and includes

upstream.conf:
  - Backend server definitions
  - Load balancing algorithm (session cookie hash)
  - Health check parameters (max_fails, fail_timeout)

default.conf:
  - Virtual host listening on port 80
  - Proxy headers and settings
  - WebSocket support
  - Error handling

status.conf:
  - Status page on port 8080 (mapped to :8081)
  - nginx_status endpoint for metrics
```

**Key Features:**
- **Sticky Sessions**: Uses JSESSIONID cookie hash (consistent hashing)
- **Health Checks**: Passive via max_fails=3, fail_timeout=30s
- **Status Page**: stub_status on :8081/nginx_status
- **Compression**: Gzip for text/html, application/json, etc.
- **WebSocket Support**: Full HTTP/1.1 upgrade support

### 2. XWiki Application Nodes

**Purpose:**
- Serve web requests
- Process wiki logic
- Maintain user sessions
- Synchronize with other nodes via JGroups

**Configuration per Node:**
```
Memory: 2GB heap (configurable)
CPU: Shares host CPU
Network: Internal cluster network
Storage: Shared volume mounted at /usr/local/xwiki

Environment:
  - DB_HOST: xwiki-cluster-db
  - INDEX_HOST: xwiki-cluster-solr
  - JGroups bind address: unique per node
```

**JGroups Cluster Communication:**
```
Protocol: TCP (better for Docker than UDP multicast)
Port: 7800
Discovery: TCPPING (static node list)

Configuration: jgroups/tcp.xml
  - Reliable message delivery
  - Failure detection (FD_SOCK, FD_ALL)
  - Network partition handling (MERGE3)
  - Cache synchronization
```

**Session Management:**
- Sessions are node-local (not replicated)
- HAProxy ensures same user → same node
- If node fails, user must re-login

### 3. PostgreSQL Database

**Purpose:**
- Store all wiki content (pages, attachments metadata, users, etc.)
- Provide ACID guarantees
- Handle concurrent access from all nodes

**Tuning for Cluster:**
```
max_connections: 200 (increased from default 100)
  - ~20 connections per XWiki node
  - ~20 for background tasks
  - Buffer for spikes

shared_buffers: 256MB
  - Cache for frequently accessed data
  - Reduces disk I/O

Connection Pooling:
  - Each XWiki node maintains pool
  - Typically 10-20 connections per node
```

**Important:**
- Single database shared by all nodes
- No database replication in this setup (see Production section for that)
- Bottleneck if not properly sized

### 4. Apache Solr Search

**Purpose:**
- Provide full-text search across all wiki content
- Index pages, attachments, comments, etc.
- Support faceted search and auto-suggestions

**Configuration:**
```
Heap: 1-2GB (adjustable based on wiki size)
Index: xwiki core
Storage: Persistent volume

Initialization:
  - Configured via JAR file on first start
  - Creates xwiki core with schema
  - Loads XWiki-specific config
```

**Indexing Strategy:**
- Nodes send index updates to Solr
- Solr maintains single shared index
- Real-time search across all content

### 5. Shared Storage

**Purpose:**
- Store XWiki permanent directory
- Share data between all nodes
- Persist configuration, attachments, extensions

**Critical Files Shared:**
```
/usr/local/xwiki/data/
  ├── cache/              # File caches
  ├── extension/          # Installed extensions
  ├── jobs/               # Background job data
  ├── locks/              # Distributed locks
  ├── observation/        # Event data
  └── store/              # File attachments
```

**Access Pattern:**
- All nodes read/write concurrently
- NFS recommended for production
- Docker volume for development

**Performance Considerations:**
- Network latency affects performance
- Use SSD-backed storage
- Consider local cache for frequently accessed files

## Data Flow

### 1. User Request Flow

```
User → Nginx → XWiki Node → Database/Solr → Response
  1. User makes HTTP request
  2. Nginx checks JSESSIONID cookie
  3. Hashes cookie to select consistent node (or picks node if new session)
  4. XWiki sets JSESSIONID cookie in response
  5. XWiki processes request
  6. Fetches data from PostgreSQL/Solr if needed
  7. Response sent back through Nginx
```

### 2. Cache Synchronization Flow

```
Node 1 modifies page → JGroups event → All nodes invalidate cache

  1. User edits page on Node 1
  2. Node 1 updates database
  3. Node 1 sends JGroups cache invalidation event
  4. Nodes 2 and 3 receive event
  5. Nodes 2 and 3 clear cached version
  6. Next read on Nodes 2/3 fetches fresh data
```

### 3. Search Indexing Flow

```
Node updates page → Solr index updated → Available to all nodes

  1. Page modified on any node
  2. Node sends document to Solr for indexing
  3. Solr updates index (asynchronous)
  4. Search queries from any node see updated index
```

## Failure Scenarios

### Scenario 1: Single Node Failure

```
Before:
  Nginx → [Node1✓, Node2✓, Node3✓]
          Sessions: 33% | 33% | 33%

Node2 Fails:
  Nginx detects failure (3 consecutive failed requests)
  New requests go to Node1 and Node3
  Node2 sessions are lost (users must re-login)

After:
  Nginx → [Node1✓, Node2✗, Node3✓]
          Sessions: 50% | 0% | 50%

Recovery:
  Node2 restarts
  Nginx marks Node2 healthy after successful request
  New sessions distributed to Node2
```

**User Impact:**
- Users on failed node: Must re-login
- Users on other nodes: No impact

### Scenario 2: Database Failure

```
Impact: ALL nodes cannot serve requests
Mitigation: PostgreSQL replication (not in this setup)

Recovery:
  1. Restore database from backup
  2. All nodes reconnect automatically
```

### Scenario 3: Network Partition

```
Cluster splits: [Node1, Node2] | [Node3]

Without proper handling:
  - Split-brain: Two independent clusters
  - Data inconsistencies

With MERGE3 protocol:
  - Detects partition
  - Attempts to merge sub-clusters
  - Larger partition wins
  - Smaller partition syncs state
```

## Scaling Patterns

### Horizontal Scaling (Add Nodes)

```
Steps:
  1. Add new node to docker-compose-cluster.yml
  2. Update JGroups TCPPING with new node
  3. Update Nginx upstream.conf
  4. Reload Nginx: docker exec xwiki-cluster-lb nginx -s reload
  5. Start new node
  6. Nginx automatically routes traffic

Benefits:
  - Increased capacity
  - Better fault tolerance
  - Maintained performance under load

Limits:
  - Database becomes bottleneck (~5-7 nodes)
  - Shared storage I/O limits
  - Network bandwidth
```

### Vertical Scaling (Bigger Nodes)

```
Options:
  - Increase JVM heap (JAVA_OPTS -Xmx)
  - Add more CPU to host
  - Faster storage (SSD)

Benefits:
  - Handle more concurrent users per node
  - Faster response times
  - Better cache hit rates

Limits:
  - JVM pause times increase with heap size
  - Single node still a failure point
  - More expensive
```

## Monitoring Points

### 1. Nginx Metrics
- Active connections
- Request rate (accepts/handled/requests)
- Connection states (reading/writing/waiting)
- Upstream response times
- Error rate (4xx, 5xx in access logs)

### 2. XWiki Node Metrics
- JVM heap usage
- GC pause times
- Request latency
- Thread pool utilization
- Cache hit rates

### 3. Database Metrics
- Active connections
- Query performance
- Lock waits
- Replication lag (if applicable)
- Disk I/O

### 4. Solr Metrics
- Query rate
- Index size
- Query latency
- Cache hit ratio
- Commit rate

### 5. Cluster Health
- JGroups view (membership)
- Message lag
- Network latency between nodes
- Shared storage I/O

## Security Architecture

### Network Isolation

```
External: User → Nginx only
Internal: All services on private network

Exposed Ports:
  - 8080: Nginx (XWiki access)
  - 8081: Nginx status (should be firewalled in production)
  - 8983: Solr (development only, remove in production)

Internal-only:
  - 5432: PostgreSQL
  - 7800: JGroups cluster
  - 8080: XWiki nodes (not exposed)
```

### Authentication & Authorization

- **Nginx**: Optional IP restriction for status page
- **XWiki**: Application-level auth (users, groups, permissions)
- **PostgreSQL**: Username/password (should use secrets)
- **Solr**: Optional basic auth (recommended for production)

### Data Protection

- **In Transit**: Add HTTPS termination at Nginx (SSL configuration included)
- **At Rest**: Encrypt volumes (LUKS, cloud provider encryption)
- **Backups**: Encrypted backup storage

## Performance Characteristics

### Latency

```
User Request → Response Time:
  - Nginx overhead: <1ms
  - XWiki processing: 50-500ms (depends on page complexity)
  - Database query: 1-50ms
  - Solr query: 10-100ms
  - Network: <1ms (internal)

Total typical: 100-600ms
```

### Throughput

```
Requests per Second (approximate):
  - Single node: 10-50 req/s
  - 2 nodes: 20-100 req/s
  - 3 nodes: 30-150 req/s

Limits:
  - Database: 200-500 req/s
  - Solr: 100-300 queries/s
  - Network: 1Gbps = ~10K small requests/s
```

### Capacity Planning

```
Users per Node:
  - Concurrent: 50-100
  - Total: 500-1000

Database Sizing:
  - Small wiki: 1-10GB
  - Medium wiki: 10-100GB
  - Large wiki: 100GB-1TB

Solr Index:
  - Typically 10-20% of content size
  - 1000 pages ≈ 100MB index
```

## Comparison: Single Node vs Cluster

| Aspect | Single Node | 3-Node Cluster |
|--------|-------------|----------------|
| **Availability** | 99% (single point of failure) | 99.9% (tolerates 1 node failure) |
| **Capacity** | 50 concurrent users | 150 concurrent users |
| **Response Time** | 100-300ms | 100-300ms (same) |
| **Failure Recovery** | Manual restart required | Automatic failover |
| **Maintenance** | Downtime required | Rolling updates |
| **Cost** | Low | Medium (3x nodes + LB) |
| **Complexity** | Simple | Complex (cluster sync) |
| **Scalability** | Vertical only | Horizontal + vertical |

## Use Cases

### Single Node (Adequate For):
- Small teams (<50 users)
- Development/testing
- Non-critical wikis
- Budget constraints

### Cluster (Required For):
- Medium/large teams (>100 users)
- Production systems with SLA
- 24/7 availability requirements
- Geographic distribution
- Compliance (redundancy requirements)

## Further Reading

- [XWiki Clustering Documentation](https://www.xwiki.org/xwiki/bin/view/Documentation/AdminGuide/Clustering/)
- [JGroups Manual](http://www.jgroups.org/manual5/index.html)
- [HAProxy Configuration Manual](https://docs.haproxy.org/)
- [PostgreSQL High Availability](https://www.postgresql.org/docs/current/high-availability.html)
- [SolrCloud Documentation](https://solr.apache.org/guide/solr/latest/deployment-guide/solrcloud.html)
