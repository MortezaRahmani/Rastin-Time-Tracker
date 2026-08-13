<?php

return [
    // Put config.php above your web root when hosting on cPanel.
    'database' => __DIR__ . '/data/rtt.sqlite3',
    // Set true in production. Reverse proxies must set X-Forwarded-Proto safely.
    'require_https' => true,
    // Generate once: password_hash('your-long-random-sync-key', PASSWORD_DEFAULT)
    'token_hash' => 'replace-with-password-hash',
];
