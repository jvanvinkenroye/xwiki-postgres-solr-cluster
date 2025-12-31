# Solr Initialization Directory

This directory contains files required to initialize the Solr container with XWiki-specific configuration.

## Required Files

1. **solr-init.sh** - Initialization script (already present)
2. **xwiki-platform-search-solr-server-data-VERSION.jar** - XWiki Solr configuration (YOU MUST DOWNLOAD THIS)

## Setup Instructions

### Download the XWiki Solr Configuration JAR

Replace `VERSION` with your XWiki version (e.g., 17.10.2, 16.10.15):

```bash
# Set your XWiki version
XWIKI_VERSION="17.10.2"

# Download the JAR file
wget "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/${XWIKI_VERSION}/xwiki-platform-search-solr-server-data-${XWIKI_VERSION}.jar"
```

### Available Versions

You can browse available versions here:
https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/

### Set Correct Permissions

The Solr container runs as UID/GID 8983:

```bash
# From the parent directory
sudo chown -R 8983:8983 solr-init/
```

### Verify Setup

After downloading and setting permissions, this directory should contain:

```
solr-init/
├── README.md                                           (this file)
├── solr-init.sh                                        (executable, owner 8983:8983)
└── xwiki-platform-search-solr-server-data-17.10.2.jar  (readable, owner 8983:8983)
```

Check with:
```bash
ls -la
```

Expected output:
```
total XX
drwxr-xr-x  4 8983 8983  128 Dec 30 10:00 .
drwxr-xr-x 15 user staff 480 Dec 30 10:00 ..
-rw-r--r--  1 8983 8983  XXX Dec 30 10:00 README.md
-rwxr-xr-x  1 8983 8983  XXX Dec 30 10:00 solr-init.sh
-rw-r--r--  1 8983 8983  XXX Dec 30 10:00 xwiki-platform-search-solr-server-data-17.10.2.jar
```

## Troubleshooting

### Permission Issues

If you see errors like "Permission denied" when Solr starts:

```bash
# Fix ownership
sudo chown -R 8983:8983 solr-init/

# Verify
ls -la
```

### JAR File Not Found

If Solr initialization fails with "No XWiki Solr configuration jar found":

```bash
# Check the JAR file is present
ls -la *.jar

# Download if missing (replace VERSION)
wget "https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/VERSION/xwiki-platform-search-solr-server-data-VERSION.jar"
```

### Multiple JAR Files

If you see "Too many XWiki Solr configuration jars found":

```bash
# Only keep one JAR file (the one matching your XWiki version)
rm xwiki-platform-search-solr-server-data-OLD_VERSION.jar
```

## What the Initialization Script Does

The `solr-init.sh` script:

1. Verifies exactly one JAR file is present
2. Extracts the Solr library plugins from the JAR
3. Extracts the XWiki core configuration
4. Deploys everything to `/opt/solr/server/solr/`

This runs automatically when the Solr container first starts.
