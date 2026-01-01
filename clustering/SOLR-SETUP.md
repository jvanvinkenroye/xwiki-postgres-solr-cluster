# XWiki Solr Core Configuration Guide

## Overview

This document explains the Solr core configuration setup for XWiki clustering, including the migration from custom minimal schemas to official XWiki configurations.

## Core Architecture

### XWiki 16.2.0+ Core Structure

XWiki requires 4 separate Solr cores for optimal functionality:

| Core Name | Purpose | Schema Type | Size | Critical |
|-----------|---------|-------------|------|----------|
| `xwiki_search_9` | Main wiki content search | Full XWiki schema | ~6MB | Yes |
| `xwiki_extension_index_9` | Extension management | Minimal schema | ~2KB | Medium |
| `xwiki_events_9` | Event stream / activity | Minimal schema | ~2KB | No* |
| `xwiki_ratings_9` | Page ratings / likes | Minimal schema | ~2KB | No* |

\* Can fall back to database storage if Solr core unavailable

### Core Naming Convention

Format: `xwiki_<type>_<wikiId>`

- **Wiki ID**: Hash-based identifier for the wiki instance
- **Default wiki "xwiki"**: Hash value = 9
- **Multi-wiki setup**: Each sub-wiki gets its own set of cores

Example:
- Main wiki: `xwiki_search_9`, `xwiki_events_9`, etc.
- Sub-wiki "engineering": `xwiki_search_10`, `xwiki_events_10`, etc.

## Implementation History

### Version 1: Custom Minimal Schemas (Failed)

**Approach:**
- Created cores with hand-crafted minimal XML schemas
- Used basic field types (plong, string, _version_)
- Pre-created cores in solr-init container

**Problems Encountered:**
1. Schema conflicts with _version_ field indexing
2. Missing field types required by XWiki
3. XWiki attempted to CREATE already-existing cores
4. No configSet specified in XWiki's core creation requests

**Errors:**
```
Error CREATEing SolrCore 'xwiki_search_9': Unable to create core
Caused by: Can't find resource 'solrconfig.xml'
'_version_' is not an indexed field
```

### Version 2: Official Maven Configurations (Success)

**Approach:**
- Download official core configurations from XWiki Maven repository
- Use full search core schema (xwiki-platform-search-solr-server-core-search)
- Use minimal core schema for secondary cores (xwiki-platform-search-solr-server-core-minimal)
- Enable Solr analysis-extras module

**Success Factors:**
1. Official schemas include all required field types and analyzers
2. Proper configSet created for dynamic core creation
3. analysis-extras module provides advanced language analyzers
4. Pre-created cores prevent XWiki CREATE failures

## Configuration Details

### Maven Artifacts

**Main Search Core:**
```bash
https://maven.xwiki.org/releases/org/xwiki/platform/\
  xwiki-platform-search-solr-server-core-search/\
  ${VERSION}/xwiki-platform-search-solr-server-core-search-${VERSION}.zip
```

**Minimal Cores:**
```bash
https://maven.xwiki.org/releases/org/xwiki/platform/\
  xwiki-platform-search-solr-server-core-minimal/\
  ${VERSION}/xwiki-platform-search-solr-server-core-minimal-${VERSION}.zip
```

### Directory Structure

After extraction in `solr-cores-official/`:

```
solr-cores-official/
├── search-core.zip          # Downloaded archive
├── minimal-core.zip         # Downloaded archive
├── conf/                    # Main search core config
│   ├── managed-schema.xml   # Full XWiki schema
│   ├── solrconfig.xml       # Solr configuration
│   ├── lang/                # Language-specific configs
│   ├── stopwords.txt
│   ├── synonyms.txt
│   └── ...
├── lib/                     # Custom JARs for search core
│   ├── *.jar
└── minimal/                 # Minimal core config
    └── conf/
        ├── managed-schema   # Basic schema
        └── solrconfig.xml   # Basic config
```

### solr-init Container

The initialization container sets up all cores before Solr starts:

```yaml
solr-init:
  image: alpine:latest
  volumes:
    - ./solr-cores-official:/source:ro
    - solr-data:/target
  command: |
    sh -c '
      # Create main search core
      mkdir -p /target/data/xwiki_search_9
      cp -r /source/conf /target/data/xwiki_search_9/
      cp -r /source/lib /target/data/xwiki_search_9/
      echo "name=xwiki_search_9" > /target/data/xwiki_search_9/core.properties

      # Create ConfigSet for dynamic core creation
      mkdir -p /target/data/configsets/xwiki
      cp -r /source/conf /target/data/configsets/xwiki/

      # Create additional cores with minimal config
      for core_name in xwiki_extension_index_9 xwiki_events_9 xwiki_ratings_9; do
        mkdir -p /target/data/$core_name
        cp -r /source/minimal/conf /target/data/$core_name/
        echo "name=$core_name" > /target/data/$core_name/core.properties
      done

      # Set permissions for Solr user (UID:GID 8983:8983)
      chown -R 8983:8983 /target/data
    '
```

### Solr Service Configuration

Key environment variables:

```yaml
solr:
  environment:
    SOLR_HEAP: ${SOLR_HEAP:-1g}
    SOLR_MODULES: analysis-extras              # Required for advanced analyzers
    SOLR_OPTS: "-Dsolr.configset.default=xwiki"  # Default configSet
```

### Required Solr Modules

**analysis-extras** (XWiki 16.6.0+):

Provides advanced language-specific token filters:
- stempelPolishStem (Polish)
- czechStem (Czech)
- hungarianLightStem (Hungarian)
- And many more...

Without this module, Solr startup fails with:
```
Plugin init failure for [schema.xml] analyzer/filter "stempelPolishStem":
A SPI class of type org.apache.lucene.analysis.TokenFilterFactory with name
'stempelPolishStem' does not exist.
```

## XWiki Configuration

### xwiki.properties

```properties
# Remote Solr configuration
solr.type=remote
solr.remote.baseURL=http://xwiki-cluster-solr:8983/solr

# ConfigSet for dynamic core creation
solr.remote.configSet=xwiki

# Optional: Core prefix (default is "xwiki")
# solr.remote.corePrefix=xwiki

# Event stream storage (fallback to database)
eventstream.store=database
```

## Version Compatibility

### XWiki Version Matrix

| XWiki Version | Solr Version | Core Names | Search Core Package |
|---------------|--------------|------------|---------------------|
| 11.4 - 11.5 | 7.7.x | `xwiki` | server-core |
| 11.6 - 13.2 | 8.1.x | `xwiki` | server-core |
| 14.8 - 16.1.0 | 8.11.x | `xwiki` | server-core |
| 16.2.0+ | 9.4.x | `xwiki_search_9` | server-core-search |

### Core Naming Changes (16.2.0+)

**Before 16.2.0:**
- Main core: `xwiki`
- Secondary cores: `xwiki_extension_index`, `xwiki_events`, `xwiki_ratings`

**After 16.2.0:**
- Main core: `xwiki_search_9` (renamed for consistency)
- Secondary cores: `xwiki_extension_index_9`, `xwiki_events_9`, `xwiki_ratings_9`

## Troubleshooting

### Verify Core Loading

```bash
# Check all loaded cores
curl -s "http://localhost:8983/solr/admin/cores?action=STATUS" | \
  python3 -c "import sys, json; data=json.load(sys.stdin); \
  print('Loaded Cores:'); \
  [print(f'  ✅ {name}: {info[\"index\"][\"numDocs\"]} documents') \
   for name, info in sorted(data['status'].items()) if name]"
```

Expected output:
```
Loaded Cores:
  ✅ xwiki_events_9: 0 documents
  ✅ xwiki_extension_index_9: 0 documents
  ✅ xwiki_ratings_9: 0 documents
  ✅ xwiki_search_9: 0 documents
```

### Check Solr Logs

```bash
# View startup logs
docker logs xwiki-cluster-solr

# Check for errors
docker logs xwiki-cluster-solr 2>&1 | grep -i "error\|exception"

# Monitor in real-time
docker logs -f xwiki-cluster-solr
```

### Test Core Health

```bash
# Ping main search core
curl "http://localhost:8983/solr/xwiki_search_9/admin/ping"

# Check core statistics
curl "http://localhost:8983/solr/xwiki_search_9/admin/stats"
```

### Common Issues

**Issue: Missing analysis-extras**
```
Error: A SPI class of type org.apache.lucene.analysis.TokenFilterFactory
with name 'stempelPolishStem' does not exist.
```
**Solution:** Add `SOLR_MODULES: analysis-extras` to Solr environment variables.

**Issue: Core already exists**
```
Error CREATEing SolrCore 'xwiki_search_9': Core with name
'xwiki_search_9' already exists.
```
**Solution:** This is expected. XWiki attempts to create cores but finds them pre-created. No action needed.

**Issue: Wrong core name in healthcheck**
```
curl: (22) The requested URL returned error: 404
```
**Solution:** Update healthcheck to use `xwiki_search_9` instead of `xwiki`:
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:8983/solr/xwiki_search_9/admin/ping || exit 1"]
```

## Performance Considerations

### Heap Sizing

- **Small wiki** (<10k pages): 1GB heap
- **Medium wiki** (10k-100k pages): 2-4GB heap
- **Large wiki** (>100k pages): 4-8GB heap

```yaml
environment:
  SOLR_HEAP: 4g
```

### Index Optimization

After initial indexing or bulk updates:

```bash
# Optimize all cores
for core in xwiki_search_9 xwiki_extension_index_9 xwiki_events_9 xwiki_ratings_9; do
  curl "http://localhost:8983/solr/${core}/update?optimize=true"
done
```

### Disk Space

Monitor index sizes:

```bash
docker exec xwiki-cluster-solr du -sh /var/solr/data/xwiki_*
```

Typical sizes:
- `xwiki_search_9`: ~18KB per document
- `xwiki_extension_index_9`: Minimal
- `xwiki_events_9`: 5-10KB per event (if used)
- `xwiki_ratings_9`: Minimal

## Best Practices

### Development

1. Use official Maven artifacts matching XWiki version
2. Enable analysis-extras module by default
3. Pre-create all cores in solr-init
4. Use database fallback for events/ratings (simplicity)

### Production

1. Monitor Solr heap usage and GC pauses
2. Regular index optimization (weekly for active wikis)
3. Backup Solr data directory
4. Consider SolrCloud for high availability
5. Separate Solr from XWiki nodes (dedicated servers)

### Upgrades

1. Check XWiki version compatibility matrix
2. Download matching Solr core configurations
3. Test in staging environment first
4. Backup existing cores before upgrade
5. Clear and reindex if major version change

## References

- **XWiki Solr API Documentation**: https://extensions.xwiki.org/xwiki/bin/view/Extension/Solr%20Search%20API
- **XWiki Maven Repository**: https://maven.xwiki.org/releases/org/xwiki/platform/
- **Solr Reference Guide**: https://solr.apache.org/guide/9_4/
- **Solr Modules**: https://solr.apache.org/guide/9_4/modules.html

## Changelog

### 2026-01-01: Official Maven Configurations

- Migrated from custom minimal schemas to official XWiki configurations
- Added analysis-extras module support
- Updated core naming for XWiki 16.2.0+ compatibility
- Implemented proper configSet for dynamic core creation
- Documented troubleshooting procedures

### Previous: Custom Minimal Schemas (Deprecated)

- Hand-crafted XML schemas (no longer recommended)
- Missing required analyzers and field types
- Incompatible with XWiki's schema migration
