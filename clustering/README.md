# XWiki High Availability Cluster Setup

Complete Docker Compose configuration for running XWiki in a clustered, high-availability setup with load balancing.

## Architecture

```
                    ┌─────────────────┐
                    │    Nginx LB     │ :8080
                    │  (Sticky Sessions)
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
    ┌──────▼──────┐   ┌──────▼──────┐   ┌─────▼───────┐
    │ XWiki Node1 │   │ XWiki Node2 │   │ XWiki Node3 │
    │  (JGroups)  │◄──┤  (JGroups)  │◄──┤  (JGroups)  │
    └──────┬──────┘   └──────┬──────┘   └─────┬───────┘
           │                 │                 │
           │                 │                 │
           └─────────────────┼─────────────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
    ┌──────▼──────┐   ┌──────▼──────┐   ┌─────▼───────┐
    │ PostgreSQL  │   │    Solr     │   │   Shared    │
    │  Database   │   │   Search    │   │   Storage   │
    └─────────────┘   └─────────────┘   └─────────────┘
```

## Key Features

- **Load Balancing**: Nginx distributes traffic across multiple XWiki nodes
- **Sticky Sessions**: Session cookie hashing ensures users stay on the same node
- **High Availability**: Automatic failover if a node goes down
- **Horizontal Scaling**: Add/remove nodes dynamically
- **Cluster Communication**: JGroups synchronizes cache and events between nodes
- **Shared Storage**: All nodes access the same permanent directory
- **Health Monitoring**: Built-in health checks and nginx status page

## Prerequisites

- Docker Engine 20.10.16+
- Docker Compose v2.0+
- At least 8GB RAM (12GB+ recommended)
- 20GB free disk space
- Understanding of XWiki clustering concepts

## Quick Start

### Automated Setup (Recommended)

The easiest way to set up the cluster is using the automated setup script:

```bash
# 1. Navigate to clustering directory
cd clustering/

# 2. Run the automated setup script
./setup-cluster.sh

# The script will:
# - Check prerequisites (Docker, Docker Compose)
# - Download the correct Solr configuration for your XWiki version
# - Set up permissions automatically (macOS and Linux compatible)
# - Create secure .env file with random passwords
# - Start all services
# - Wait for health checks to pass
```

### Manual Setup

If you prefer manual setup or need custom configuration:

```bash
# 1. Navigate to clustering directory
cd clustering/

# 2. Download official Solr core configurations from Maven
XWIKI_VERSION="17.10.2"

# Create directory for official cores
mkdir -p solr-cores-official
cd solr-cores-official

# Download main search core (full XWiki schema)
curl -L -o search-core.zip \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-core-search/${XWIKI_VERSION}/xwiki-platform-search-solr-server-core-search-${XWIKI_VERSION}.zip"

# Download minimal core configuration (for extension_index, events, ratings)
curl -L -o minimal-core.zip \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-core-minimal/${XWIKI_VERSION}/xwiki-platform-search-solr-server-core-minimal-${XWIKI_VERSION}.zip"

# Extract cores
unzip -q search-core.zip
unzip -q minimal-core.zip -d minimal

# Return to clustering directory
cd ..

# 3. Create environment file
cp .env.example .env
# Edit .env and change passwords!

# 4. Start the cluster
docker compose -f docker-compose-cluster.yml up -d

# 5. Monitor startup
docker compose -f docker-compose-cluster.yml logs -f
```

**Note:** The cluster now uses official XWiki Solr core configurations downloaded from Maven, ensuring full compatibility and proper schema management.

## Access Points

| Service           | URL                          | Purpose                    |
|-------------------|------------------------------|----------------------------|
| XWiki (via LB)    | http://localhost:8080        | Main application access    |
| Nginx Status      | http://localhost:8081/nginx_status | Load balancer monitoring |
| Nginx Health      | http://localhost:8081/health | Health check endpoint      |
| Solr Admin        | http://localhost:8983/solr   | Search engine admin        |

## Configuration

### Number of Nodes

**2 Nodes (Recommended minimum for HA):**
```bash
# In docker-compose-cluster.yml, comment out web3 service
# web3:
#   ...
```

**3 Nodes (Recommended for production):**
```bash
# Default configuration - all 3 nodes enabled
```

**4+ Nodes:**
```bash
# Copy web3 service in docker-compose-cluster.yml and modify:
# - Container name: xwiki-cluster-node4
# - Hostname: xwiki-node4
# - JGroups bind address: xwiki-node4
# Add to nginx/upstream.conf:
# server xwiki-cluster-node4:8080 max_fails=3 fail_timeout=30s;
```

### Load Balancing Algorithms

Edit `nginx/upstream.conf`:

```nginx
upstream xwiki_backend {
    # Options:
    hash $cookie_JSESSIONID consistent;  # Default: Session cookie hash (sticky)
    # least_conn;                         # Send to least-busy server
    # ip_hash;                            # Hash client IP (basic stickiness)
    # (none)                              # Round-robin
```

### Sticky Sessions

**Session Cookie Hash (Default - Recommended):**
```nginx
hash $cookie_JSESSIONID consistent;
```
Uses XWiki's JSESSIONID cookie to route requests to the same node.

**IP Hash (Alternative):**
```nginx
ip_hash;
```
Note: Less reliable with proxies, NAT, or mobile users.

### JGroups Cluster Configuration

The cluster uses TCP-based JGroups for node communication. Configuration in `jgroups/tcp.xml`.

**Add/Remove nodes:**
```xml
<TCPPING initial_hosts="xwiki-cluster-node1[7800],xwiki-cluster-node2[7800],xwiki-cluster-node3[7800]"
```

**Alternative discovery methods for production:**
- **JDBC_PING**: Database-based discovery (recommended for cloud)
- **DNS_PING**: DNS-based discovery
- **KUBE_PING**: Kubernetes-based discovery

### Shared Storage

**Development (Docker volume):**
```yaml
volumes:
  xwiki-data-shared:
    name: xwiki-cluster-data-shared
```

**Production (NFS example):**
```yaml
volumes:
  xwiki-data-shared:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server.example.com,rw,nfsvers=4
      device: ":/xwiki/data"
```

**Other options:**
- GlusterFS
- Ceph
- Amazon EFS
- Azure Files
- Google Cloud Filestore

## Scaling Operations

### Add a Node

```bash
# 1. Update docker-compose-cluster.yml (copy web3, rename to web4)

# 2. Update jgroups/tcp.xml
# Add: xwiki-cluster-node4[7800]

# 3. Update nginx/upstream.conf
# Add: server xwiki-cluster-node4:8080 max_fails=3 fail_timeout=30s;

# 4. Reload nginx configuration
docker exec xwiki-cluster-lb nginx -s reload

# 5. Start new node
docker compose -f docker-compose-cluster.yml up -d --no-deps web4
```

### Remove a Node

```bash
# 1. Stop the node
docker compose -f docker-compose-cluster.yml stop web3

# 2. Update nginx/upstream.conf (remove or comment out the server line)

# 3. Reload nginx
docker exec xwiki-cluster-lb nginx -s reload

# 4. Remove container
docker compose -f docker-compose-cluster.yml rm web3
```

### Scale on Demand

```bash
# Stop a node during low traffic
docker compose -f docker-compose-cluster.yml stop web3

# Start during high traffic
docker compose -f docker-compose-cluster.yml start web3
```

## Monitoring

### Nginx Status Page

Access the status page in your browser or via curl:

```bash
# Browser
open http://localhost:8081/nginx_status

# Terminal
curl http://localhost:8081/nginx_status
```

**Sample output:**
```
Active connections: 5
server accepts handled requests
 100 100 250
Reading: 0 Writing: 2 Waiting: 3
```

**Metrics:**
- **Active connections**: Current open connections
- **Accepts**: Total accepted connections
- **Handled**: Total handled connections
- **Requests**: Total client requests
- **Reading**: Connections reading request
- **Writing**: Connections writing response
- **Waiting**: Idle keepalive connections

### Load Balancer Request Distribution

Check which backend node handled each request:

```bash
# View access logs with upstream information
docker compose -f docker-compose-cluster.yml logs loadbalancer --tail=20

# Count requests per node
docker exec xwiki-cluster-lb cat /var/log/nginx/xwiki-access.log | \
  grep -oE "upstream: [0-9.]+:[0-9]+" | sort | uniq -c

# Live monitoring (updates every 2 seconds)
watch -n 2 'docker exec xwiki-cluster-lb cat /var/log/nginx/xwiki-access.log | \
  grep -oE "upstream: [0-9.]+:[0-9]+" | sort | uniq -c'
```

**Sample output:**
```
 122 upstream: 172.18.0.4:8080    # Node 1
  38 upstream: 172.18.0.5:8080    # Node 2
```

**Note:** Due to sticky sessions (JSESSIONID cookie hashing), you'll see uneven distribution - this is expected and correct behavior.

### Response Time Analysis

```bash
# View response times from nginx logs
docker exec xwiki-cluster-lb cat /var/log/nginx/xwiki-access.log | \
  awk '{print $(NF-6), $(NF-2)}' | grep upstream_response_time | tail -20

# Average response time
docker exec xwiki-cluster-lb cat /var/log/nginx/xwiki-access.log | \
  awk '{print $(NF-2)}' | grep -v upstream_response_time | \
  awk '{sum+=$1; count++} END {print "Average:", sum/count, "seconds"}'
```

### Check Cluster Health

```bash
# View all service status
docker compose -f docker-compose-cluster.yml ps

# Check specific node health
docker inspect xwiki-cluster-node1 | grep -A 10 Health

# View XWiki logs
docker compose -f docker-compose-cluster.yml logs -f web1

# Check JGroups cluster membership
docker exec xwiki-cluster-node1 \
  grep "view =" /usr/local/tomcat/logs/catalina.out
```

### Performance Metrics

```bash
# Container resource usage
docker stats

# Database connections
docker exec xwiki-cluster-db \
  psql -U xwiki -d xwiki -c \
  "SELECT count(*) FROM pg_stat_activity WHERE datname='xwiki';"
```

## Maintenance

### Rolling Updates (Zero Downtime)

```bash
# 1. Update one node at a time
docker compose -f docker-compose-cluster.yml pull web1
docker compose -f docker-compose-cluster.yml up -d --no-deps web1

# 2. Wait for health check to pass
docker inspect xwiki-cluster-node1 | grep -A 5 Health

# 3. Repeat for other nodes
docker compose -f docker-compose-cluster.yml up -d --no-deps web2
# Wait for health...
docker compose -f docker-compose-cluster.yml up -d --no-deps web3
```

### Backup Strategy

**Database backup (same as single node):**
```bash
docker exec xwiki-cluster-db \
  pg_dump -U xwiki xwiki > backup_$(date +%Y%m%d).sql
```

**Shared storage backup:**
```bash
# Stop all XWiki nodes first (ensures consistency)
docker compose -f docker-compose-cluster.yml stop web1 web2 web3

# Backup
docker run --rm \
  -v xwiki-cluster-data-shared:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/xwiki-cluster-backup-$(date +%Y%m%d).tar.gz -C /data .

# Restart nodes
docker compose -f docker-compose-cluster.yml start web1 web2 web3
```

### Database Connection Pooling

PostgreSQL is configured for 200 max connections. Monitor usage:

```bash
# Current connections
docker exec xwiki-cluster-db \
  psql -U xwiki -d xwiki -c \
  "SELECT count(*) FROM pg_stat_activity;"

# Increase if needed (in docker-compose-cluster.yml)
# -c "max_connections=300"
```

## Troubleshooting

### Nodes Not Forming Cluster

**Symptoms:**
- Cache not synchronized between nodes
- Changes on one node not visible on others

**Check:**
```bash
# View JGroups cluster formation in logs
docker compose -f docker-compose-cluster.yml logs web1 | grep -i jgroups
docker compose -f docker-compose-cluster.yml logs web2 | grep -i jgroups

# Should see messages like:
# "GMS: address=xwiki-node1, cluster=xwiki, physical address=..."
# "received new view: [xwiki-node1|2] (2) [xwiki-node1, xwiki-node2]"
```

**Solution:**
```bash
# Verify network connectivity between nodes
docker exec xwiki-cluster-node1 ping xwiki-cluster-node2

# Check JGroups configuration
docker exec xwiki-cluster-node1 \
  cat /usr/local/tomcat/webapps/ROOT/WEB-INF/observation/remote/jgroups/tcp.xml

# Restart all XWiki nodes
docker compose -f docker-compose-cluster.yml restart web1 web2 web3
```

### Load Balancer Not Distributing Traffic

**Check Nginx upstream status:**
```bash
# View nginx logs
docker compose -f docker-compose-cluster.yml logs loadbalancer

# Test configuration
docker exec xwiki-cluster-lb nginx -t

# Check upstream configuration
docker exec xwiki-cluster-lb cat /etc/nginx/conf.d/upstream.conf

# Reload nginx after configuration changes
docker exec xwiki-cluster-lb nginx -s reload
```

**Verify sticky sessions:**
```bash
# Request should return same upstream each time with same JSESSIONID
curl -v http://localhost:8080/ 2>&1 | grep -E "(JSESSIONID|upstream)"
```

### XWiki Redirects Without Port (localhost:8080 → localhost)

**Symptoms:**
- Browser redirects from `http://localhost:8080/` to `http://localhost/bin/view/Main/`
- Port 8080 is lost in the redirect
- "Can't connect to server" error

**Root Cause:**
Nginx proxy headers not preserving the client-facing port.

**Solution:**
Verify `nginx/default.conf` contains:
```nginx
proxy_set_header Host $http_host;              # Includes port
proxy_set_header X-Forwarded-Host $http_host;  # Includes port
proxy_set_header X-Forwarded-Port 8080;        # Explicit port
```

**Test fix:**
```bash
# Restart load balancer
docker compose -f docker-compose-cluster.yml restart loadbalancer

# Verify redirect includes port
curl -I http://localhost:8080/ | grep Location
# Should show: Location: http://localhost:8080/bin/view/Main/
```

### Split-Brain Scenario

**Symptoms:**
- Cluster shows multiple separate views
- Data inconsistencies

**Prevention:**
- Ensure stable network between nodes
- Properly configure MERGE3 protocol
- Use database-based discovery (JDBC_PING) in production

**Recovery:**
```bash
# Stop all nodes
docker compose -f docker-compose-cluster.yml stop web1 web2 web3

# Start first node
docker compose -f docker-compose-cluster.yml start web1
# Wait for full startup

# Start remaining nodes one by one
docker compose -f docker-compose-cluster.yml start web2
docker compose -f docker-compose-cluster.yml start web3
```

### Shared Storage Permission Issues

```bash
# Check volume ownership
docker run --rm -v xwiki-cluster-data-shared:/data alpine ls -la /data

# Fix if needed (Tomcat runs as UID 999)
docker run --rm -v xwiki-cluster-data-shared:/data alpine chown -R 999:999 /data
```

### Solr Core Configuration Issues

**Symptoms:**
- Solr fails to start with errors about missing token filters (e.g., `stempelPolishStem`)
- Cores fail to load with schema errors
- XWiki can't connect to Solr during flavor installation

**Root Causes:**
1. **Missing analysis-extras module**: XWiki 16.6.0+ requires Solr's `analysis-extras` module for advanced language analyzers
2. **Incorrect core configurations**: Using minimal schemas instead of official XWiki configurations
3. **Wrong core naming**: XWiki 16.2.0+ expects `xwiki_search_9` instead of `xwiki`

**Solutions:**

**Enable analysis-extras module** (already configured in docker-compose-cluster.yml):
```yaml
environment:
  SOLR_MODULES: analysis-extras
```

**Verify all 4 cores are loaded:**
```bash
curl -s "http://localhost:8983/solr/admin/cores?action=STATUS" | \
  python3 -c "import sys, json; data=json.load(sys.stdin); \
  [print(f'{name}: {info[\"index\"][\"numDocs\"]} docs') for name, info in data['status'].items()]"
```

**Expected cores for XWiki 16.2.0+:**
- `xwiki_search_9` - Main search core (full schema)
- `xwiki_extension_index_9` - Extension management
- `xwiki_events_9` - Event stream
- `xwiki_ratings_9` - Page ratings

**Check Solr logs for errors:**
```bash
docker logs xwiki-cluster-solr 2>&1 | grep -i "error\|exception"
```

**Rebuild with official configurations:**
```bash
# Stop and remove everything
docker compose -f docker-compose-cluster.yml down -v

# Download official cores (see Manual Setup section)

# Restart
docker compose -f docker-compose-cluster.yml up -d
```

### High Database Connection Count

```bash
# Check connections per node
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -c \
  "SELECT application_name, count(*) FROM pg_stat_activity GROUP BY application_name;"

# Tune connection pool in XWiki (create custom xwiki.properties)
# hibernate.connection.pool_size=20
# hibernate.c3p0.min_size=5
# hibernate.c3p0.max_size=20
```

## Production Considerations

### Security

1. **Change all default passwords** in .env (or use `setup-cluster.sh` for auto-generation)
2. **Restrict Nginx status page access** (edit `nginx/status.conf`):
   ```nginx
   allow 127.0.0.1;  # Only localhost
   deny all;
   ```
3. **Disable external Solr port** (remove `ports:` section from solr service in docker-compose-cluster.yml)
4. **Use Docker secrets** instead of environment variables for production
5. **Enable HTTPS** with reverse proxy (nginx with SSL, Traefik, Caddy)
6. **Implement network segmentation** with multiple Docker networks
7. **Regular security updates:** Keep base images updated
   ```bash
   docker compose -f docker-compose-cluster.yml pull
   docker compose -f docker-compose-cluster.yml up -d
   ```

### Performance Tuning

1. **JVM Tuning per Node:**
   ```bash
   -Xmx4096m  # Increase heap based on available RAM
   -Xms2048m
   -XX:+UseG1GC
   -XX:MaxGCPauseMillis=200
   ```

2. **PostgreSQL Tuning:**
   ```bash
   max_connections=300
   shared_buffers=512MB
   effective_cache_size=2GB
   ```

3. **Nginx Tuning** (edit `nginx/nginx.conf`):
   ```nginx
   worker_processes auto;
   worker_connections 8192;
   keepalive_timeout 65;
   client_max_body_size 100M;  # For large file uploads
   ```

4. **Nginx Upstream Tuning** (edit `nginx/upstream.conf`):
   ```nginx
   keepalive 64;              # Connection pool to backends
   keepalive_requests 1000;   # Requests per connection
   keepalive_timeout 120s;    # Keep connections alive
   ```

5. **Solr Heap:**
   ```bash
   SOLR_HEAP=4g  # For large wikis
   ```

### Infrastructure Recommendations

**Minimum (Development/Testing):**
- 2 XWiki nodes
- 1 database server
- 1 Solr instance
- 1 load balancer
- 8GB RAM total

**Recommended (Production):**
- 3+ XWiki nodes
- PostgreSQL with replication (primary + replica)
- SolrCloud (multiple Solr nodes)
- 2+ load balancers (for LB redundancy)
- 16GB+ RAM total
- SSD storage for database and Solr

**Enterprise:**
- 5+ XWiki nodes across multiple availability zones
- PostgreSQL cluster (Patroni, pgpool-II)
- SolrCloud cluster (3+ nodes)
- External load balancer (AWS ALB, Azure Load Balancer)
- CDN for static assets
- Monitoring (Prometheus, Grafana)
- Distributed tracing (Jaeger, Zipkin)

### Disaster Recovery

1. **Automated backups** (database + shared storage)
2. **Off-site backup replication**
3. **Documented recovery procedures**
4. **Regular disaster recovery drills**
5. **Monitoring and alerting**

## Advanced Configurations

### External Load Balancer

For production, use external LB (AWS ALB, Azure Load Balancer, etc.) instead of containerized Nginx:

```yaml
# Remove loadbalancer service from docker-compose-cluster.yml
# Expose XWiki nodes on different host ports
services:
  web1:
    ports:
      - "8081:8080"
  web2:
    ports:
      - "8082:8080"
  web3:
    ports:
      - "8083:8080"
```

**Important:** Configure sticky sessions (session affinity) on the external load balancer using:
- Cookie-based routing (JSESSIONID cookie)
- Or source IP affinity (less reliable)

### Database Replication

```yaml
services:
  db-primary:
    image: postgres:17
    # Primary configuration

  db-replica:
    image: postgres:17
    # Replica configuration
    environment:
      POSTGRES_REPLICATION_MODE: replica
```

### SolrCloud (Distributed Solr)

Replace single Solr instance with SolrCloud cluster for high availability.

### Kubernetes Deployment

Convert to Kubernetes manifests:
- Deployment (XWiki nodes)
- StatefulSet (Database, Solr)
- Service (Load balancing)
- Ingress (External access)
- ConfigMap (Configurations)
- Secret (Credentials)

## Support and Documentation

- **XWiki Clustering**: https://www.xwiki.org/xwiki/bin/view/Documentation/AdminGuide/Clustering/
- **JGroups**: http://www.jgroups.org/manual5/index.html
- **Nginx**: https://nginx.org/en/docs/
- **Docker Compose**: https://docs.docker.com/compose/
- **XWiki Forum**: https://forum.xwiki.org/
- **Apache Solr**: https://solr.apache.org/guide/

## Related Files

- `setup-cluster.sh` - Automated cluster setup script
- `docker-compose-cluster.yml` - Main cluster configuration
  - Includes `solr-init` service (Alpine-based initialization container)
- `nginx/` - Nginx load balancer configuration
- `jgroups/tcp.xml` - JGroups cluster communication config
- `config/xwiki.properties` - XWiki configuration for remote Solr
- `solr-cores-official/` - Official XWiki Solr core configurations from Maven
- `SOLR-SETUP.md` - Detailed Solr configuration guide and troubleshooting
- `SETUP-ANLEITUNG.md` - German setup guide (manual)
- `CHANGELOG.md` - Version history and changes
- `MONITORING.md` - Monitoring and troubleshooting guide

## License

LGPL 2.1 - Same as XWiki
