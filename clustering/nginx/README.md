# Nginx Load Balancer Configuration

This directory contains the nginx configuration files for the XWiki cluster load balancer.

## Files

### nginx.conf
Main nginx configuration file containing:
- Worker process settings
- Event handling configuration
- HTTP module settings
- Logging configuration
- Gzip compression
- Security headers
- Global timeouts and limits

### upstream.conf
Backend server (upstream) configuration:
- XWiki cluster node definitions
- Load balancing algorithm (session cookie hashing)
- Health check parameters (max_fails, fail_timeout)
- Connection keepalive settings

**Key Setting:**
```nginx
hash $cookie_JSESSIONID consistent;
```
This ensures sticky sessions - users stay on the same XWiki node throughout their session.

### default.conf
Virtual host configuration:
- Main server block listening on port 80
- Proxy settings for backend communication
- WebSocket support
- Custom error pages
- Health check endpoint (/nginx-health)
- HTTPS configuration (commented, for production)

### status.conf
Status and monitoring endpoint:
- Nginx stub_status on port 8080
- Provides metrics: active connections, requests, etc.
- Health check endpoint for monitoring tools

## Load Balancing Strategy

### Sticky Sessions (Default)

Uses session cookie hashing for session persistence:
```nginx
upstream xwiki_backend {
    hash $cookie_JSESSIONID consistent;
    server xwiki-cluster-node1:8080;
    server xwiki-cluster-node2:8080;
    server xwiki-cluster-node3:8080;
}
```

**Why sticky sessions?**
- XWiki stores session data locally on each node
- Sessions are not replicated between nodes
- Users must stay on the same node for their entire session
- If a node fails, users on that node must re-login

### Alternative Strategies

**IP Hash (less reliable):**
```nginx
upstream xwiki_backend {
    ip_hash;
    server xwiki-cluster-node1:8080;
    ...
}
```
Issues: Doesn't work well with proxies, NAT, or mobile users.

**Least Connections:**
```nginx
upstream xwiki_backend {
    least_conn;
    server xwiki-cluster-node1:8080;
    ...
}
```
Issues: No session persistence, users will be routed to different nodes.

**Round-Robin:**
```nginx
upstream xwiki_backend {
    # No algorithm specified = round-robin
    server xwiki-cluster-node1:8080;
    ...
}
```
Issues: No session persistence.

## Health Checks

### Active Health Checks

Nginx monitors backend servers:
- `max_fails=3`: Mark server as down after 3 consecutive failures
- `fail_timeout=30s`: Try again after 30 seconds
- Automatic failover to healthy servers

### Passive Health Checks

Built into proxy requests:
- Connection timeout: 60s
- Send timeout: 60s
- Read timeout: 60s

If a server fails during a request, nginx automatically tries another server.

## Monitoring

### Nginx Status Page

Access: http://localhost:8081/nginx_status

Output example:
```
Active connections: 5
server accepts handled requests
 100 100 250
Reading: 0 Writing: 2 Waiting: 3
```

Metrics:
- **Active connections**: Current open connections
- **Accepts**: Total accepted connections
- **Handled**: Total handled connections
- **Requests**: Total client requests
- **Reading**: Connections reading request headers
- **Writing**: Connections writing responses
- **Waiting**: Idle keepalive connections

### Health Check Endpoint

Access: http://localhost:8081/health

Returns: `200 OK`

Use this endpoint for:
- Docker health checks
- Monitoring systems (Prometheus, Nagios, etc.)
- Load balancer health probes (AWS ALB, etc.)

## Customization

### Add/Remove Nodes

Edit `upstream.conf`:
```nginx
upstream xwiki_backend {
    hash $cookie_JSESSIONID consistent;

    server xwiki-cluster-node1:8080;
    server xwiki-cluster-node2:8080;
    server xwiki-cluster-node3:8080;
    server xwiki-cluster-node4:8080;  # Add new node
}
```

Reload nginx:
```bash
docker exec xwiki-cluster-lb nginx -s reload
```

### Change Load Balancing Algorithm

Edit `upstream.conf`:
```nginx
upstream xwiki_backend {
    least_conn;  # Change to least connections
    # or
    ip_hash;     # Change to IP hash
    # or remove for round-robin

    server xwiki-cluster-node1:8080;
    ...
}
```

### Adjust Timeouts

Edit `default.conf`:
```nginx
location / {
    proxy_connect_timeout 120s;  # Increase from 60s
    proxy_send_timeout 120s;
    proxy_read_timeout 120s;
    ...
}
```

### Enable HTTPS

1. Obtain SSL certificates (Let's Encrypt, commercial CA, etc.)

2. Uncomment HTTPS configuration in `default.conf`

3. Update certificate paths:
```nginx
server {
    listen 443 ssl http2;

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ...
}
```

4. Mount certificates in docker-compose:
```yaml
volumes:
  - ./ssl:/etc/nginx/ssl:ro
```

### Increase Upload Size

Edit `nginx.conf`:
```nginx
http {
    client_max_body_size 500M;  # Increase from 100M
    ...
}
```

### Custom Logging

Edit `nginx.conf`:
```nginx
http {
    log_format custom '$remote_addr - $request - $status '
                      'upstream: $upstream_addr '
                      'time: $request_time';

    access_log /var/log/nginx/access.log custom;
}
```

## Troubleshooting

### Check Configuration Syntax

```bash
docker exec xwiki-cluster-lb nginx -t
```

Expected output:
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### Reload Configuration

After making changes:
```bash
docker exec xwiki-cluster-lb nginx -s reload
```

### View Logs

```bash
# Access logs
docker exec xwiki-cluster-lb tail -f /var/log/nginx/access.log

# Error logs
docker exec xwiki-cluster-lb tail -f /var/log/nginx/error.log

# Or via docker compose
docker compose -f docker-compose-cluster.yml logs -f loadbalancer
```

### Verify Upstream Status

```bash
# Check which backends are active
docker exec xwiki-cluster-lb cat /etc/nginx/conf.d/upstream.conf
```

### Test Sticky Sessions

```bash
# Make multiple requests - should see same upstream each time
for i in {1..5}; do
  curl -v http://localhost:8080/ 2>&1 | grep -E "(JSESSIONID|upstream)"
done
```

### Common Issues

**502 Bad Gateway:**
- Backend servers are down
- Check: `docker compose ps`
- Check: XWiki node logs

**Session Lost:**
- Sticky sessions not working
- Check: JSESSIONID cookie is set
- Verify: `hash $cookie_JSESSIONID consistent;` in upstream.conf

**Slow Response:**
- Increase timeouts in default.conf
- Check backend server performance
- Review nginx access logs for slow requests

## Performance Tuning

### Worker Processes

Edit `nginx.conf`:
```nginx
worker_processes auto;  # Uses number of CPU cores
# or
worker_processes 4;     # Fixed number
```

### Worker Connections

Edit `nginx.conf`:
```nginx
events {
    worker_connections 8192;  # Increase from 4096
}
```

Total max connections = worker_processes × worker_connections

### Keepalive Connections

Edit `upstream.conf`:
```nginx
upstream xwiki_backend {
    ...
    keepalive 64;  # Increase from 32
    keepalive_requests 200;
    keepalive_timeout 120s;
}
```

### Buffer Sizes

Edit `default.conf`:
```nginx
location / {
    proxy_buffer_size 8k;     # Increase from 4k
    proxy_buffers 16 8k;      # Increase from 8 4k
    proxy_busy_buffers_size 16k;
    ...
}
```

## Security

### Restrict Status Page Access

Edit `status.conf`:
```nginx
location /nginx_status {
    stub_status on;
    allow 127.0.0.1;
    allow 172.16.0.0/12;  # Docker networks
    deny all;
}
```

### Rate Limiting

Add to `nginx.conf` (http block):
```nginx
http {
    limit_req_zone $binary_remote_addr zone=xwiki:10m rate=10r/s;
    ...
}
```

Add to `default.conf` (server block):
```nginx
location / {
    limit_req zone=xwiki burst=20;
    ...
}
```

### DDoS Protection

Add to `nginx.conf`:
```nginx
http {
    # Connection limits
    limit_conn_zone $binary_remote_addr zone=addr:10m;
    limit_conn addr 10;  # Max 10 connections per IP

    # Request rate limits
    limit_req_zone $binary_remote_addr zone=req:10m rate=50r/s;
    limit_req zone=req burst=100 nodelay;
}
```

## Further Reading

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Nginx Load Balancing](https://docs.nginx.com/nginx/admin-guide/load-balancer/http-load-balancer/)
- [Nginx Reverse Proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
- [Nginx Performance Tuning](https://www.nginx.com/blog/tuning-nginx/)
