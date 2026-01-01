# Changelog - XWiki Cluster Setup

Alle wichtigen Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

## [1.3.0] - 2026-01-01

### Geändert - BREAKING: Solr Core-Konfiguration komplett überarbeitet

**Wichtig:** Diese Version verwendet offizielle XWiki Solr-Konfigurationen von Maven statt Custom-Schemas.

#### Neue Solr-Architektur
- **Offizielle Maven-Artefakte**: Download von xwiki-platform-search-solr-server-core-search und -minimal
- **4 Pre-konfigurierte Cores**:
  - `xwiki_search_9` - Haupt-Suchindex (volle XWiki-Schema, ~6MB)
  - `xwiki_extension_index_9` - Extension-Management (minimal)
  - `xwiki_events_9` - Event-Stream (minimal)
  - `xwiki_ratings_9` - Seiten-Bewertungen (minimal)
- **analysis-extras Modul**: Automatisch aktiviert für erweiterte Sprach-Analyzer
- **Neues Verzeichnis**: `solr-cores-official/` statt `../solr-init/`

#### Technische Verbesserungen
- ✅ **Vollständige Schema-Kompatibilität**: Alle benötigten Field Types und Analyzer
- ✅ **Keine Schema-Konflikte**: Offizielles Schema verhindert _version_ und andere Feldprobleme
- ✅ **ConfigSet Support**: Dynamische Core-Erstellung via Solr API
- ✅ **Sprachunterstützung**: Polnisch, Tschechisch, Ungarisch und 30+ weitere Sprachen
- ✅ **XWiki 16.2.0+ kompatibel**: Neue Core-Naming-Convention

### Hinzugefügt
- **Neue Dokumentation**: `SOLR-SETUP.md`
  - Detaillierte Solr-Konfigurationsanleitung
  - Versions-Kompatibilitätsmatrix
  - Troubleshooting-Guide
  - Performance-Tuning-Tipps

- **Umgebungsvariable**: `SOLR_MODULES=analysis-extras`
  - Aktiviert erweiterte Token-Filter
  - Erforderlich für XWiki 16.6.0+

- **Healthcheck-Update**: Verwendet `xwiki_search_9` statt veraltetem `xwiki`

### Behoben
- **Solr Startup-Fehler**: "stempelPolishStem does not exist"
  - Ursache: Fehlende analysis-extras Module
  - Lösung: SOLR_MODULES environment variable

- **Schema-Konflikte**: "_version_ is not an indexed field"
  - Ursache: Falsche Field-Definition in Custom-Schemas
  - Lösung: Offizielle XWiki-Schemas verwenden

- **Core-Erstellung schlägt fehl**: "Can't find resource 'solrconfig.xml'"
  - Ursache: XWiki konnte Cores nicht erstellen (fehlende ConfigSet)
  - Lösung: ConfigSet vorbereitet, Cores pre-created

- **Flavor-Installation scheitert**: Solr nicht erreichbar
  - Ursache: Cores existierten nicht oder hatten falsches Schema
  - Lösung: Alle 4 Cores mit offiziellen Configs vorbereitet

### Migration von 1.2.0 zu 1.3.0

```bash
# 1. Cluster stoppen und Volumes löschen (notwendig!)
docker compose -f docker-compose-cluster.yml down -v

# 2. Offizielle Solr-Cores herunterladen
VERSION="17.10.2"
mkdir -p solr-cores-official
cd solr-cores-official

# Main Search Core
curl -L -o search-core.zip \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-core-search/${VERSION}/xwiki-platform-search-solr-server-core-search-${VERSION}.zip"

# Minimal Cores
curl -L -o minimal-core.zip \
  "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-core-minimal/${VERSION}/xwiki-platform-search-solr-server-core-minimal-${VERSION}.zip"

# Extrahieren
unzip -q search-core.zip
unzip -q minimal-core.zip -d minimal

cd ..

# 3. Cluster neu starten
docker compose -f docker-compose-cluster.yml up -d

# 4. Cores verifizieren
curl -s "http://localhost:8983/solr/admin/cores?action=STATUS" | \
  python3 -c "import sys, json; data=json.load(sys.stdin); \
  [print(f'{name}: OK') for name in data['status'].keys()]"
```

**Erwartete Ausgabe:**
```
xwiki_events_9: OK
xwiki_extension_index_9: OK
xwiki_ratings_9: OK
xwiki_search_9: OK
```

### Veraltet
- **Custom Minimal Schemas**: Nicht mehr verwendet
- **Core-Name "xwiki"**: Ersetzt durch `xwiki_search_9` (XWiki 16.2.0+)
- **../solr-init/ Verzeichnis**: Ersetzt durch `solr-cores-official/`

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
