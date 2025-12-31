# XWiki with PostgreSQL and Separate Solr

Complete Docker Compose setup for running XWiki with PostgreSQL database and an external Solr search service.

## Available Setups

### 1. Single Node Setup (This Directory)
Standard XWiki installation with PostgreSQL and Solr.

### 2. High Availability Cluster Setup (`clustering/`)
**Production-ready XWiki cluster** with:
- Multiple XWiki nodes (2-3) for high availability
- Nginx load balancer with sticky sessions
- Automatic failover and horizontal scaling
- JGroups cluster communication
- **Automated setup script** (`setup-cluster.sh`)

👉 **For production environments, see [`clustering/`](clustering/) directory**

## Directory Contents

```
postgres-solr-setup/
├── README.md                          # This file
├── SETUP-POSTGRES-SOLR.md            # Detailed setup documentation
├── docker-compose-postgres-solr.yml  # Single node configuration
├── .env.example                      # Environment variables template
├── setup-postgres-solr.sh            # Automated setup script
├── solr-init/                        # Solr initialization files
│   ├── README.md                     # Solr setup instructions
│   └── solr-init.sh                  # Solr initialization script
└── clustering/                       # ⭐ High Availability Cluster Setup
    ├── README.md                     # Cluster documentation
    ├── setup-cluster.sh              # Automated cluster setup
    ├── docker-compose-cluster.yml    # Cluster configuration (uses official images only!)
    ├── CHANGELOG.md                  # Version history
    ├── MONITORING.md                 # Monitoring guide
    ├── nginx/                        # Load balancer config
    └── jgroups/                      # Cluster communication
```

## Quick Start

### Automated Setup (Recommended)

```bash
cd postgres-solr-setup
./setup-postgres-solr.sh
```

The script will:
1. Check prerequisites (Docker, Docker Compose)
2. Download the XWiki Solr configuration JAR
3. Set proper file permissions
4. Create .env configuration with random passwords
5. Start all services

### Manual Setup

```bash
cd postgres-solr-setup

# 1. Download XWiki Solr configuration
XWIKI_VERSION="17.10.2"
wget -P solr-init/ \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/${XWIKI_VERSION}/xwiki-platform-search-solr-server-data-${XWIKI_VERSION}.jar"

# 2. Set permissions for Solr
sudo chown -R 8983:8983 solr-init/

# 3. Create environment file
cp .env.example .env
# Edit .env and change passwords!

# 4. Start services
docker compose -f docker-compose-postgres-solr.yml up -d

# 5. Check logs
docker compose -f docker-compose-postgres-solr.yml logs -f
```

## Access

After startup (2-3 minutes):
- **XWiki**: http://localhost:8080
- **Solr Admin**: http://localhost:8983/solr

## Services

| Service    | Container Name       | Purpose                    |
|------------|---------------------|----------------------------|
| web        | xwiki-web           | XWiki application          |
| db         | xwiki-postgres-db   | PostgreSQL 17 database     |
| solr       | xwiki-solr          | Solr 9 search engine       |

## Configuration

Edit `.env` file to customize:

```bash
# XWiki version
XWIKI_VERSION=stable-postgres-tomcat

# Port
XWIKI_PORT=8080

# Database passwords (CHANGE THESE!)
POSTGRES_ROOT_PASSWORD=your_secure_password
POSTGRES_PASSWORD=your_secure_password

# Solr heap size
SOLR_HEAP=1g
```

## Common Commands

```bash
# Start services
docker compose -f docker-compose-postgres-solr.yml up -d

# Stop services
docker compose -f docker-compose-postgres-solr.yml stop

# View logs
docker compose -f docker-compose-postgres-solr.yml logs -f

# Restart a service
docker compose -f docker-compose-postgres-solr.yml restart web

# Remove everything (including volumes!)
docker compose -f docker-compose-postgres-solr.yml down -v
```

## Backup

```bash
# Backup database
docker exec xwiki-postgres-db pg_dump -U xwiki xwiki > backup_$(date +%Y%m%d).sql

# Backup XWiki data
docker run --rm \
  -v xwiki-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/xwiki-backup-$(date +%Y%m%d).tar.gz -C /data .
```

## Troubleshooting

### Services not starting?

```bash
# Check service status
docker compose -f docker-compose-postgres-solr.yml ps

# Check health
docker inspect xwiki-web | grep -A 10 Health
```

### Solr core not found?

```bash
# Verify JAR file exists
ls -la solr-init/*.jar

# Check permissions
ls -la solr-init/

# Recreate Solr
docker compose -f docker-compose-postgres-solr.yml stop solr
docker compose -f docker-compose-postgres-solr.yml rm -f solr
docker volume rm xwiki-solr-data
docker compose -f docker-compose-postgres-solr.yml up -d solr
```

### Database connection issues?

```bash
# Test database
docker exec xwiki-postgres-db pg_isready -U xwiki

# Check environment variables
docker exec xwiki-web env | grep DB_
```

## Documentation

See **SETUP-POSTGRES-SOLR.md** for:
- Detailed setup instructions
- Configuration options
- Security hardening
- Performance tuning
- Production deployment guide
- Comprehensive troubleshooting

## Version Compatibility

| XWiki Version | PostgreSQL | Solr | Java |
|---------------|------------|------|------|
| 17.x          | 17         | 9    | 21   |
| 16.x          | 17         | 9    | 21   |

## Support

- XWiki Documentation: https://www.xwiki.org/xwiki/bin/view/Documentation/
- Docker Image: https://hub.docker.com/_/xwiki
- JIRA (Docker): https://jira.xwiki.org/browse/XDOCKER
- Forum: https://forum.xwiki.org/

## License

LGPL 2.1 - Same as XWiki
