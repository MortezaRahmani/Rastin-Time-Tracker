<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');

function respond(int $status, array $body): never {
    http_response_code($status);
    echo json_encode($body, JSON_THROW_ON_ERROR);
    exit;
}

function requestToken(): string {
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    return preg_match('/^Bearer\\s+(.+)$/i', $header, $matches) ? $matches[1] : '';
}

function requireHttps(array $config): void {
    if (empty($config['require_https'])) return;
    $https = ($_SERVER['HTTPS'] ?? '') === 'on'
        || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
    if (!$https) respond(400, ['error' => 'https_required']);
}

function parseTime(mixed $value): DateTimeImmutable|false {
    if (!is_string($value) || strlen($value) > 40) return false;
    try {
        return new DateTimeImmutable($value);
    } catch (Throwable) {
        return false;
    }
}

function validSyncId(mixed $value): bool {
    return is_string($value) && preg_match('/^[a-f0-9]{32}$/', $value) === 1;
}

function validText(mixed $value, int $limit): bool {
    return is_string($value) && strlen($value) <= $limit;
}

function validPausesJson(mixed $value): bool {
    if (!is_string($value) || strlen($value) > 16384) return false;
    try {
        return is_array(json_decode($value, true, 16, JSON_THROW_ON_ERROR));
    } catch (Throwable) {
        return false;
    }
}

function normalizeTime(string $value): string {
    return (new DateTimeImmutable($value))->format(DateTimeInterface::ATOM);
}

try {
    $config = require dirname(__DIR__) . '/config.php';
    requireHttps($config);
    if (!is_array($config) || !isset($config['database'], $config['token_hash'])
        || !password_verify(requestToken(), $config['token_hash'])) {
        respond(401, ['error' => 'unauthorized']);
    }

    $pdo = new PDO('sqlite:' . $config['database'], null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
    $pdo->exec(file_get_contents(dirname(__DIR__) . '/sql/schema.sql'));
    $columns = $pdo->query('PRAGMA table_info(entries)')->fetchAll();
    $columnNames = array_column($columns, 'name');
    if (!in_array('pauses_json', $columnNames, true)) {
        $pdo->exec("ALTER TABLE entries ADD COLUMN pauses_json TEXT NOT NULL DEFAULT '[]'");
    }

    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        $since = $_GET['since'] ?? '1970-01-01T00:00:00+00:00';
        $time = parseTime($since);
        if (!$time) respond(400, ['error' => 'invalid_since']);
        $cursor = $time->format(DateTimeInterface::ATOM);
        $projects = $pdo->prepare('SELECT sync_id, name, color, created_at, updated_at, deleted_at FROM projects WHERE updated_at > ? ORDER BY updated_at, sync_id');
        $entries = $pdo->prepare('SELECT sync_id, project_sync_id, started_at, ended_at, title, description, pauses_json, created_at, updated_at, deleted_at FROM entries WHERE updated_at > ? ORDER BY updated_at, sync_id');
        $projects->execute([$cursor]);
        $entries->execute([$cursor]);
        respond(200, [
            'projects' => array_map(static fn(array $row) => [
                'syncId' => $row['sync_id'],
                'name' => $row['name'],
                'color' => (int) $row['color'],
                'createdAt' => $row['created_at'],
                'updatedAt' => $row['updated_at'],
                'deletedAt' => $row['deleted_at'],
            ], $projects->fetchAll()),
            'entries' => array_map(static fn(array $row) => [
                'syncId' => $row['sync_id'],
                'projectSyncId' => $row['project_sync_id'],
                'startedAt' => $row['started_at'],
                'endedAt' => $row['ended_at'],
                'title' => $row['title'],
                'description' => $row['description'],
                'pausesJson' => $row['pauses_json'],
                'createdAt' => $row['created_at'],
                'updatedAt' => $row['updated_at'],
                'deletedAt' => $row['deleted_at'],
            ], $entries->fetchAll()),
            'cursor' => gmdate(DATE_ATOM),
        ]);
    }

    if ($_SERVER['REQUEST_METHOD'] !== 'POST') respond(405, ['error' => 'method_not_allowed']);
    if ((int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > 1_000_000) {
        respond(413, ['error' => 'payload_too_large']);
    }
    $body = json_decode(file_get_contents('php://input'), true, 32, JSON_THROW_ON_ERROR);
    if (!is_array($body) || !isset($body['projects'], $body['entries'])
        || !is_array($body['projects']) || !is_array($body['entries'])
        || count($body['projects']) > 500 || count($body['entries']) > 1000) {
        respond(400, ['error' => 'invalid_payload']);
    }

    $upsertProject = $pdo->prepare('INSERT INTO projects (sync_id, name, color, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(sync_id) DO UPDATE SET name = excluded.name, color = excluded.color, created_at = excluded.created_at, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
      WHERE excluded.updated_at > projects.updated_at');
    $upsertEntry = $pdo->prepare('INSERT INTO entries (sync_id, project_sync_id, started_at, ended_at, title, description, pauses_json, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(sync_id) DO UPDATE SET project_sync_id = excluded.project_sync_id, started_at = excluded.started_at, ended_at = excluded.ended_at, title = excluded.title, description = excluded.description, pauses_json = excluded.pauses_json, created_at = excluded.created_at, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
      WHERE excluded.updated_at > entries.updated_at');

    $pdo->beginTransaction();
    foreach ($body['projects'] as $project) {
        if (!is_array($project) || !validSyncId($project['syncId'] ?? null)
            || !validText($project['name'] ?? null, 240)
            || !is_int($project['color'] ?? null)
            || !parseTime($project['createdAt'] ?? null)
            || !parseTime($project['updatedAt'] ?? null)
            || (($project['deletedAt'] ?? null) !== null && !parseTime($project['deletedAt']))) {
            $pdo->rollBack(); respond(400, ['error' => 'invalid_project']);
        }
        $upsertProject->execute([
            $project['syncId'],
            $project['name'],
            $project['color'],
            normalizeTime($project['createdAt']),
            normalizeTime($project['updatedAt']),
            isset($project['deletedAt']) && $project['deletedAt'] !== null ? normalizeTime($project['deletedAt']) : null,
        ]);
    }
    foreach ($body['entries'] as $entry) {
        if (!is_array($entry) || !validSyncId($entry['syncId'] ?? null)
            || !validSyncId($entry['projectSyncId'] ?? null)
            || !validText($entry['title'] ?? null, 240)
            || !validText($entry['description'] ?? null, 4096)
            || !validPausesJson($entry['pausesJson'] ?? '[]')
            || !parseTime($entry['startedAt'] ?? null)
            || !parseTime($entry['createdAt'] ?? null)
            || !parseTime($entry['updatedAt'] ?? null)
            || (($entry['endedAt'] ?? null) !== null && !parseTime($entry['endedAt']))
            || (($entry['deletedAt'] ?? null) !== null && !parseTime($entry['deletedAt']))) {
            $pdo->rollBack(); respond(400, ['error' => 'invalid_entry']);
        }
        $upsertEntry->execute([
            $entry['syncId'],
            $entry['projectSyncId'],
            normalizeTime($entry['startedAt']),
            isset($entry['endedAt']) && $entry['endedAt'] !== null ? normalizeTime($entry['endedAt']) : null,
            $entry['title'],
            $entry['description'],
            $entry['pausesJson'] ?? '[]',
            normalizeTime($entry['createdAt']),
            normalizeTime($entry['updatedAt']),
            isset($entry['deletedAt']) && $entry['deletedAt'] !== null ? normalizeTime($entry['deletedAt']) : null,
        ]);
    }
    $pdo->commit();
    respond(200, ['cursor' => gmdate(DATE_ATOM)]);
} catch (Throwable $error) {
    error_log('RTT sync error: ' . $error->getMessage());
    respond(500, ['error' => 'server_error']);
}
