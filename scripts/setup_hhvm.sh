#!/bin/bash

BASE_DIR="/work/mewais/DCArch/DCPerf"
HHVM_BIN="${BASE_DIR}/release/bin/hhvm"
MEDIAWIKI_ROOT="${BASE_DIR}/release"
SCRIPT_DIR="${BASE_DIR}/scripts"
CACHE_DIR="${BASE_DIR}/cache"

echo "=== HHVM Environment Setup ==="
echo "This script prepares the environment for multiple benchmark runs"

# Create necessary directories
mkdir -p $CACHE_DIR
mkdir -p ${BASE_DIR}/logs
mkdir -p ${BASE_DIR}/data

# Step 1: Build bytecode repository (persisted to disk)
if [ ! -f "$CACHE_DIR/hhvm.hhbc" ]; then
    echo "Building HHVM bytecode repository (one-time operation)..."
    cd $MEDIAWIKI_ROOT
    $HHVM_BIN --hphp -t hhbc -v AllVolatile=true \
        --input-list <(find . -name "*.php") \
        --output-dir $CACHE_DIR/
    echo "Bytecode repository built at $CACHE_DIR/hhvm.hhbc"
else
    echo "Bytecode repository already exists at $CACHE_DIR/hhvm.hhbc"
fi

# Step 2: Generate pre-filled APC cache data files
if [ ! -f "${BASE_DIR}/data/apc_cache_dump.bin" ]; then
    echo "Generating APC cache data files (one-time operation)..."
    
    # Create a script to generate cache data
    cat > ${SCRIPT_DIR}/generate_cache_data.php << 'EOF'
<?php
// Generate 100GB of deterministic data and save to files
$dataDir = '/work/mewais/DCArch/DCPerf/data/hhvm';
$totalSize = 100 * 1024 * 1024 * 1024; // 100GB
$blockSize = 1024 * 1024 * 1024;       // 1GB files
$numFiles = $totalSize / $blockSize;

echo "Generating cache data files...\n";

for ($i = 0; $i < $numFiles; $i++) {
    $filename = "$dataDir/cache_block_$i.dat";
    if (!file_exists($filename)) {
        $data = str_repeat(md5($i), $blockSize / 32);
        file_put_contents($filename, $data);
        echo "Generated: cache_block_$i.dat (" . ($i + 1) . "/" . $numFiles . ")\n";
    }
}

// Save metadata
$metadata = array(
    'blocks' => $numFiles,
    'block_size' => $blockSize,
    'total_size' => $totalSize,
    'created' => date('Y-m-d H:i:s')
);
file_put_contents("$dataDir/cache_metadata.json", json_encode($metadata));
echo "Cache data generation complete!\n";
EOF

    php ${SCRIPT_DIR}/generate_cache_data.php
else
    echo "Cache data files already exist"
fi

# Step 3: Setup MariaDB database
echo "Checking MariaDB setup..."
if ! pgrep -x "mysqld" > /dev/null; then
    echo "Starting MariaDB..."
    sudo systemctl start mariadb 2>/dev/null || \
    mysqld --datadir=/var/lib/mysql --socket=/tmp/mysql.sock --pid-file=/tmp/mysql.pid &
    sleep 5
fi

# Check if MediaWiki database exists
if ! mysql -e "USE mediawiki" 2>/dev/null; then
    echo "Creating MediaWiki database..."
    mysql -e "CREATE DATABASE IF NOT EXISTS mediawiki;"
    mysql -e "GRANT ALL PRIVILEGES ON mediawiki.* TO 'wiki'@'localhost' IDENTIFIED BY 'wiki123';"
    mysql -e "FLUSH PRIVILEGES;"
fi

# Step 4: Create MediaWiki LocalSettings.php if it doesn't exist
if [ ! -f "${MEDIAWIKI_ROOT}/LocalSettings.php" ]; then
    echo "Creating MediaWiki LocalSettings.php..."
    cat > ${MEDIAWIKI_ROOT}/LocalSettings.php << 'EOF'
<?php
# Basic MediaWiki configuration for HHVM testing
$wgSitename = "TestWiki";
$wgMetaNamespace = "TestWiki";
$wgScriptPath = "";
$wgServer = "http://localhost:8080";
$wgResourceBasePath = $wgScriptPath;
$wgLogo = "$wgResourceBasePath/resources/assets/wiki.png";
$wgEnableEmail = false;
$wgEnableUserEmail = false;
$wgDBtype = "mysql";
$wgDBserver = "localhost:/tmp/mysql.sock";
$wgDBname = "mediawiki";
$wgDBuser = "wiki";
$wgDBpassword = "wiki123";
$wgDBprefix = "";
$wgDBTableOptions = "ENGINE=InnoDB, DEFAULT CHARSET=binary";
$wgSharedTables[] = "actor";
$wgMainCacheType = CACHE_ACCEL;
$wgMemCachedServers = [];
$wgEnableUploads = false;
$wgUseInstantCommons = false;
$wgPingback = false;
$wgLanguageCode = "en";
$wgLocaltimezone = "UTC";
$wgSecretKey = "a8f5f167f44f4964e6c998dee827110c";
$wgAuthenticationTokenVersion = "1";
$wgSiteNotice = "HHVM Benchmark Test";
EOF
fi

# Step 5: Create workload generation scripts
echo "Creating workload scripts..."

# Create the Lua script for wrk
cat > ${SCRIPT_DIR}/mediawiki_varied.lua << 'EOF'
counter = 0
pages = {
    "/index.php?title=Main_Page",
    "/index.php?title=Special:Random",
    "/index.php?title=Special:RecentChanges",  
    "/index.php?title=Special:AllPages",
    "/index.php?title=Help:Contents",
    "/api.php?action=query&list=random&rnlimit=10",
}
request = function()
    counter = counter + 1
    local path = pages[(counter % #pages) + 1]
    return wrk.format("GET", path)
end
EOF

# Step 6: Generate HHVM configuration files for different memory sizes
for SIZE in 128; do
    cat > ${SCRIPT_DIR}/hhvm-64C-${SIZE}gb.ini << EOF
; HHVM ${SIZE}GB Memory Configuration
memory_limit = $((SIZE + 12))G
hhvm.server.memory_limit = $((SIZE + 12))G

; APC Cache - scales with memory size
hhvm.server.apc.memory_limit = $((SIZE * 1073741824))
hhvm.server.apc.enable_apc = true
hhvm.server.apc.table_type = concurrent
hhvm.server.apc.expire_on_sets = false
hhvm.server.apc.purge_frequency = 4294967295

; JIT Memory (scales with size)
hhvm.jit = true
hhvm.jit_a_size = $((SIZE * 85899345))           ; ~0.08 * SIZE GB
hhvm.jit_a_cold_size = $((SIZE * 42949672))     ; ~0.04 * SIZE GB
hhvm.jit_frozen_size = $((SIZE * 85899345))     ; ~0.08 * SIZE GB
hhvm.jit_data_size = $((SIZE * 85899345))       ; ~0.08 * SIZE GB

; Request handling
hhvm.server.thread_count = 64
hhvm.server.thread_round_robin = true
hhvm.server.request_memory_max_bytes = 2147483648

; Repo authoritative mode
hhvm.repo.authoritative = true
hhvm.repo.central.path = ${CACHE_DIR}/hhvm.hhbc

; Admin server
hhvm.admin_server.port = 8081
hhvm.admin_server.thread_count = 1

; Logging
hhvm.log.file = ${BASE_DIR}/logs/hhvm_${SIZE}gb.log
hhvm.log.level = Warning
EOF
done

echo "=== Setup Complete ==="
echo "Environment is ready for benchmark runs"
echo "Generated configs"
echo ""
echo "You can now run benchmarks with:"
echo "  ./run_hhvm_benchmark.sh <memory_size_gb> <experiment_name>"
