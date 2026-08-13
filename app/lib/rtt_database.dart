import 'dart:ffi';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

class RttDatabase {
  RttDatabase._(this._database, this.path);

  final Database _database;
  final String path;

  static Future<RttDatabase> open() async {
    final preferred = await preferredPath();
    return openPath(preferred ?? await defaultPath());
  }

  static Future<RttDatabase> openPath(String path) async {
    _configurePlatformLibrary();
    return _initialize(sqlite3.open(path), path);
  }

  static Future<String> defaultPath() async {
    if (Platform.isWindows) {
      final portable = await _portableDirectory();
      if (portable != null) {
        return '${portable.path}${Platform.pathSeparator}rtt.sqlite3';
      }
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        final directory = Directory('$appData${Platform.pathSeparator}RTT');
        await directory.create(recursive: true);
        return '${directory.path}${Platform.pathSeparator}rtt.sqlite3';
      }
    }
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}${Platform.pathSeparator}rtt.sqlite3';
  }

  static Future<String?> preferredPath() async {
    final file = await _pathPreferenceFile();
    if (!await file.exists()) return null;
    final path = (await file.readAsString()).trim();
    return path.isEmpty ? null : path;
  }

  static Future<void> setPreferredPath(String path) async {
    final file = await _pathPreferenceFile();
    await file.writeAsString(path, flush: true);
  }

  static Future<File> _pathPreferenceFile() async {
    final portable = Platform.isWindows ? await _portableDirectory() : null;
    if (portable != null) {
      return File(
        '${portable.path}${Platform.pathSeparator}rtt_database_path.txt',
      );
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        final directory = Directory('$appData${Platform.pathSeparator}RTT');
        await directory.create(recursive: true);
        return File(
          '${directory.path}${Platform.pathSeparator}rtt_database_path.txt',
        );
      }
    }
    final directory = await getApplicationDocumentsDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}rtt_database_path.txt',
    );
  }

  static Future<Directory?> _portableDirectory() async {
    final directory = File(Platform.resolvedExecutable).parent;
    final marker = File(
      '${directory.path}${Platform.pathSeparator}portable.flag',
    );
    return await marker.exists() ? directory : null;
  }

  static RttDatabase inMemory() {
    _configurePlatformLibrary();
    return _initialize(sqlite3.openInMemory(), ':memory:');
  }

  static void _configurePlatformLibrary() {
    if (Platform.isWindows) {
      sqlite_open.open.overrideFor(
        sqlite_open.OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
    if (Platform.isAndroid) {
      sqlite_open.open.overrideFor(
        sqlite_open.OperatingSystem.android,
        () => DynamicLibrary.open('libsqlite3.so'),
      );
    }
  }

  static RttDatabase _initialize(Database database, String path) {
    database.execute('PRAGMA foreign_keys = ON;');
    database.execute('PRAGMA journal_mode = WAL;');
    database.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY,
        sync_id TEXT NOT NULL UNIQUE CHECK (length(sync_id) = 32),
        name TEXT NOT NULL UNIQUE,
        color INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      );
      CREATE TABLE IF NOT EXISTS entries (
        id INTEGER PRIMARY KEY,
        sync_id TEXT NOT NULL UNIQUE CHECK (length(sync_id) = 32),
        project_id INTEGER NOT NULL REFERENCES projects(id),
        started_at TEXT NOT NULL,
        ended_at TEXT,
        title TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        pauses_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        CHECK (ended_at IS NULL OR ended_at > started_at)
      );
      CREATE UNIQUE INDEX IF NOT EXISTS one_running_entry
        ON entries ((1)) WHERE ended_at IS NULL AND deleted_at IS NULL;
      CREATE INDEX IF NOT EXISTS entries_project_started_at
        ON entries(project_id, started_at DESC) WHERE deleted_at IS NULL;
      CREATE INDEX IF NOT EXISTS entries_updated_at ON entries(updated_at);
      CREATE INDEX IF NOT EXISTS projects_updated_at ON projects(updated_at);
      CREATE TABLE IF NOT EXISTS app_preferences (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        color_mode TEXT NOT NULL DEFAULT 'dark'
          CHECK (color_mode IN ('dark', 'light', 'system')),
        sync_mode TEXT NOT NULL DEFAULT 'local'
          CHECK (sync_mode IN ('local', 'remote')),
        font_size TEXT NOT NULL DEFAULT 'normal'
          CHECK (font_size IN ('tiny', 'small', 'normal', 'large', 'huge')),
        break_reminder_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (break_reminder_enabled IN (0, 1)),
        break_reminder_minutes INTEGER NOT NULL DEFAULT 30
          CHECK (break_reminder_minutes BETWEEN 1 AND 1440),
        reminder_sound_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (reminder_sound_enabled IN (0, 1)),
        reminder_sound_path TEXT,
        minimize_to_tray INTEGER NOT NULL DEFAULT 0
          CHECK (minimize_to_tray IN (0, 1)),
        local_database_path TEXT
      );
      CREATE TABLE IF NOT EXISTS sync_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        endpoint TEXT,
        cursor TEXT,
        last_sync_at TEXT,
        last_status TEXT,
        last_error TEXT
      );
      INSERT OR IGNORE INTO app_preferences (id) VALUES (1);
      INSERT OR IGNORE INTO sync_state (id) VALUES (1);
    ''');
    _migrateOldTables(database);
    return RttDatabase._(database, path);
  }

  void close() => _database.dispose();

  static void _migrateOldTables(Database database) {
    _ensureColumn(database, 'projects', 'sync_id', 'TEXT');
    _ensureColumn(database, 'projects', 'created_at', 'TEXT');
    _ensureColumn(database, 'projects', 'updated_at', 'TEXT');
    _ensureColumn(database, 'projects', 'deleted_at', 'TEXT');
    _ensureColumn(database, 'entries', 'sync_id', 'TEXT');
    _ensureColumn(database, 'entries', 'title', "TEXT NOT NULL DEFAULT ''");
    _ensureColumn(
      database,
      'entries',
      'pauses_json',
      "TEXT NOT NULL DEFAULT '[]'",
    );
    _ensureColumn(database, 'entries', 'created_at', 'TEXT');
    _ensureColumn(database, 'entries', 'updated_at', 'TEXT');
    _ensureColumn(database, 'entries', 'deleted_at', 'TEXT');
    _ensureColumn(
      database,
      'app_preferences',
      'font_size',
      "TEXT NOT NULL DEFAULT 'normal'",
    );
    _ensureColumn(
      database,
      'app_preferences',
      'break_reminder_enabled',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn(
      database,
      'app_preferences',
      'break_reminder_minutes',
      'INTEGER NOT NULL DEFAULT 30',
    );
    _ensureColumn(
      database,
      'app_preferences',
      'reminder_sound_enabled',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn(database, 'app_preferences', 'reminder_sound_path', 'TEXT');
    _ensureColumn(
      database,
      'app_preferences',
      'minimize_to_tray',
      'INTEGER NOT NULL DEFAULT 0',
    );
    database.execute('''
      UPDATE projects
      SET sync_id = lower(hex(randomblob(16))),
          created_at = COALESCE(created_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          updated_at = COALESCE(updated_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
      WHERE sync_id IS NULL OR created_at IS NULL OR updated_at IS NULL;
      UPDATE entries
      SET sync_id = lower(hex(randomblob(16))),
          created_at = COALESCE(created_at, started_at),
          updated_at = COALESCE(updated_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
      WHERE sync_id IS NULL OR created_at IS NULL OR updated_at IS NULL;
    ''');
  }

  static void _ensureColumn(
    Database database,
    String table,
    String name,
    String definition,
  ) {
    final names = database
        .select('PRAGMA table_info($table)')
        .map((column) => column['name'] as String)
        .toSet();
    if (!names.contains(name)) {
      database.execute('ALTER TABLE $table ADD COLUMN $name $definition');
    }
  }

  List<Project> projects() => _database
      .select(
        'SELECT id, name, color FROM projects WHERE deleted_at IS NULL ORDER BY name COLLATE NOCASE',
      )
      .map(
        (row) => Project(
          id: row['id'] as int,
          name: row['name'] as String,
          color: row['color'] as int,
        ),
      )
      .toList();

  Project addProject(String name, {int color = 0xffd97706}) {
    final now = _now();
    final trimmed = name.trim();
    _database.execute(
      '''INSERT INTO projects
         (sync_id, name, color, created_at, updated_at)
         VALUES (lower(hex(randomblob(16))), ?, ?, ?, ?)''',
      [trimmed, color, now, now],
    );
    return Project(id: _database.lastInsertRowId, name: trimmed, color: color);
  }

  Project updateProject(Project project, String name) {
    final trimmed = name.trim();
    _database.execute(
      'UPDATE projects SET name = ?, updated_at = ? WHERE id = ?',
      [trimmed, _now(), project.id],
    );
    return Project(id: project.id, name: trimmed, color: project.color);
  }

  void deleteProject(Project project) {
    final now = _now();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'UPDATE entries SET deleted_at = ?, updated_at = ? WHERE project_id = ?',
        [now, now, project.id],
      );
      _database.execute(
        'UPDATE projects SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [now, now, project.id],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  TimeEntry? runningEntry() {
    final rows = _database.select(_entryQuery('WHERE e.ended_at IS NULL'));
    return rows.isEmpty ? null : _entry(rows.single);
  }

  List<TimeEntry> recentEntries(Project project) => _database
      .select(
        '${_entryQuery('WHERE e.project_id = ?')} ORDER BY e.started_at DESC LIMIT 20',
        [project.id],
      )
      .map(_entry)
      .toList();

  List<TimeEntry> entriesForProject(Project project) => _database
      .select(
        '${_entryQuery('WHERE e.project_id = ?')} ORDER BY e.started_at DESC',
        [project.id],
      )
      .map(_entry)
      .toList();

  List<TimeEntry> allEntries() => _database
      .select(
        '${_entryQuery('')} ORDER BY p.name COLLATE NOCASE, e.started_at DESC',
      )
      .map(_entry)
      .toList();

  String? setting(String key) => switch (key) {
    'color_mode' => _single(
      'SELECT color_mode FROM app_preferences WHERE id = 1',
    ),
    'sync_mode' => _single(
      'SELECT sync_mode FROM app_preferences WHERE id = 1',
    ),
    'font_size' => _single(
      'SELECT font_size FROM app_preferences WHERE id = 1',
    ),
    'break_reminder_enabled' => _single(
      'SELECT break_reminder_enabled FROM app_preferences WHERE id = 1',
    ),
    'break_reminder_minutes' => _single(
      'SELECT break_reminder_minutes FROM app_preferences WHERE id = 1',
    ),
    'reminder_sound_enabled' => _single(
      'SELECT reminder_sound_enabled FROM app_preferences WHERE id = 1',
    ),
    'reminder_sound_path' => _single(
      'SELECT reminder_sound_path FROM app_preferences WHERE id = 1',
    ),
    'minimize_to_tray' => _single(
      'SELECT minimize_to_tray FROM app_preferences WHERE id = 1',
    ),
    'sync_endpoint' => _single('SELECT endpoint FROM sync_state WHERE id = 1'),
    'sync_cursor' => _single('SELECT cursor FROM sync_state WHERE id = 1'),
    'last_sync_at' => _single(
      'SELECT last_sync_at FROM sync_state WHERE id = 1',
    ),
    'last_sync_status' => _single(
      'SELECT last_status FROM sync_state WHERE id = 1',
    ),
    'last_sync_error' => _single(
      'SELECT last_error FROM sync_state WHERE id = 1',
    ),
    _ => null,
  };

  void setSetting(String key, String value) {
    switch (key) {
      case 'color_mode':
        _database.execute(
          'UPDATE app_preferences SET color_mode = ? WHERE id = 1',
          [value],
        );
      case 'sync_mode':
        _database.execute(
          'UPDATE app_preferences SET sync_mode = ? WHERE id = 1',
          [value],
        );
      case 'font_size':
        _database.execute(
          'UPDATE app_preferences SET font_size = ? WHERE id = 1',
          [value],
        );
      case 'break_reminder_enabled':
        _database.execute(
          'UPDATE app_preferences SET break_reminder_enabled = ? WHERE id = 1',
          [value == 'true' ? 1 : 0],
        );
      case 'break_reminder_minutes':
        _database.execute(
          'UPDATE app_preferences SET break_reminder_minutes = ? WHERE id = 1',
          [int.tryParse(value) ?? 30],
        );
      case 'reminder_sound_enabled':
        _database.execute(
          'UPDATE app_preferences SET reminder_sound_enabled = ? WHERE id = 1',
          [value == 'true' ? 1 : 0],
        );
      case 'reminder_sound_path':
        _database.execute(
          'UPDATE app_preferences SET reminder_sound_path = ? WHERE id = 1',
          [value.isEmpty ? null : value],
        );
      case 'minimize_to_tray':
        _database.execute(
          'UPDATE app_preferences SET minimize_to_tray = ? WHERE id = 1',
          [value == 'true' ? 1 : 0],
        );
      case 'sync_endpoint':
        _database.execute('UPDATE sync_state SET endpoint = ? WHERE id = 1', [
          value,
        ]);
      case 'sync_cursor':
        _database.execute('UPDATE sync_state SET cursor = ? WHERE id = 1', [
          value,
        ]);
      case 'last_sync_at':
        _database.execute(
          'UPDATE sync_state SET last_sync_at = ? WHERE id = 1',
          [value],
        );
      case 'last_sync_status':
        _database.execute(
          'UPDATE sync_state SET last_status = ? WHERE id = 1',
          [value],
        );
      case 'last_sync_error':
        _database.execute('UPDATE sync_state SET last_error = ? WHERE id = 1', [
          value,
        ]);
      default:
        throw ArgumentError.value(key, 'key', 'Unknown setting key.');
    }
  }

  Map<String, Object?> syncPayload() => {
    'projects': _database
        .select('''
      SELECT sync_id, name, color, created_at, updated_at, deleted_at
      FROM projects
      WHERE sync_id IS NOT NULL AND updated_at IS NOT NULL
    ''')
        .map(
          (row) => <String, Object?>{
            'syncId': row['sync_id'] as String,
            'name': row['name'] as String,
            'color': row['color'] as int,
            'createdAt': row['created_at'] as String,
            'updatedAt': row['updated_at'] as String,
            'deletedAt': row['deleted_at'] as String?,
          },
        )
        .toList(),
    'entries': _database
        .select('''
      SELECT e.sync_id, p.sync_id AS project_sync_id, e.started_at,
             e.ended_at, e.title, e.description, e.pauses_json,
             e.created_at, e.updated_at, e.deleted_at
      FROM entries e JOIN projects p ON p.id = e.project_id
      WHERE e.sync_id IS NOT NULL AND e.updated_at IS NOT NULL
    ''')
        .map(
          (row) => <String, Object?>{
            'syncId': row['sync_id'] as String,
            'projectSyncId': row['project_sync_id'] as String,
            'startedAt': row['started_at'] as String,
            'endedAt': row['ended_at'] as String?,
            'title': row['title'] as String,
            'description': row['description'] as String,
            'pausesJson': row['pauses_json'] as String,
            'createdAt': row['created_at'] as String,
            'updatedAt': row['updated_at'] as String,
            'deletedAt': row['deleted_at'] as String?,
          },
        )
        .toList(),
  };

  int mergeSyncPayload(Map body) {
    var conflicts = 0;
    final projects = body['projects'];
    final entries = body['entries'];
    _database.execute('BEGIN IMMEDIATE');
    try {
      if (projects is List) {
        for (final project in projects) {
          if (project is Map) conflicts += _mergeProject(project);
        }
      }
      if (entries is List) {
        for (final entry in entries) {
          if (entry is Map) conflicts += _mergeEntry(entry);
        }
      }
      _database.execute('COMMIT');
      return conflicts;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  TimeEntry start(Project project, String title, String description) {
    final now = _now();
    _database.execute(
      '''INSERT INTO entries
         (sync_id, project_id, started_at, title, description, created_at,
          updated_at)
         VALUES (lower(hex(randomblob(16))), ?, ?, ?, ?, ?, ?)''',
      [
        project.id,
        DateTime.now().toUtc().toIso8601String(),
        title.trim(),
        description.trim(),
        now,
        now,
      ],
    );
    return runningEntry()!;
  }

  void addEntry(
    Project project,
    DateTime startedAt,
    DateTime endedAt,
    String title,
    String description,
  ) {
    if (!endedAt.isAfter(startedAt)) {
      throw ArgumentError('End time must be after start time.');
    }
    final now = _now();
    _database.execute(
      '''INSERT INTO entries
         (sync_id, project_id, started_at, ended_at, title, description,
          created_at, updated_at)
         VALUES (lower(hex(randomblob(16))), ?, ?, ?, ?, ?, ?, ?)''',
      [
        project.id,
        startedAt.toUtc().toIso8601String(),
        endedAt.toUtc().toIso8601String(),
        title.trim(),
        description.trim(),
        now,
        now,
      ],
    );
  }

  void stop(TimeEntry entry) {
    final endedAt = DateTime.now().toUtc();
    final pauses = _pausedRangesForEntry(entry.id);
    if (pauses.isNotEmpty && pauses.last['pause_end'] == null) {
      pauses[pauses.length - 1] = _closedPause(pauses.last, endedAt);
    }
    _database.execute(
      '''UPDATE entries
         SET ended_at = ?, pauses_json = ?, updated_at = ?
         WHERE id = ? AND ended_at IS NULL''',
      [endedAt.toIso8601String(), jsonEncode(pauses), _now(), entry.id],
    );
  }

  void pause(TimeEntry entry) {
    if (!entry.isRunning || entry.isPaused) return;
    final pauses = _pausedRangesForEntry(entry.id);
    pauses.add({
      'pause_start': DateTime.now().toUtc().toIso8601String(),
      'pause_end': null,
      'pause_duration': null,
    });
    _database.execute(
      'UPDATE entries SET pauses_json = ?, updated_at = ? WHERE id = ? AND ended_at IS NULL',
      [jsonEncode(pauses), _now(), entry.id],
    );
  }

  void resume(TimeEntry entry) {
    if (!entry.isRunning || !entry.isPaused) return;
    final pauses = _pausedRangesForEntry(entry.id);
    if (pauses.isEmpty || pauses.last['pause_end'] != null) return;
    pauses[pauses.length - 1] = _closedPause(
      pauses.last,
      DateTime.now().toUtc(),
    );
    _database.execute(
      'UPDATE entries SET pauses_json = ?, updated_at = ? WHERE id = ? AND ended_at IS NULL',
      [jsonEncode(pauses), _now(), entry.id],
    );
  }

  void updateEntry(
    TimeEntry entry,
    Project project,
    DateTime startedAt,
    DateTime endedAt,
    String title,
    String description,
  ) {
    if (!endedAt.isAfter(startedAt)) {
      throw ArgumentError('End time must be after start time.');
    }
    _database.execute(
      '''UPDATE entries
         SET project_id = ?, started_at = ?, ended_at = ?, title = ?,
             description = ?, updated_at = ?
         WHERE id = ?''',
      [
        project.id,
        startedAt.toUtc().toIso8601String(),
        endedAt.toUtc().toIso8601String(),
        title.trim(),
        description.trim(),
        _now(),
        entry.id,
      ],
    );
  }

  void deleteEntry(TimeEntry entry) {
    final now = _now();
    _database.execute(
      'UPDATE entries SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, entry.id],
    );
  }

  String? _single(String sql, [List<Object?> parameters = const []]) {
    final rows = _database.select(sql, parameters);
    if (rows.isEmpty) return null;
    final value = rows.single.values.first;
    return value?.toString();
  }

  int _mergeProject(Map record) {
    final syncId = record['syncId'];
    final updatedAt = record['updatedAt'];
    final createdAt = record['createdAt'];
    if (!_validSyncId(syncId) || updatedAt is! String || createdAt is! String) {
      return 1;
    }
    final existing = _database.select(
      'SELECT id, updated_at FROM projects WHERE sync_id = ?',
      [syncId],
    );
    if (existing.isNotEmpty && !_newer(updatedAt, existing.single)) return 0;
    final deletedAt = record['deletedAt'];
    if (deletedAt != null && deletedAt is! String) return 1;
    final nameValue = record['name'];
    final color = record['color'];
    if (deletedAt == null && (nameValue is! String || color is! int)) return 1;
    final name = _uniqueProjectName(
      nameValue is String && nameValue.trim().isNotEmpty
          ? nameValue
          : 'Remote project',
      syncId as String,
    );
    final projectColor = color is int ? color : 0xffd97706;
    if (existing.isEmpty) {
      _database.execute(
        '''INSERT INTO projects
           (sync_id, name, color, created_at, updated_at, deleted_at)
           VALUES (?, ?, ?, ?, ?, ?)''',
        [syncId, name, projectColor, createdAt, updatedAt, deletedAt],
      );
    } else {
      _database.execute(
        '''UPDATE projects
           SET name = ?, color = ?, created_at = ?, updated_at = ?,
               deleted_at = ?
           WHERE sync_id = ?''',
        [name, projectColor, createdAt, updatedAt, deletedAt, syncId],
      );
    }
    return 0;
  }

  int _mergeEntry(Map record) {
    final syncId = record['syncId'];
    final projectSyncId = record['projectSyncId'];
    final startedAt = record['startedAt'];
    final updatedAt = record['updatedAt'];
    final createdAt = record['createdAt'];
    if (!_validSyncId(syncId) ||
        !_validSyncId(projectSyncId) ||
        startedAt is! String ||
        updatedAt is! String ||
        createdAt is! String) {
      return 1;
    }
    final existing = _database.select(
      'SELECT id, updated_at FROM entries WHERE sync_id = ?',
      [syncId],
    );
    if (existing.isNotEmpty && !_newer(updatedAt, existing.single)) return 0;
    final project = _database.select(
      'SELECT id FROM projects WHERE sync_id = ?',
      [projectSyncId],
    );
    if (project.isEmpty) return 1;
    final endedAt = record['endedAt'];
    final deletedAt = record['deletedAt'];
    if ((endedAt != null && endedAt is! String) ||
        (deletedAt != null && deletedAt is! String) ||
        record['title'] is! String ||
        record['description'] is! String ||
        !_validPausesJson(record['pausesJson'])) {
      return 1;
    }
    if (endedAt == null && deletedAt == null) {
      final running = _database.select(
        'SELECT id FROM entries WHERE ended_at IS NULL AND deleted_at IS NULL AND sync_id IS NOT ?',
        [syncId],
      );
      if (running.isNotEmpty) return 1;
    }
    final values = [
      project.single['id'],
      startedAt,
      endedAt,
      record['title'],
      record['description'],
      record['pausesJson'] ?? '[]',
      createdAt,
      updatedAt,
      deletedAt,
    ];
    if (existing.isEmpty) {
      _database.execute(
        '''INSERT INTO entries
           (sync_id, project_id, started_at, ended_at, title, description,
            pauses_json, created_at, updated_at, deleted_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [syncId, ...values],
      );
    } else {
      _database.execute(
        '''UPDATE entries
           SET project_id = ?, started_at = ?, ended_at = ?, title = ?,
               description = ?, pauses_json = ?, created_at = ?, updated_at = ?,
               deleted_at = ?
           WHERE sync_id = ?''',
        [...values, syncId],
      );
    }
    return 0;
  }

  bool _newer(String updatedAt, Row row) {
    final local = row['updated_at'];
    return local is! String ||
        DateTime.parse(updatedAt).isAfter(DateTime.parse(local));
  }

  bool _validSyncId(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

  bool _validPausesJson(Object? value) {
    if (value == null) return true;
    if (value is! String || value.length > 16384) return false;
    try {
      return jsonDecode(value) is List;
    } catch (_) {
      return false;
    }
  }

  String _uniqueProjectName(String name, String syncId) {
    final trimmed = name.trim().isEmpty ? 'Remote project' : name.trim();
    var candidate = trimmed;
    var suffix = 2;
    while (_database.select(
      'SELECT 1 FROM projects WHERE name = ? COLLATE NOCASE AND sync_id IS NOT ?',
      [candidate, syncId],
    ).isNotEmpty) {
      candidate = '$trimmed ($suffix)';
      suffix++;
    }
    return candidate;
  }

  String _entryQuery(String where) =>
      '''
    SELECT e.id, e.started_at, e.ended_at, e.title, e.description,
           e.pauses_json,
           p.id AS project_id, p.name AS project_name, p.color AS project_color
    FROM entries e JOIN projects p ON p.id = e.project_id
    ${where.isEmpty ? 'WHERE e.deleted_at IS NULL AND p.deleted_at IS NULL' : '$where AND e.deleted_at IS NULL AND p.deleted_at IS NULL'}
  ''';

  TimeEntry _entry(Row row) => TimeEntry(
    id: row['id'] as int,
    project: Project(
      id: row['project_id'] as int,
      name: row['project_name'] as String,
      color: row['project_color'] as int,
    ),
    title: row['title'] as String,
    startedAt: DateTime.parse(row['started_at'] as String).toLocal(),
    endedAt: row['ended_at'] == null
        ? null
        : DateTime.parse(row['ended_at'] as String).toLocal(),
    description: row['description'] as String,
    pauses: _parsePauses(row['pauses_json'] as String? ?? '[]'),
  );

  static List<PauseInterval> _parsePauses(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) {
            final startedAt = item['pause_start'];
            final endedAt = item['pause_end'];
            if (startedAt is! String) return null;
            return PauseInterval(
              startedAt: DateTime.parse(startedAt).toLocal(),
              endedAt: endedAt is String
                  ? DateTime.parse(endedAt).toLocal()
                  : null,
            );
          })
          .whereType<PauseInterval>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, Object?>> _pausedRangesForEntry(int entryId) {
    final rows = _database.select(
      'SELECT pauses_json FROM entries WHERE id = ?',
      [entryId],
    );
    if (rows.isEmpty) return [];
    try {
      final decoded = jsonDecode(rows.single['pauses_json'] as String? ?? '[]');
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) {
            return <String, Object?>{
              'pause_start': item['pause_start'],
              'pause_end': item['pause_end'],
              'pause_duration': item['pause_duration'],
            };
          })
          .where((item) => item['pause_start'] is String)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, Object?> _closedPause(
    Map<String, Object?> pause,
    DateTime endedAt,
  ) {
    final startedAt = DateTime.parse(pause['pause_start'] as String);
    return {
      'pause_start': pause['pause_start'],
      'pause_end': endedAt.toIso8601String(),
      'pause_duration': _durationText(endedAt.difference(startedAt)),
    };
  }

  static String _durationText(Duration duration) {
    final seconds = duration.inSeconds.abs();
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remaining.toString().padLeft(2, '0')}';
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
}
