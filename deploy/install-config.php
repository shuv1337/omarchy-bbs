<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "CLI only.\n");
    exit(1);
}

$target = $argv[1] ?? null;
if (!$target || !str_starts_with($target, '/home/')) {
    fwrite(STDERR, "Usage: php install-config.php /home/USER/.config/omarchy-bbs.php\n");
    exit(1);
}

$password = trim((string)fgets(STDIN));
if ($password === '') {
    fwrite(STDERR, "Database password required on standard input.\n");
    exit(1);
}

$config = [
    'db_host' => 'localhost',
    'db_name' => 'thoupnrm_omarchy_bbs',
    'db_user' => 'thoupnrm_omarchy',
    'db_pass' => $password,
    'app_key' => bin2hex(random_bytes(32)),
];
$directory = dirname($target);
if (!is_dir($directory) && !mkdir($directory, 0700, true)) {
    throw new RuntimeException("Could not create config directory");
}
$content = "<?php\nreturn " . var_export($config, true) . ";\n";
if (file_put_contents($target, $content, LOCK_EX) === false || !chmod($target, 0600)) {
    throw new RuntimeException("Could not write secure config");
}
fwrite(STDOUT, "Configuration installed.\n");
