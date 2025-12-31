# XWiki Cluster Setup - Schritt für Schritt Anleitung

Diese Anleitung führt Sie durch die komplette Einrichtung eines XWiki-Clusters mit PostgreSQL und Solr.

## Voraussetzungen

- Docker Engine 20.10.16 oder höher
- Docker Compose v2.0 oder höher
- Mindestens 8GB RAM
- 20GB freier Festplattenspeicher
- Sudo-Rechte (für Solr-Berechtigungen)

## Automatische Installation

Das Setup-Skript richtet alles automatisch ein:

```bash
cd postgres-solr-setup/clustering/
./setup-cluster.sh
```

### Was das Skript macht:

1. **Überprüft Voraussetzungen**
   - Docker Installation
   - Docker Compose Version
   - Verfügbare Tools (wget/curl)

2. **XWiki-Version auswählen**
   ```
   Welche XWiki-Version möchten Sie verwenden?

   1) 17.10.2 (Latest stable - Empfohlen)
   2) 16.10.15 (LTS)
   3) 17.4.7 (Ältere stable)
   4) Benutzerdefinierte Version
   ```

3. **Solr-Konfiguration einrichten**
   - Lädt automatisch die passende Solr-JAR-Datei herunter
   - Kopiert das solr-init.sh Skript (falls benötigt)
   - Setzt die korrekten Berechtigungen (8983:8983)

4. **Umgebungsvariablen erstellen**
   - Erstellt .env Datei
   - Generiert sichere Zufallspasswörter
   - Konfiguriert Ports

5. **Cluster-Größe festlegen**
   ```
   Wie viele XWiki-Nodes sollen laufen?

   2 Nodes - Minimum für High Availability
   3 Nodes - Empfohlen für Produktion (Standard)
   ```

6. **Services starten**
   - PostgreSQL Datenbank
   - Solr Suchmaschine
   - XWiki Nodes (2-3)
   - Nginx Load Balancer

7. **Gesundheitschecks abwarten**
   - Überwacht alle Services
   - Zeigt Fortschritt in Echtzeit
   - Wartet auf vollständige Initialisierung

## Manuelle Installation

Falls Sie die Schritte manuell durchführen möchten:

### Schritt 1: Solr-Konfiguration herunterladen

```bash
# XWiki-Version festlegen
XWIKI_VERSION="17.10.2"

# Ins übergeordnete Verzeichnis wechseln (für solr-init)
cd /Users/java/src/xwiki-docker/postgres-solr-setup

# Solr-Konfiguration herunterladen
# WICHTIG: Ab XWiki 16.x wird ein anderes Artefakt verwendet!

# Für XWiki >= 16.0 (ZIP-Format):
wget -P solr-init/ \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-core-minimal/${XWIKI_VERSION}/xwiki-platform-search-solr-server-core-minimal-${XWIKI_VERSION}.zip"

# Für ältere Versionen < 16.0 (JAR-Format):
# wget -P solr-init/ \
#   "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/${XWIKI_VERSION}/xwiki-platform-search-solr-server-data-${XWIKI_VERSION}.jar"
```

**Wichtig:**
- Die Version muss mit Ihrer XWiki-Version übereinstimmen!
- Ab XWiki 16.x verwendet man `xwiki-platform-search-solr-server-core-minimal` (ZIP)
- Ältere Versionen verwenden `xwiki-platform-search-solr-server-data` (JAR)
- Beide Formate funktionieren mit dem solr-init.sh Skript

### Schritt 2: Berechtigungen setzen

```bash
# Solr läuft als UID/GID 8983
sudo chown -R 8983:8983 solr-init/

# Überprüfen
ls -la solr-init/
```

Erwartete Ausgabe:
```
drwxr-xr-x  4 8983 8983  128 Dec 30 10:00 .
-rwxr-xr-x  1 8983 8983 1234 Dec 30 10:00 solr-init.sh
-rw-r--r--  1 8983 8983 5678 Dec 30 10:00 xwiki-platform-search-solr-server-data-17.10.2.jar
```

### Schritt 3: Umgebungsdatei erstellen

```bash
# Ins Clustering-Verzeichnis wechseln
cd clustering/

# Umgebungsdatei kopieren
cp .env.example .env

# Passwörter anpassen (wichtig!)
nano .env
```

Ändern Sie mindestens diese Werte:
```bash
POSTGRES_ROOT_PASSWORD=IhrSicheresPasswort123!
POSTGRES_PASSWORD=IhrXWikiPasswort456!
```

### Schritt 4: Cluster starten

```bash
# Alle Services starten
docker compose -f docker-compose-cluster.yml up -d

# Logs verfolgen
docker compose -f docker-compose-cluster.yml logs -f
```

### Schritt 5: Warten auf Initialisierung

Der Start dauert etwa 3-5 Minuten. Überwachen Sie den Fortschritt:

```bash
# Service-Status prüfen
docker compose -f docker-compose-cluster.yml ps

# Gesundheitszustand einzelner Services
docker inspect xwiki-cluster-db | grep -A 5 Health
docker inspect xwiki-cluster-solr | grep -A 5 Health
docker inspect xwiki-cluster-node1 | grep -A 5 Health
docker inspect xwiki-cluster-lb | grep -A 5 Health
```

Alle sollten `"Status": "healthy"` zeigen.

## Nach der Installation

### Zugriffspunkte

| Service | URL | Zweck |
|---------|-----|-------|
| **XWiki** | http://localhost:8080 | Hauptzugriff (über Load Balancer) |
| **Nginx Status** | http://localhost:8081/nginx_status | Load Balancer Monitoring |
| **Solr Admin** | http://localhost:8983/solr | Suchmaschinen-Admin |

### Erste Schritte

1. **XWiki öffnen**
   ```
   http://localhost:8080
   ```

2. **Distribution Wizard durchlaufen**
   - Klicken Sie auf "Continue"
   - Wählen Sie "Main Wiki" Flavor
   - Warten Sie auf Installation

3. **Admin-Benutzer erstellen**
   - Benutzername festlegen
   - Sicheres Passwort wählen
   - E-Mail-Adresse angeben

4. **Cluster-Bildung überprüfen**
   ```bash
   # JGroups-Logs anzeigen
   docker compose -f docker-compose-cluster.yml logs web1 | grep -i "received new view"

   # Sollte zeigen:
   # "received new view: [xwiki-node1|2] (2) [xwiki-node1, xwiki-node2]"
   # Oder bei 3 Nodes:
   # "received new view: [xwiki-node1|3] (3) [xwiki-node1, xwiki-node2, xwiki-node3]"
   ```

5. **Load Balancer Status prüfen**
   ```bash
   curl http://localhost:8081/nginx_status
   ```

## Problembehandlung

### Problem: Solr-JAR nicht gefunden

**Fehlermeldung:**
```
No XWiki Solr configuration jar found
```

**Lösung:**
```bash
# Überprüfen Sie das Verzeichnis
ls -la ../solr-init/

# JAR sollte vorhanden sein
# Falls nicht, manuell herunterladen
XWIKI_VERSION="17.10.2"
wget -P ../solr-init/ \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/${XWIKI_VERSION}/xwiki-platform-search-solr-server-data-${XWIKI_VERSION}.jar"

# Berechtigungen setzen
sudo chown -R 8983:8983 ../solr-init/
```

### Problem: Berechtigungsfehler

**Fehlermeldung:**
```
Permission denied
```

**Lösung:**
```bash
# Solr-Berechtigungen korrigieren
sudo chown -R 8983:8983 ../solr-init/

# Überprüfen
ls -la ../solr-init/
# Eigentümer sollte 8983:8983 sein
```

### Problem: Ports bereits belegt

**Fehlermeldung:**
```
Error: bind: address already in use
```

**Lösung:**
```bash
# Prüfen, welcher Port belegt ist
lsof -i :8080
lsof -i :8081
lsof -i :8983

# Option 1: Andere Ports verwenden (in .env)
XWIKI_PORT=9080
NGINX_STATUS_PORT=9081

# Option 2: Bestehende Services stoppen
docker stop <container-name>
```

### Problem: Services starten nicht

**Symptome:**
- Container bleiben im "starting" Status
- Health checks schlagen fehl

**Diagnose:**
```bash
# Logs aller Services anzeigen
docker compose -f docker-compose-cluster.yml logs

# Einzelne Services überprüfen
docker compose -f docker-compose-cluster.yml logs db
docker compose -f docker-compose-cluster.yml logs solr
docker compose -f docker-compose-cluster.yml logs web1

# Service-Status
docker compose -f docker-compose-cluster.yml ps
```

**Häufige Ursachen:**
1. Zu wenig RAM (mindestens 8GB erforderlich)
2. Solr-JAR fehlt oder falsche Berechtigungen
3. Datenbankverbindung fehlgeschlagen
4. Falsches Passwort in .env

### Problem: Cluster bildet sich nicht

**Symptome:**
- Änderungen auf einem Node nicht auf anderen sichtbar
- Cache nicht synchronisiert

**Lösung:**
```bash
# JGroups-Logs prüfen
docker compose -f docker-compose-cluster.yml logs web1 | grep -i jgroups
docker compose -f docker-compose-cluster.yml logs web2 | grep -i jgroups

# Netzwerkverbindung testen
docker exec xwiki-cluster-node1 ping xwiki-cluster-node2

# Alle XWiki-Nodes neu starten
docker compose -f docker-compose-cluster.yml restart web1 web2 web3
```

### Problem: Sticky Sessions funktionieren nicht

**Symptome:**
- Benutzer werden zwischen Nodes hin und her geschaltet
- Session-Verlust

**Diagnose:**
```bash
# JSESSIONID Cookie prüfen
curl -v http://localhost:8080/ 2>&1 | grep JSESSIONID

# Nginx-Konfiguration testen
docker exec xwiki-cluster-lb nginx -t

# Upstream-Konfiguration prüfen
docker exec xwiki-cluster-lb cat /etc/nginx/conf.d/upstream.conf
```

## Nützliche Befehle

### Service-Verwaltung

```bash
# Alle Services starten
docker compose -f docker-compose-cluster.yml up -d

# Alle Services stoppen
docker compose -f docker-compose-cluster.yml stop

# Alle Services neu starten
docker compose -f docker-compose-cluster.yml restart

# Bestimmten Service neu starten
docker compose -f docker-compose-cluster.yml restart web1

# Services entfernen (Daten bleiben erhalten)
docker compose -f docker-compose-cluster.yml down

# Alles entfernen (inkl. Volumes - ACHTUNG: Datenverlust!)
docker compose -f docker-compose-cluster.yml down -v
```

### Monitoring

```bash
# Alle Logs anzeigen
docker compose -f docker-compose-cluster.yml logs -f

# Logs eines Services
docker compose -f docker-compose-cluster.yml logs -f web1

# Service-Status
docker compose -f docker-compose-cluster.yml ps

# Ressourcennutzung
docker stats

# Nginx Status
curl http://localhost:8081/nginx_status
```

### Wartung

```bash
# In Container einloggen
docker exec -it xwiki-cluster-node1 bash
docker exec -it xwiki-cluster-db bash
docker exec -it xwiki-cluster-lb sh

# Datenbank-Backup
docker exec xwiki-cluster-db pg_dump -U xwiki xwiki > backup_$(date +%Y%m%d).sql

# Datenbank wiederherstellen
cat backup_20240101.sql | docker exec -i xwiki-cluster-db psql -U xwiki xwiki

# Nginx-Konfiguration neu laden (ohne Downtime)
docker exec xwiki-cluster-lb nginx -s reload
```

## Skalierung

### Node hinzufügen

```bash
# 1. docker-compose-cluster.yml bearbeiten (web3 nach web4 kopieren)
# 2. jgroups/tcp.xml aktualisieren (node4 hinzufügen)
# 3. nginx/upstream.conf aktualisieren
vim nginx/upstream.conf
# Hinzufügen: server xwiki-cluster-node4:8080 max_fails=3 fail_timeout=30s;

# 4. Nginx neu laden
docker exec xwiki-cluster-lb nginx -s reload

# 5. Neuen Node starten
docker compose -f docker-compose-cluster.yml up -d --no-deps web4
```

### Node entfernen

```bash
# 1. Node stoppen
docker compose -f docker-compose-cluster.yml stop web3

# 2. nginx/upstream.conf bearbeiten (Zeile entfernen/kommentieren)

# 3. Nginx neu laden
docker exec xwiki-cluster-lb nginx -s reload

# 4. Container entfernen
docker compose -f docker-compose-cluster.yml rm web3
```

## Weiterführende Dokumentation

- **README.md** - Vollständige Setup-Dokumentation
- **ARCHITECTURE.md** - Detaillierte Architektur-Beschreibung
- **MIGRATION-NGINX.md** - Nginx vs HAProxy Vergleich
- **nginx/README.md** - Nginx-Konfiguration im Detail

## Support

Bei Problemen:
1. Logs überprüfen: `docker compose -f docker-compose-cluster.yml logs`
2. README.md Troubleshooting-Sektion konsultieren
3. XWiki Forum: https://forum.xwiki.org/
4. Docker Image Docs: https://hub.docker.com/_/xwiki

## Lizenz

LGPL 2.1 - Wie XWiki
