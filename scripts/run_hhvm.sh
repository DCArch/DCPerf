#!/bin/bash

# Usage: ./run_hhvm_benchmark.sh <memory_size_gb> <experiment_name> [simulator_options]
# Example: ./run_hhvm_benchmark.sh 128 exp1_baseline "--cache-size=32MB"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <memory_size_gb> <experiment_name> [simulator_options]"
    echo "Example: $0 128 exp1_baseline \"--cache-size=32MB\""
    exit 1
fi

MEMORY_SIZE=$1
EXPERIMENT_NAME=$2
SIMULATOR_OPTIONS=${3:-""}

BASE_DIR="/work/mewais/DCArch/DCPerf"
HHVM_BIN="${BASE_DIR}/release/bin/hhvm"
MEDIAWIKI_ROOT="${BASE_DIR}/release"
SCRIPT_DIR="${BASE_DIR}/scripts"
CACHE_DIR="${BASE_DIR}/cache"
LOG_DIR="${BASE_DIR}/logs/${EXPERIMENT_NAME}"

# Create experiment-specific log directory
mkdir -p $LOG_DIR

echo "=== Running HHVM Benchmark ==="
echo "Memory Size: ${MEMORY_SIZE}GB"
echo "Experiment: ${EXPERIMENT_NAME}"
echo "Simulator Options: ${SIMULATOR_OPTIONS}"
echo "Logs: ${LOG_DIR}"

# Step 1: Ensure MariaDB is running
if ! pgrep -x "mysqld" > /dev/null; then
    echo "Starting MariaDB..."
    mysqld --datadir=/var/lib/mysql --socket=/tmp/mysql.sock --pid-file=/tmp/mysql.pid &
    sleep 5
fi

# Step 2: Create simulator communication flag
echo "0" > /tmp/hhvm_simulator_flag

# Step 3: Start HHVM under simulator
echo "Starting HHVM under simulator..."
simulator_command \
    --defer-measurement \
    --memory-size=$((MEMORY_SIZE + 20))G \
    ${SIMULATOR_OPTIONS} \
    --output-dir=${LOG_DIR} \
    $HHVM_BIN \
    -m server \
    -c ${SCRIPT_DIR}/hhvm-${MEMORY_SIZE}gb.ini \
    -p 8080 \
    -vServer.Type=proxygen \
    -vServer.SourceRoot=$MEDIAWIKI_ROOT \
    -vAdminServer.Port=8081 \
    -vLog.File=${LOG_DIR}/hhvm.log &

HHVM_PID=$!
echo $HHVM_PID > ${LOG_DIR}/hhvm.pid
echo "HHVM PID: $HHVM_PID"

# Step 4: Wait for HHVM to start
echo "Waiting for HHVM to start..."
for i in {1..60}; do
    if curl -s http://localhost:8080/index.php > /dev/null 2>&1; then
        echo "HHVM started successfully"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        echo "ERROR: HHVM failed to start"
        cat ${LOG_DIR}/hhvm.log
        exit 1
    fi
done

# Step 5: Fill memory with cached data
echo "Loading cache data into memory..."
cat > /tmp/load_cache.php << 'EOF'
<?php
$dataDir = '/work/mewais/DCArch/DCPerf/data';
$metadata = json_decode(file_get_contents("$dataDir/cache_metadata.json"), true);

echo "Loading " . $metadata['blocks'] . " cache blocks...\n";
for ($i = 0; $i < $metadata['blocks']; $i++) {
    $data = file_get_contents("$dataDir/cache_block_$i.dat");
    apc_store("memory_block_$i", $data, 0);
    if ($i % 10 == 0) {
        echo "Loaded " . ($i + 1) . "/" . $metadata['blocks'] . " blocks\n";
    }
}
echo "Cache loading complete!\n";
EOF

curl -X POST --data-binary @/tmp/load_cache.php http://localhost:8080/load_cache.php

# Step 6: Monitor memory growth
echo "Waiting for memory to stabilize..."
MEMORY_TARGET=$((MEMORY_SIZE * 9 / 10))  # Target 90% of configured size
for i in {1..120}; do
    RSS=$(ps -o rss= -p $HHVM_PID 2>/dev/null | awk '{print int($1/1048576)}')
    echo "Memory: ${RSS}GB / ${MEMORY_TARGET}GB target"
    
    if [ "$RSS" -ge "$MEMORY_TARGET" ]; then
        echo "Memory target reached: ${RSS}GB"
        break
    fi
    
    if [ $i -eq 120 ]; then
        echo "Warning: Memory target not reached after 10 minutes"
    fi
    sleep 5
done

# Step 7: Run warmup for JIT compilation
echo "Running JIT warmup..."
if command -v wrk &> /dev/null; then
    wrk -t32 -c200 -d30s --latency \
        -s ${SCRIPT_DIR}/mediawiki_varied.lua \
        http://localhost:8080/index.php > ${LOG_DIR}/warmup.txt
else
    for i in {1..1000}; do
        curl -s "http://localhost:8080/index.php?warmup=$i" > /dev/null &
        if [ $((i % 100)) -eq 0 ]; then
            wait
            echo "Warmup: $i/1000 requests"
        fi
    done
fi

# Step 8: Final memory check
RSS=$(ps -o rss= -p $HHVM_PID 2>/dev/null | awk '{print int($1/1048576)}')
echo "Memory before measurement: ${RSS}GB"
echo "Timestamp: $(date)" >> ${LOG_DIR}/benchmark_info.txt
echo "Memory at start: ${RSS}GB" >> ${LOG_DIR}/benchmark_info.txt

# Step 9: START SIMULATOR MEASUREMENT
echo "=== STARTING SIMULATOR MEASUREMENT ==="
curl http://localhost:8081/simulator-start
echo "1" > /tmp/hhvm_simulator_flag

# Step 10: Run benchmark
echo "Running benchmark workload..."
DURATION=${BENCHMARK_DURATION:-"10m"}
THREADS=${BENCHMARK_THREADS:-32}
CONNECTIONS=${BENCHMARK_CONNECTIONS:-200}

if command -v wrk &> /dev/null; then
    wrk -t${THREADS} -c${CONNECTIONS} -d${DURATION} \
        --latency \
        -s ${SCRIPT_DIR}/mediawiki_varied.lua \
        http://localhost:8080/index.php \
        | tee ${LOG_DIR}/results.txt
else
    echo "ERROR: wrk not found. Install wrk for proper benchmarking."
    exit 1
fi

# Step 11: Collect final stats
RSS_FINAL=$(ps -o rss= -p $HHVM_PID 2>/dev/null | awk '{print int($1/1048576)}')
echo "Memory at end: ${RSS_FINAL}GB" >> ${LOG_DIR}/benchmark_info.txt

# Step 12: Stop HHVM
echo "Stopping HHVM..."
kill $HHVM_PID 2>/dev/null
sleep 2
kill -9 $HHVM_PID 2>/dev/null

# Cleanup
rm -f /tmp/hhvm_simulator_flag
rm -f ${LOG_DIR}/hhvm.pid

echo "=== Benchmark Complete ==="
echo "Results saved to: ${LOG_DIR}/"
echo "  - results.txt: Benchmark results"
echo "  - hhvm.log: HHVM runtime log"
echo "  - benchmark_info.txt: Run metadata"
