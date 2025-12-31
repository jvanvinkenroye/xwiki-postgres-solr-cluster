# XWiki Cluster Monitoring Guide

Umfassende Anleitung zum Überwachen und Debuggen des XWiki-Clusters.

## Quick Status Check

```bash
# Alle Services anzeigen
docker compose -f docker-compose-cluster.yml ps

# Erwartete Ausgabe: Alle Services "healthy"
# - xwiki-cluster-db (PostgreSQL)
# - xwiki-cluster-solr (Solr)
# - xwiki-cluster-node1 (XWiki)
# - xwiki-cluster-node2 (XWiki)
# - xwiki-cluster-lb (Nginx)
```

## Nginx Load Balancer

### Status Page

```bash
# Im Browser öffnen
open http://localhost:8081/nginx_status

# Oder im Terminal
curl http://localhost:8081/nginx_status
```

**Ausgabe-Beispiel:**
```
Active connections: 5
server accepts handled requests
 150 150 387
Reading: 0 Writing: 2 Waiting: 3
```

**Bedeutung:**
- **Active connections**: Aktuell offene Verbindungen
- **150 accepts**: Insgesamt akzeptierte Verbindungen
- **150 handled**: Insgesamt behandelte Verbindungen
- **387 requests**: Insgesamt bearbeitete Requests
- **Reading**: Verbindungen, die Request lesen
- **Writing**: Verbindungen, die Response schreiben
- **Waiting**: Wartende Keep-Alive Verbindungen

### Request-Verteilung pro Node

```bash
# Zeigt welcher Node wie viele Requests bekommen hat
docker exec xwiki-cluster-lb cat /var/log/nginx/xwiki-access.log | \
  grep -oE "upstream: [0-9.]+:[0-9]+" | sort | uniq -c

# Beispiel-Ausgabe:
#  122 upstream: 172.18.0.4:8080    # Node 1
#   38 upstream: 172.18.0.5:8080    # Node 2
```

**Hinweis:** Ungleiche Verteilung ist **normal** wegen Sticky Sessions (JSESSIONID)!

### Live-Monitoring der Request-Verteilung

```bash
# Aktualisiert alle 2 Sekunden
watch -n 2 'docker exec xwiki-cluster-lb cat /var/log/nginx/xwiki-access.log | \
  grep -oE "upstream: [0-9.]+:[0-9]+" | sort | uniq -c'
```

### Letzte Requests anzeigen

```bash
# Letzte 20 Requests mit Details
docker exec xwiki-cluster-lb tail -20 /var/log/nginx/xwiki-access.log

# Nur Error-Logs
docker exec xwiki-cluster-lb tail -50 /var/log/nginx/xwiki-error.log
```

### Response-Zeiten analysieren

```bash
# Response-Zeiten der letzten 20 Requests
docker exec xwiki-cluster-lb cat /var/log/nginx/xwiki-access.log | \
  grep -oE "upstream_response_time: [0-9.]+" | tail -20

# Durchschnittliche Response-Zeit berechnen
docker exec xwiki-cluster-lb awk '{
  for(i=1;i<=NF;i++) {
    if($i ~ /upstream_response_time:/) {
      gsub(/[^0-9.]/, "", $(i+1))
      sum+=$(i+1); count++
    }
  }
} END {
  print "Durchschnitt:", sum/count, "Sekunden"
  print "Requests:", count
}' /var/log/nginx/xwiki-access.log
```

### Nginx Konfiguration testen

```bash
# Konfiguration auf Syntax-Fehler prüfen
docker exec xwiki-cluster-lb nginx -t

# Nginx neu laden (ohne Downtime)
docker exec xwiki-cluster-lb nginx -s reload

# Nginx Workers anzeigen
docker exec xwiki-cluster-lb ps aux | grep nginx
```

## XWiki Nodes

### Logs anzeigen

```bash
# Alle Nodes parallel
docker compose -f docker-compose-cluster.yml logs -f web1 web2

# Nur einen Node
docker compose -f docker-compose-cluster.yml logs -f web1

# Letzte 50 Zeilen
docker compose -f docker-compose-cluster.yml logs --tail=50 web1
```

### JGroups Cluster-Status prüfen

```bash
# Cluster-Mitgliedschaft in Node 1 prüfen
docker exec xwiki-cluster-node1 grep -a "view =" /usr/local/tomcat/logs/catalina.out | tail -5

# Erwartete Ausgabe (2-Node Cluster):
# [xwiki-node1|2] (2) [xwiki-node1, xwiki-node2]

# Alle JGroups-Events anzeigen
docker compose -f docker-compose-cluster.yml logs web1 | grep -i jgroups
```

**Cluster ist OK wenn:**
- Alle Nodes in der View erscheinen: `[xwiki-node1, xwiki-node2]`
- Keine MERGE-Events (Split-Brain)
- Keine Timeout-Fehler

### Health Checks

```bash
# Docker Health Status
docker inspect xwiki-cluster-node1 | grep -A 10 '"Health"'

# Manueller Health Check
curl -I http://localhost:8080/

# Health Check aller Services
docker compose -f docker-compose-cluster.yml ps | grep healthy
```

### Resource-Nutzung

```bash
# CPU und RAM aller Container
docker stats

# Nur XWiki Nodes
docker stats xwiki-cluster-node1 xwiki-cluster-node2

# Top-Prozesse in einem Container
docker exec xwiki-cluster-node1 top -b -n 1 | head -20
```

### Java/JVM Monitoring

```bash
# JVM-Parameter anzeigen
docker exec xwiki-cluster-node1 ps aux | grep java

# Heap-Nutzung (wenn JMX aktiviert)
# docker exec xwiki-cluster-node1 jstat -gc 1

# Thread-Dump erstellen
docker exec xwiki-cluster-node1 jstack 1 > thread-dump.txt
```

## PostgreSQL Datenbank

### Verbindungen überwachen

```bash
# Anzahl aktiver Verbindungen
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -c \
  "SELECT count(*) as connections FROM pg_stat_activity;"

# Verbindungen pro Node/Application
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -c \
  "SELECT application_name, count(*)
   FROM pg_stat_activity
   WHERE datname='xwiki'
   GROUP BY application_name;"

# Max Connections Check
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -c \
  "SHOW max_connections;"
```

### Datenbank-Performance

```bash
# Langsamste Queries
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -c \
  "SELECT query, calls, total_time, mean_time
   FROM pg_stat_statements
   ORDER BY mean_time DESC
   LIMIT 10;"

# Cache Hit Rate
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -c \
  "SELECT sum(heap_blks_read) as heap_read,
          sum(heap_blks_hit) as heap_hit,
          sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
   FROM pg_statio_user_tables;"
```

### Datenbank-Größe

```bash
# Gesamtgröße
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -c \
  "SELECT pg_size_pretty(pg_database_size('xwiki'));"

# Größte Tabellen
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -c \
  "SELECT schemaname, tablename,
          pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
   FROM pg_tables
   WHERE schemaname = 'public'
   ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
   LIMIT 10;"
```

## Apache Solr

### Core Status

```bash
# Solr Core Status
curl -s "http://localhost:8983/solr/admin/cores?action=STATUS&core=xwiki" | \
  grep -o '"numDocs":[0-9]*'

# Index-Größe
curl -s "http://localhost:8983/solr/admin/cores?action=STATUS&core=xwiki" | \
  grep -o '"sizeInBytes":[0-9]*'

# Core-Pfad prüfen
curl -s "http://localhost:8983/solr/admin/cores?action=STATUS&core=xwiki" | \
  grep -o '"instanceDir":"[^"]*"'
```

### Solr Logs

```bash
# Solr Container Logs
docker compose -f docker-compose-cluster.yml logs -f solr

# Solr initialisierung prüfen
docker compose -f docker-compose-cluster.yml logs solr | \
  grep -E "core definitions|Started"

# Solr Fehler
docker compose -f docker-compose-cluster.yml logs solr | grep -i error
```

### Solr Performance

```bash
# Solr Ping (Health Check)
curl "http://localhost:8983/solr/xwiki/admin/ping"

# Query-Stats
curl "http://localhost:8983/solr/xwiki/admin/mbeans?cat=QUERYHANDLER&wt=json" | \
  jq '.["solr-mbeans"][1]."/select".stats'
```

## Netzwerk & Konnektivität

### Service-zu-Service Verbindung testen

```bash
# Von XWiki zu Solr
docker exec xwiki-cluster-node1 curl -I http://xwiki-cluster-solr:8983/solr/

# Von XWiki zu DB
docker exec xwiki-cluster-node1 nc -zv xwiki-cluster-db 5432

# Von Nginx zu XWiki Nodes
docker exec xwiki-cluster-lb curl -I http://xwiki-cluster-node1:8080/
docker exec xwiki-cluster-lb curl -I http://xwiki-cluster-node2:8080/
```

### DNS-Auflösung prüfen

```bash
# Hostname-Auflösung testen
docker exec xwiki-cluster-node1 nslookup xwiki-cluster-db
docker exec xwiki-cluster-node1 nslookup xwiki-cluster-solr
docker exec xwiki-cluster-node1 nslookup xwiki-cluster-node2
```

### Netzwerk-Traffic

```bash
# Container Netzwerk-Stats
docker stats --no-stream --format "table {{.Container}}\t{{.NetIO}}"

# Offene Ports in Container
docker exec xwiki-cluster-node1 netstat -tuln
```

## Volumes & Storage

### Volume-Größen prüfen

```bash
# Alle Volumes
docker volume ls

# Volume-Größe prüfen
docker run --rm -v xwiki-cluster-data-shared:/data alpine du -sh /data
docker run --rm -v xwiki-cluster-postgres-data:/data alpine du -sh /data
docker run --rm -v xwiki-cluster-solr-data:/data alpine du -sh /data
```

### Volume-Inhalte ansehen

```bash
# Shared XWiki Data
docker run --rm -v xwiki-cluster-data-shared:/data alpine ls -lah /data

# Solr Core
docker run --rm -v xwiki-cluster-solr-data:/data alpine ls -lah /data/data/xwiki

# PostgreSQL Data
docker run --rm -v xwiki-cluster-postgres-data:/data alpine ls -lah /data
```

## Troubleshooting Dashboard (All-in-One)

```bash
#!/bin/bash
# cluster-status.sh - Kompletter Cluster-Status

echo "=== CONTAINER STATUS ==="
docker compose -f docker-compose-cluster.yml ps

echo -e "\n=== NGINX STATUS ==="
curl -s http://localhost:8081/nginx_status

echo -e "\n=== REQUEST DISTRIBUTION ==="
docker exec xwiki-cluster-lb cat /var/log/nginx/xwiki-access.log 2>/dev/null | \
  grep -oE "upstream: [0-9.]+:[0-9]+" | sort | uniq -c

echo -e "\n=== DATABASE CONNECTIONS ==="
docker exec xwiki-cluster-db psql -U xwiki -d xwiki -t -c \
  "SELECT count(*) FROM pg_stat_activity WHERE datname='xwiki';" 2>/dev/null

echo -e "\n=== SOLR DOCUMENTS ==="
curl -s "http://localhost:8983/solr/admin/cores?action=STATUS&core=xwiki" | \
  grep -o '"numDocs":[0-9]*'

echo -e "\n=== RESOURCE USAGE ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

Speichern als `cluster-status.sh` und ausführbar machen:
```bash
chmod +x cluster-status.sh
./cluster-status.sh
```

## Alerting Setup (Beispiel)

### Simple Health Check Cron Job

```bash
# /etc/cron.d/xwiki-health-check
*/5 * * * * /usr/local/bin/check-xwiki-cluster.sh

# /usr/local/bin/check-xwiki-cluster.sh
#!/bin/bash
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/)

if [ "$HEALTH" != "200" ] && [ "$HEALTH" != "302" ]; then
    echo "XWiki Cluster unhealthy: HTTP $HEALTH" | \
        mail -s "XWiki Alert" admin@example.com
fi
```

## Weiterführende Tools

- **Prometheus + Grafana**: Für umfassendes Monitoring
- **ELK Stack**: Für Log-Aggregation
- **Datadog/New Relic**: Für APM
- **Sentry**: Für Error Tracking

## Support

Bei Problemen siehe auch:
- `README.md` - Vollständige Dokumentation
- `CHANGELOG.md` - Bekannte Issues und Fixes
- XWiki Forum: https://forum.xwiki.org/
