# XWiki with PostgreSQL and Separate Solr - Setup Guide

This guide provides step-by-step instructions for running XWiki with PostgreSQL database and a separate (external) Solr search service using Docker Compose.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Accessing Services](#accessing-services)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Docker Engine 20.10.16 or higher
- Docker Compose v2.0 or higher
- At least 4GB of available RAM
- 10GB of free disk space

## Quick Start

```bash
# 1. Navigate to the xwiki-docker directory
cd /path/to/xwiki-docker

# 2. Download the XWiki Solr configuration JAR
# (Replace 17.10.2 with your XWiki version)
XWIKI_VERSION="17.10.2"
wget -P solr-init/ \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/${XWIKI_VERSION}/xwiki-platform-search-solr-server-data-${XWIKI_VERSION}.jar"

# 3. Set proper permissions for Solr
sudo chown -R 8983:8983 solr-init/

# 4. Create environment configuration
cp .env.example .env

# 5. Customize passwords in .env file
nano .env  # or use your preferred editor

# 6. Start all services
docker compose -f docker-compose-postgres-solr.yml up -d

# 7. Check logs to monitor startup
docker compose -f docker-compose-postgres-solr.yml logs -f
```

After startup completes (2-3 minutes), access XWiki at: http://localhost:8080

## Detailed Setup

### Step 1: Download Solr Configuration

The Solr service requires XWiki-specific configuration files. Download the appropriate JAR for your XWiki version:

```bash
# Create the solr-init directory if it doesn't exist
mkdir -p solr-init

# Download the Solr configuration JAR
# Use the same version as your XWiki installation
XWIKI_VERSION="17.10.2"  # Adjust to match your XWiki version

wget -P solr-init/ \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/${XWIKI_VERSION}/xwiki-platform-search-solr-server-data-${XWIKI_VERSION}.jar"
```

**Version Compatibility Matrix:**

| XWiki Version | Solr Config JAR Version |
|---------------|-------------------------|
| 17.x          | 17.10.2                 |
| 16.x          | 16.10.15                |
| 15.x          | 15.10.x                 |

**Important:** Always use the Solr configuration JAR that matches your XWiki version.

### Step 2: Set File Permissions

Solr runs as user ID 8983. The initialization scripts and data directories must be owned by this user:

```bash
# Set ownership for initialization directory
sudo chown -R 8983:8983 solr-init/

# Verify permissions
ls -la solr-init/
```

Expected output:
```
-rwxr-xr-x 1 8983 8983  solr-init.sh
-rw-r--r-- 1 8983 8983  xwiki-platform-search-solr-server-data-17.10.2.jar
```

### Step 3: Configure Environment Variables

```bash
# Copy the example environment file
cp .env.example .env

# Edit with your preferred editor
nano .env
```

**Recommended changes for production:**

```bash
# XWiki version to use
XWIKI_VERSION=17-postgres-tomcat  # or stable-postgres-tomcat

# Port configuration
XWIKI_PORT=8080

# PostgreSQL - CHANGE THESE PASSWORDS!
POSTGRES_ROOT_PASSWORD=YourSecureRootPassword123!
POSTGRES_USER=xwiki
POSTGRES_PASSWORD=YourSecureXwikiPassword456!
POSTGRES_DB=xwiki

# Solr heap size (adjust based on wiki size)
# Small wiki (<1000 pages): 512m
# Medium wiki (1000-10000 pages): 1g
# Large wiki (>10000 pages): 2g or more
SOLR_HEAP=1g
```

### Step 4: Start Services

```bash
# Start all services in detached mode
docker compose -f docker-compose-postgres-solr.yml up -d

# Watch the logs to monitor startup
docker compose -f docker-compose-postgres-solr.yml logs -f
```

**Expected startup sequence:**

1. PostgreSQL starts (10-15 seconds)
2. Solr starts and initializes XWiki core (30-45 seconds)
3. XWiki starts and connects to both services (60-90 seconds)

### Step 5: Initial XWiki Setup

1. Open your browser to http://localhost:8080
2. XWiki will display the Distribution Wizard
3. Click "Continue" to start the setup
4. Select the flavor (default: "Main Wiki")
5. Wait for the installation to complete
6. Create the admin user account

## Configuration

### Custom Configuration Files

To customize XWiki configuration files:

```bash
# Create a configuration directory
mkdir -p xwiki-config

# Copy default configuration from a running container
docker cp xwiki-web:/usr/local/tomcat/webapps/ROOT/WEB-INF/xwiki.cfg ./xwiki-config/
docker cp xwiki-web:/usr/local/tomcat/webapps/ROOT/WEB-INF/xwiki.properties ./xwiki-config/
docker cp xwiki-web:/usr/local/tomcat/webapps/ROOT/WEB-INF/hibernate.cfg.xml ./xwiki-config/

# Edit the files as needed
nano xwiki-config/xwiki.properties

# Uncomment the volume mounts in docker-compose-postgres-solr.yml
# Then restart the services
docker compose -f docker-compose-postgres-solr.yml restart web
```

### JVM Memory Configuration

Edit the `JAVA_OPTS` in docker-compose-postgres-solr.yml:

```yaml
environment:
  JAVA_OPTS: >-
    -Xmx4096m          # Maximum heap size (adjust based on available RAM)
    -Xms2048m          # Initial heap size
    -XX:+UseG1GC       # Use G1 garbage collector (recommended)
    -XX:MaxGCPauseMillis=200
    -Dfile.encoding=UTF-8
    -Djava.awt.headless=true
```

**Memory recommendations:**

| Wiki Size | XWiki Heap | Solr Heap | Total RAM |
|-----------|------------|-----------|-----------|
| Small     | 1-2 GB     | 512 MB    | 4 GB      |
| Medium    | 2-4 GB     | 1 GB      | 8 GB      |
| Large     | 4-8 GB     | 2 GB      | 16 GB     |

### Solr Configuration

Verify Solr is properly configured:

1. Access Solr admin UI: http://localhost:8983/solr
2. Check the "xwiki" core exists
3. Navigate to Core Admin → xwiki → Query
4. Run a test query: `*:*`

## Accessing Services

### Service URLs

| Service    | URL                              | Purpose                    |
|------------|----------------------------------|----------------------------|
| XWiki      | http://localhost:8080            | Main wiki application      |
| Solr UI    | http://localhost:8983/solr       | Search admin interface     |
| PostgreSQL | localhost:5432                   | Database (internal only)   |

### Docker Container Access

```bash
# Access XWiki container
docker exec -it xwiki-web bash

# Access PostgreSQL container
docker exec -it xwiki-postgres-db bash
psql -U xwiki -d xwiki

# Access Solr container
docker exec -it xwiki-solr bash
```

### View Logs

```bash
# All services
docker compose -f docker-compose-postgres-solr.yml logs -f

# Specific service
docker compose -f docker-compose-postgres-solr.yml logs -f web
docker compose -f docker-compose-postgres-solr.yml logs -f db
docker compose -f docker-compose-postgres-solr.yml logs -f solr
```

## Maintenance

### Backup

**Database Backup:**

```bash
# Create database backup
docker exec xwiki-postgres-db pg_dump -U xwiki xwiki > xwiki_backup_$(date +%Y%m%d).sql

# Restore from backup
cat xwiki_backup_20240101.sql | docker exec -i xwiki-postgres-db psql -U xwiki xwiki
```

**XWiki Data Backup:**

```bash
# Backup XWiki permanent directory
docker run --rm \
  -v xwiki-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/xwiki-data-backup-$(date +%Y%m%d).tar.gz -C /data .
```

**Solr Index Backup:**

```bash
# Backup Solr index
docker run --rm \
  -v xwiki-solr-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/solr-data-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### Updates

```bash
# Stop services
docker compose -f docker-compose-postgres-solr.yml down

# Pull latest images
docker compose -f docker-compose-postgres-solr.yml pull

# Start services with new images
docker compose -f docker-compose-postgres-solr.yml up -d
```

**Important:** Before updating, check the [XWiki Release Notes](https://www.xwiki.org/xwiki/bin/view/ReleaseNotes/) for migration steps.

### Reindexing Search

If search results are inconsistent, trigger a full reindex:

1. Login to XWiki as admin
2. Navigate to: Administration → Search → Indexing
3. Click "Index all pages"
4. Monitor progress in Solr UI: http://localhost:8983/solr/#/xwiki/query

## Troubleshooting

### Service Health Checks

```bash
# Check service status
docker compose -f docker-compose-postgres-solr.yml ps

# Check specific service health
docker inspect --format='{{.State.Health.Status}}' xwiki-web
docker inspect --format='{{.State.Health.Status}}' xwiki-postgres-db
docker inspect --format='{{.State.Health.Status}}' xwiki-solr
```

### Common Issues

#### Issue: XWiki Cannot Connect to Database

**Symptoms:**
- XWiki logs show connection errors
- Database container is running but XWiki can't connect

**Solution:**
```bash
# Check database is accepting connections
docker exec xwiki-postgres-db pg_isready -U xwiki

# Verify network connectivity
docker exec xwiki-web ping xwiki-postgres-db

# Check environment variables
docker exec xwiki-web env | grep DB_
```

#### Issue: Solr Core Not Found

**Symptoms:**
- XWiki logs show "Solr core 'xwiki' not found"
- Search functionality doesn't work

**Solution:**
```bash
# Check if JAR file exists and has correct permissions
ls -la solr-init/
# Should show: xwiki-platform-search-solr-server-data-*.jar owned by 8983:8983

# Recreate Solr container to reinitialize
docker compose -f docker-compose-postgres-solr.yml stop solr
docker compose -f docker-compose-postgres-solr.yml rm -f solr
docker volume rm xwiki-solr-data
docker compose -f docker-compose-postgres-solr.yml up -d solr
```

#### Issue: Out of Memory Errors

**Symptoms:**
- XWiki becomes unresponsive
- Logs show `java.lang.OutOfMemoryError`

**Solution:**
```bash
# Increase heap size in docker-compose-postgres-solr.yml
# Edit JAVA_OPTS for the web service:
#   -Xmx4096m  # Increase from 2048m
#   -Xms2048m  # Increase from 1024m

# Restart services
docker compose -f docker-compose-postgres-solr.yml restart web
```

#### Issue: Slow Performance

**Checklist:**
- [ ] Check available system resources: `docker stats`
- [ ] Increase JVM heap sizes for XWiki and Solr
- [ ] Verify PostgreSQL has adequate resources
- [ ] Check disk I/O performance
- [ ] Review XWiki logs for slow queries
- [ ] Consider moving Solr index to SSD

#### Issue: Permission Denied Errors

**Solution:**
```bash
# Fix Solr permissions
sudo chown -R 8983:8983 solr-init/

# Fix XWiki data permissions (if needed)
docker run --rm -v xwiki-data:/data alpine chown -R 999:999 /data
```

### Getting Help

- **XWiki Forum:** https://forum.xwiki.org/
- **XWiki JIRA (Docker):** https://jira.xwiki.org/browse/XDOCKER
- **Docker Image Docs:** https://hub.docker.com/_/xwiki
- **XWiki Documentation:** https://www.xwiki.org/xwiki/bin/view/Documentation/

## Production Considerations

### Security Hardening

1. **Change default passwords** in `.env` file
2. **Enable Solr authentication:**
   ```yaml
   environment:
     SOLR_AUTH_TYPE: basic
     SOLR_AUTHENTICATION_OPTS: "-Dbasicauth=admin:SecurePassword"
   ```
3. **Remove Solr port exposure** from docker-compose.yml (only needed for debugging)
4. **Use Docker secrets** instead of environment variables:
   ```yaml
   secrets:
     - db_password
     - db_root_password
   ```
5. **Enable HTTPS** with reverse proxy (nginx, Traefik, Caddy)

### Performance Optimization

1. **Use SSD storage** for Solr index and PostgreSQL data
2. **Tune PostgreSQL** configuration for your workload
3. **Enable XWiki caching** in xwiki.properties
4. **Monitor resource usage** with `docker stats`
5. **Regular maintenance:** vacuum PostgreSQL, optimize Solr index

### High Availability

For production deployments, consider:
- PostgreSQL replication (primary/replica)
- XWiki clustering (multiple web nodes)
- Shared Solr instance (SolrCloud)
- Load balancer (HAProxy, nginx)
- External storage for volumes (NFS, Ceph)

## License

This configuration is provided under the LGPL 2.1 license, same as XWiki.
