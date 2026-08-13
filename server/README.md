# RTT sync service

1. Point the domain/subdomain document root to `server/public/`.
2. Open `/installer.php` in the browser.
3. Install with a 32+ character sync key, or leave the field blank to generate one.
4. Save the sync key in RTT Remote Mode.
5. Delete `public/installer.php` after setup.

Manual setup still works: copy `config.example.php` to `config.php`, create `server/data/`, make it writable by PHP, and store only `password_hash($key, PASSWORD_DEFAULT)` in `config.php`.

`GET /?since=<ISO-8601>` downloads changed projects and entries. `POST /` uploads `projects` and `entries` arrays. Both require `Authorization: Bearer <sync-key>`.

The endpoint enforces HTTPS (when configured), a 1 MB request limit, 16 KB per record payload limit, UUID-like record IDs, and SQLite transactions. Deploy only `public/` as the document root; keep `config.php` and the SQLite file outside it.
