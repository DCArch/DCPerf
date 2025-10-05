<?php
// Generate 100GB of deterministic data and save to files
// Usage: php generate_cache_data.php <data_dir>

if ($argc < 2) {
    echo "Usage: php generate_cache_data.php <data_dir>\n";
    exit(1);
}

$dataDir = rtrim($argv[1], '/');
$totalSize = 100 * 1024 * 1024 * 1024; // 100GB
$blockSize = 1024 * 1024 * 1024;       // 1GB files
$numFiles = $totalSize / $blockSize;

// Create data directory if it doesn't exist
if (!is_dir($dataDir)) {
    mkdir($dataDir, 0755, true);
}

echo "Generating cache data files in $dataDir...\n";

for ($i = 0; $i < $numFiles; $i++) {
    $filename = "$dataDir/cache_block_$i.dat";
    if (!file_exists($filename)) {
        $data = str_repeat(md5($i), $blockSize / 32);
        file_put_contents($filename, $data);
        echo "Generated: cache_block_$i.dat (" . ($i + 1) . "/" . $numFiles . ")\n";
    } else {
        echo "Skipping existing: cache_block_$i.dat\n";
    }
}

// Save metadata
$metadata = array(
    'blocks' => $numFiles,
    'block_size' => $blockSize,
    'total_size' => $totalSize,
    'created' => date('Y-m-d H:i:s'),
    'data_dir' => $dataDir
);
file_put_contents("$dataDir/cache_metadata.json", json_encode($metadata, JSON_PRETTY_PRINT));
echo "Cache data generation complete!\n";
echo "Metadata saved to $dataDir/cache_metadata.json\n";
