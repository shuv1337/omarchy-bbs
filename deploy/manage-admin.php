<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "CLI only.\n");
    exit(1);
}

[$script, $configPath, $action, $handle] = array_pad($argv, 4, null);
if (!$configPath || $configPath[0] !== '/' || !is_file($configPath) ||
    !in_array($action, ['promote', 'demote'], true) ||
    !is_string($handle) || !preg_match('/^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$/', $handle)) {
    fwrite(STDERR, "Usage: php manage-admin.php /absolute/path/to/config.php promote|demote handle\n");
    exit(1);
}

$config = require $configPath;
if (($config['driver'] ?? 'mysql') === 'sqlite') {
    $pdo = new PDO('sqlite:' . $config['db_path']);
} else {
    $pdo = new PDO(
        "mysql:host={$config['db_host']};dbname={$config['db_name']};charset=utf8mb4",
        $config['db_user'],
        $config['db_pass']
    );
}
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);

$pdo->beginTransaction();
try {
    $query = $pdo->prepare('SELECT id, role FROM users WHERE handle=?');
    $query->execute([$handle]);
    $user = $query->fetch(PDO::FETCH_ASSOC);
    if (!$user) {
        throw new RuntimeException("User @$handle was not found");
    }

    if ($action === 'promote') {
        $pdo->prepare("UPDATE users SET role='admin' WHERE id=?")->execute([$user['id']]);
    } else {
        $admins = (int)$pdo->query("SELECT COUNT(*) FROM users WHERE role='admin'")->fetchColumn();
        if ($user['role'] === 'admin' && $admins <= 1) {
            throw new RuntimeException('Refusing to remove the final administrator');
        }
        $pdo->prepare("UPDATE users SET role='member' WHERE id=?")->execute([$user['id']]);
    }

    $pdo->commit();
    fwrite(STDOUT, "@$handle is now " . ($action === 'promote' ? 'an administrator' : 'a member') . ".\n");
} catch (Throwable $error) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    fwrite(STDERR, $error->getMessage() . "\n");
    exit(1);
}
