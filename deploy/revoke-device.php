<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "CLI only.\n");
    exit(1);
}
$configPath = $argv[1] ?? '';
if (!is_file($configPath)) {
    fwrite(STDERR, "Usage: php revoke-device.php /path/to/config.php\n");
    exit(1);
}
$input = trim((string)stream_get_contents(STDIN));
$decoded = json_decode($input, true);
$deviceId = is_array($decoded) ? (string)($decoded['device_id'] ?? '') : $input;
if (!preg_match('/^[A-Za-z0-9_-]{16,64}$/', $deviceId)) {
    fwrite(STDERR, "Invalid device ID.\n");
    exit(1);
}
$config = require $configPath;
$pdo = new PDO(
    "mysql:host={$config['db_host']};dbname={$config['db_name']};charset=utf8mb4",
    $config['db_user'],
    $config['db_pass'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
$statement = $pdo->prepare('DELETE FROM devices WHERE id=?');
$statement->execute([$deviceId]);
fwrite(STDOUT, $statement->rowCount() === 1 ? "Device revoked.\n" : "Device was already absent.\n");
