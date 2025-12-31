# Changelog - XWiki Cluster Setup

Alle wichtigen Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

## [1.2.0] - 2025-12-31

### Geändert
- **Solr Setup vereinfacht** - Kein Custom Dockerfile mehr!
  - Entfernt: `Dockerfile.solr` (nicht mehr benötigt)
  - Entfernt: `solr-init/solr-init.sh` (ersetzt durch Alpine-Container)
  - Neu: `solr-init` Service in docker-compose (Alpine-based)
  - Nutzt nur noch offizielle Images: `solr:9` und `alpine:latest`

### Vorteile
- ✅ Einfacher zu warten (keine Custom Dockerfiles)
- ✅ Schnellere Image-Updates (nutzt offizielle Images)
- ✅ Clean Architecture (Separation of Concerns)
- ✅ Idempotent (kann mehrfach laufen ohne Probleme)
- ✅ Besser für CI/CD (keine Build-Schritte)

### Migration
Wenn Sie von Version 1.1.0 upgraden:
```bash
# 1. Cluster stoppen
docker compose -f docker-compose-cluster.yml down

# 2. Optional: Solr Volume löschen (wird neu initialisiert)
docker volume rm xwiki-cluster-solr-data

# 3. Neue Version starten
docker compose -f docker-compose-cluster.yml up -d
```

## [1.1.0] - 2025-12-31

### Hinzugefügt
- **Automatisiertes Setup-Script** (`setup-cluster.sh`)
  - Automatischer Download der korrekten Solr-Konfiguration (JAR oder ZIP)
  - XWiki-Versions-Erkennung (< 16.0 → JAR, >= 16.0 → ZIP)
  - Automatische Passwort-Generierung mit Base64
  - macOS und Linux Kompatibilität
  - Interaktive Cluster-Größen-Auswahl (2 oder 3 Nodes)
  - Health-Check-Monitoring während des Starts

- **Custom Solr Dockerfile** (`Dockerfile.solr`)
  - Erweitert offizielles `solr:9` Image
  - Fügt `unzip` und `sudo` hinzu für Konfigurationsextraktion
  - Läuft sicher als `solr` User (UID 8983)

- **Erweiterte Monitoring-Dokumentation**
  - Load Balancer Request-Verteilung anzeigen
  - Response-Zeit-Analyse
  - Live-Monitoring mit `watch`-Beispielen

### Geändert
- **Solr Core-Pfad korrigiert**
  - Von `/opt/solr/server/solr` → `/var/solr/data`
  - Volume Mount angepasst in `docker-compose-cluster.yml`
  - `solr-init.sh` aktualisiert für neuen Pfad

- **Nginx Port-Handling verbessert**
  - `proxy_set_header Host $http_host;` statt `$host`
  - `X-Forwarded-Port` explizit auf `8080` gesetzt
  - Behebt Problem mit fehlenden Ports in XWiki-Redirects

- **Nginx Upstream-Konfiguration**
  - Node 3 standardmäßig auskommentiert (2-Node-Cluster)
  - Kann einfach aktiviert werden bei Bedarf

- **solr-init.sh Multi-Format-Unterstützung**
  - Automatische Erkennung von JAR vs ZIP Format
  - Unterschiedliche Extraktionslogik für alte/neue XWiki-Versionen
  - Sudo-Unterstützung für Permission-Probleme

- **setup-cluster.sh macOS-Kompatibilität**
  - `sed` Delimiter von `/` auf `|` geändert (Base64-sichere Passwörter)
  - macOS-Erkennung für automatisches UID-Mapping
  - Keine `chown` auf macOS (Docker Desktop handled das)

### Behoben
- **Solr Container startet nicht** (unzip fehlte)
- **Permission denied** bei Solr-Core-Erstellung
- **Nginx Crash** wegen fehlender node3
- **Port fehlt in Redirects** (localhost:8080 → localhost)
- **sed Fehler** bei Passwörtern mit `/` Zeichen

### Dokumentation
- README.md komplett überarbeitet
  - Automatisiertes Setup dokumentiert
  - Troubleshooting erweitert (Port-Redirect-Problem)
  - Nginx statt HAProxy Referenzen
  - Monitoring-Sektion erweitert
  - Security Best Practices aktualisiert

- SETUP-ANLEITUNG.md aktualisiert
  - ZIP vs JAR Format dokumentiert
  - Automatisches Setup erwähnt

- Neue Datei: CHANGELOG.md (dieses Dokument)

## [1.0.0] - 2025-12-30

### Initial Release
- Docker Compose Setup für XWiki HA-Cluster
- PostgreSQL 17 als Shared Database
- Apache Solr 9 für Search
- Nginx Load Balancer mit Sticky Sessions
- JGroups TCP für Cluster-Kommunikation
- 2-3 XWiki Nodes
- Health Checks für alle Services
- Monitoring mit Nginx Status Page

---

## Versionsschema

Dieses Projekt folgt [Semantic Versioning](https://semver.org/):

- **MAJOR**: Inkompatible API/Konfigurations-Änderungen
- **MINOR**: Neue Funktionen (abwärtskompatibel)
- **PATCH**: Bugfixes (abwärtskompatibel)

## Kategorien

- **Hinzugefügt**: Neue Features
- **Geändert**: Änderungen an bestehenden Features
- **Veraltet**: Features die bald entfernt werden
- **Entfernt**: Entfernte Features
- **Behoben**: Bugfixes
- **Sicherheit**: Sicherheits-Updates
