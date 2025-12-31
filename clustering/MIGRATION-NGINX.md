# Migration from HAProxy to Nginx

This document explains the changes made when switching from HAProxy to Nginx as the load balancer.

## Summary of Changes

The clustering setup has been updated to use **Nginx** instead of HAProxy as the load balancer, providing:
- More flexible configuration
- Better integration with modern web stacks
- Native HTTPS/SSL support with HTTP/2
- WebSocket support out of the box
- Simpler configuration syntax
- Broader adoption and community support

## What Changed

### 1. Load Balancer Container

**Before (HAProxy):**
```yaml
loadbalancer:
  image: haproxy:3.0-alpine
  ports:
    - "8080:80"
    - "8404:8404"  # Stats page
  volumes:
    - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
```

**After (Nginx):**
```yaml
loadbalancer:
  image: nginx:1.27-alpine
  ports:
    - "8080:80"
    - "8081:8080"  # Status page
  volumes:
    - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - ./nginx/upstream.conf:/etc/nginx/conf.d/upstream.conf:ro
    - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    - ./nginx/status.conf:/etc/nginx/conf.d/status.conf:ro
```

### 2. Configuration Files

| Feature | HAProxy | Nginx |
|---------|---------|-------|
| **Config Location** | `haproxy/haproxy.cfg` | `nginx/*.conf` (modular) |
| **Sticky Sessions** | Cookie insertion (SERVERID) | Session cookie hash (JSESSIONID) |
| **Load Balancing** | Round-robin + cookie | Hash consistent |
| **Health Checks** | Active (every 2s) | Passive (max_fails) |
| **Stats/Monitoring** | Built-in dashboard | stub_status module |

### 3. Sticky Session Implementation

**HAProxy Approach:**
```
cookie SERVERID insert indirect nocache httponly
server node1 ... cookie node1
server node2 ... cookie node2
```
- HAProxy inserts its own cookie (SERVERID)
- Cookie value identifies the backend server
- Simple and reliable

**Nginx Approach:**
```nginx
hash $cookie_JSESSIONID consistent;
server xwiki-cluster-node1:8080;
server xwiki-cluster-node2:8080;
```
- Uses existing JSESSIONID cookie from XWiki
- Consistent hash ensures same node for same session
- No additional cookies needed

### 4. Health Checks

**HAProxy:**
- Active health checks every 2 seconds
- `option httpchk GET /`
- Marks DOWN after 3 failures
- Re-checks every 2 seconds

**Nginx:**
- Passive health checks (during normal traffic)
- `max_fails=3` - mark DOWN after 3 failures
- `fail_timeout=30s` - retry after 30 seconds
- More lightweight (no extra requests)

### 5. Monitoring

**HAProxy:**
- URL: `http://localhost:8404/stats`
- Rich HTML dashboard
- Real-time metrics with graphs
- Session details per backend
- Request queues

**Nginx:**
- URL: `http://localhost:8081/nginx_status`
- Simple text output (stub_status)
- Basic metrics: connections, requests
- Parseable by monitoring tools
- Lightweight

**Nginx Status Output:**
```
Active connections: 5
server accepts handled requests
 100 100 250
Reading: 0 Writing: 2 Waiting: 3
```

### 6. Configuration Syntax

**HAProxy (Single File):**
```haproxy
frontend xwiki_frontend
    bind *:80
    default_backend xwiki_backend

backend xwiki_backend
    balance roundrobin
    cookie SERVERID insert
    server node1 xwiki-node1:8080 cookie node1 check
    server node2 xwiki-node2:8080 cookie node2 check
```

**Nginx (Modular):**
```nginx
# upstream.conf
upstream xwiki_backend {
    hash $cookie_JSESSIONID consistent;
    server xwiki-cluster-node1:8080 max_fails=3 fail_timeout=30s;
    server xwiki-cluster-node2:8080 max_fails=3 fail_timeout=30s;
}

# default.conf
server {
    listen 80;
    location / {
        proxy_pass http://xwiki_backend;
        proxy_set_header Host $host;
        # ... more headers
    }
}
```

## Advantages of Nginx

### 1. Configuration Flexibility
- Modular configuration files
- Easy to extend and customize
- Include directives for organization

### 2. Feature Set
- **Built-in SSL/TLS**: Native HTTPS support with HTTP/2
- **WebSocket Support**: Full upgrade header support
- **Static File Serving**: Can serve static assets directly
- **Caching**: Built-in proxy caching capabilities
- **Rate Limiting**: Request and connection limits
- **Compression**: Gzip, brotli support

### 3. Performance
- Event-driven architecture
- Low memory footprint
- Efficient for static content
- Good at handling high connection counts

### 4. Ecosystem
- Larger community
- More third-party modules
- Better documentation
- Wider deployment experience

## Advantages of HAProxy

### 1. Load Balancing Focus
- Purpose-built for load balancing
- More sophisticated balancing algorithms
- Better connection queuing

### 2. Monitoring
- Superior built-in statistics
- Real-time dashboard
- More detailed metrics out of the box

### 3. Health Checks
- Active health checking
- More granular control
- Separate health check URIs

## Migration Steps

If you're migrating from an existing HAProxy setup:

### 1. Backup Current Configuration

```bash
# Backup existing setup
cp -r haproxy/ haproxy.backup/
cp docker-compose-cluster.yml docker-compose-cluster.yml.backup
```

### 2. Update Docker Compose

Replace the `loadbalancer` service definition with the new Nginx configuration (already done in this repository).

### 3. Create Nginx Configuration

The nginx configuration files are already provided:
- `nginx/nginx.conf` - Main configuration
- `nginx/upstream.conf` - Backend servers
- `nginx/default.conf` - Virtual host
- `nginx/status.conf` - Status page

### 4. Update Environment Variables

```bash
# In .env file, change:
HAPROXY_STATS_PORT=8404
# To:
NGINX_STATUS_PORT=8081
```

### 5. Test Configuration

```bash
# Start the cluster
docker compose -f docker-compose-cluster.yml up -d

# Test nginx configuration
docker exec xwiki-cluster-lb nginx -t

# Check status page
curl http://localhost:8081/nginx_status

# Verify XWiki access
curl -I http://localhost:8080/
```

### 6. Verify Sticky Sessions

```bash
# Make multiple requests and verify same backend
for i in {1..5}; do
  curl -v http://localhost:8080/ 2>&1 | grep -E "JSESSIONID|Set-Cookie"
done
```

### 7. Update Monitoring

If you have monitoring configured:
- Update scraping endpoints from `:8404/stats` to `:8081/nginx_status`
- Adjust parsing for nginx stub_status format
- Consider nginx-prometheus-exporter for Prometheus

### 8. Clean Up

```bash
# Remove old HAProxy directory
rm -rf haproxy/

# Remove HAProxy backup after verification
rm -rf haproxy.backup/
```

## Configuration Mapping

### Session Persistence

| Feature | HAProxy | Nginx |
|---------|---------|-------|
| Method | Cookie insertion | Cookie hash |
| Cookie name | SERVERID (custom) | JSESSIONID (XWiki) |
| Algorithm | Explicit mapping | Consistent hash |

### Load Balancing Algorithms

| Algorithm | HAProxy | Nginx |
|-----------|---------|-------|
| Round-robin | `balance roundrobin` | (default, or no directive) |
| Least connections | `balance leastconn` | `least_conn;` |
| IP hash | `balance source` | `ip_hash;` |
| Cookie hash | Cookie insertion + mapping | `hash $cookie_NAME consistent;` |

### Health Checks

| Feature | HAProxy | Nginx |
|---------|---------|-------|
| Type | Active (separate requests) | Passive (during traffic) |
| Interval | Configurable (e.g., 2s) | On-demand |
| Threshold | `rise 2 fall 3` | `max_fails=3` |
| Timeout | `fail_timeout` | `fail_timeout=30s` |

## Troubleshooting

### Nginx Won't Start

```bash
# Check configuration syntax
docker exec xwiki-cluster-lb nginx -t

# View error log
docker logs xwiki-cluster-lb
```

### Sessions Not Sticky

```bash
# Verify JSESSIONID cookie is being set
curl -v http://localhost:8080/ 2>&1 | grep JSESSIONID

# Check upstream configuration
docker exec xwiki-cluster-lb cat /etc/nginx/conf.d/upstream.conf

# Verify hash directive is present
grep "hash.*JSESSIONID" nginx/upstream.conf
```

### Backend Not Responding

```bash
# Check upstream servers
docker compose -f docker-compose-cluster.yml ps

# View nginx error log
docker exec xwiki-cluster-lb tail -f /var/log/nginx/error.log

# Test backend directly
curl http://localhost:8080/ -H "Host: xwiki-cluster-node1"
```

### Reload Configuration

After making changes to nginx config files:

```bash
# Reload without downtime
docker exec xwiki-cluster-lb nginx -s reload

# Or restart container (brief downtime)
docker compose -f docker-compose-cluster.yml restart loadbalancer
```

## Performance Tuning

### Worker Processes

```nginx
# nginx.conf
worker_processes auto;  # Use all CPU cores
worker_connections 4096;  # Connections per worker
```

### Buffer Sizes

```nginx
# default.conf
proxy_buffer_size 4k;
proxy_buffers 8 4k;
```

### Timeouts

```nginx
# default.conf
proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;
```

## Further Reading

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Nginx Load Balancing](https://docs.nginx.com/nginx/admin-guide/load-balancer/http-load-balancer/)
- [Nginx vs HAProxy Comparison](https://www.nginx.com/blog/nginx-vs-haproxy/)
- [XWiki Clustering](https://www.xwiki.org/xwiki/bin/view/Documentation/AdminGuide/Clustering/)
