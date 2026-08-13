<?php
declare(strict_types=1);

header('Content-Type: text/html; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('X-Robots-Tag: noindex, nofollow');

session_start();

$root = dirname(__DIR__);
$configPath = $root . '/config.php';
$schemaPath = $root . '/sql/schema.sql';
$databasePath = $root . '/data/rtt.sqlite3';
$errors = [];
$syncKey = '';
$installed = false;

function e(string $value): string {
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function configured(string $path): bool {
    if (!is_file($path)) return false;
    $config = require $path;
    return is_array($config)
        && isset($config['token_hash'])
        && is_string($config['token_hash'])
        && $config['token_hash'] !== 'replace-with-password-hash'
        && str_starts_with($config['token_hash'], '$');
}

function writeConfig(string $path, string $databasePath, bool $requireHttps, string $tokenHash): void {
    $php = "<?php\n\nreturn [\n"
        . "    'database' => " . var_export($databasePath, true) . ",\n"
        . "    'require_https' => " . ($requireHttps ? 'true' : 'false') . ",\n"
        . "    'token_hash' => " . var_export($tokenHash, true) . ",\n"
        . "];\n";
    if (file_put_contents($path, $php, LOCK_EX) === false) {
        throw new RuntimeException('Could not write config.php.');
    }
}

$alreadyConfigured = configured($configPath);
if (!$alreadyConfigured && empty($_SESSION['installer_csrf'])) {
    $_SESSION['installer_csrf'] = bin2hex(random_bytes(16));
}

if (!$alreadyConfigured && $_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        if (!hash_equals($_SESSION['installer_csrf'] ?? '', (string) ($_POST['csrf'] ?? ''))) {
            throw new RuntimeException('The installer form expired. Refresh and try again.');
        }
        if (!extension_loaded('pdo_sqlite')) {
            throw new RuntimeException('The PHP pdo_sqlite extension is not enabled.');
        }
        if (!is_file($schemaPath)) {
            throw new RuntimeException('Missing sql/schema.sql.');
        }
        $syncKey = trim((string) ($_POST['sync_key'] ?? ''));
        if ($syncKey === '') {
            $syncKey = rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
        }
        if (strlen($syncKey) < 32) {
            throw new RuntimeException('Use a sync key with at least 32 characters.');
        }
        if (!is_dir(dirname($databasePath)) && !mkdir(dirname($databasePath), 0775, true)) {
            throw new RuntimeException('Could not create the data directory.');
        }
        $pdo = new PDO('sqlite:' . $databasePath, null, null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        ]);
        $pdo->exec(file_get_contents($schemaPath));
        writeConfig(
            $configPath,
            $databasePath,
            !empty($_POST['require_https']),
            password_hash($syncKey, PASSWORD_DEFAULT),
        );
        unset($_SESSION['installer_csrf']);
        $installed = true;
    } catch (Throwable $error) {
        $errors[] = $error->getMessage();
    }
}

$ready = $installed || configured($configPath);
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>RTT Sync Installer</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0; background: Canvas; color: CanvasText; }
    main { max-width: 680px; margin: 48px auto; padding: 0 20px; }
    .card { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); border-radius: 14px; padding: 24px; }
    label { display: block; font-weight: 650; margin: 18px 0 6px; }
    input[type="text"] { box-sizing: border-box; width: 100%; padding: 12px; font: inherit; border-radius: 10px; border: 1px solid color-mix(in srgb, CanvasText 24%, transparent); }
    button { margin-top: 20px; padding: 12px 16px; border: 0; border-radius: 10px; font: inherit; font-weight: 700; background: #d97706; color: white; cursor: pointer; }
    code, output { overflow-wrap: anywhere; }
    .ok { color: #15803d; }
    .warn { color: #b45309; }
    .error { color: #b91c1c; }
    ul { padding-left: 20px; }
  </style>
</head>
<body>
<main>
  <h1>RTT Sync Installer</h1>
  <div class="card">
    <?php if ($ready): ?>
      <h2 class="ok">PHP sync is configured</h2>
      <p>Database: <code><?= e($databasePath) ?></code></p>
      <?php if ($installed): ?>
        <p>Your sync key is shown once. Save it in RTT Remote Mode:</p>
        <p><output><?= e($syncKey) ?></output></p>
      <?php endif; ?>
      <p class="warn">Delete <code>public/installer.php</code> after setup.</p>
    <?php else: ?>
      <?php if ($errors): ?>
        <h2 class="error">Install failed</h2>
        <ul><?php foreach ($errors as $error): ?><li><?= e($error) ?></li><?php endforeach; ?></ul>
      <?php endif; ?>
      <p>This creates <code>config.php</code>, initializes SQLite, and stores only a password hash of your sync key.</p>
      <form method="post">
        <input type="hidden" name="csrf" value="<?= e($_SESSION['installer_csrf']) ?>">
        <label for="sync_key">Sync key</label>
        <input id="sync_key" name="sync_key" type="text" minlength="32" autocomplete="off" placeholder="Leave blank to generate one">
        <label>
          <input name="require_https" type="checkbox" value="1" checked>
          Require HTTPS
        </label>
        <button type="submit">Install sync service</button>
      </form>
    <?php endif; ?>
  </div>
</main>
</body>
</html>
