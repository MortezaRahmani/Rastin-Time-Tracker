import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rastin_time_tracker/rtt_database.dart';

void main() {
  test('projects and activities support CRUD with project-scoped recents', () {
    final database = RttDatabase.inMemory();
    final alpha = database.addProject('Alpha');
    final bravo = database.addProject('Bravo');
    final start = DateTime(2026, 1, 1, 9);
    final end = DateTime(2026, 1, 1, 10);

    database.addEntry(alpha, start, end, 'Plan sprint', 'Planning');
    database.addEntry(bravo, start, end, 'Review pull request', 'Review');

    expect(database.recentEntries(alpha).single.description, 'Planning');
    expect(database.recentEntries(alpha).single.title, 'Plan sprint');

    final entry = database.recentEntries(alpha).single;
    database.updateEntry(
      entry,
      alpha,
      start,
      end,
      'Updated plan',
      'Updated planning',
    );
    expect(
      database.recentEntries(alpha).single.description,
      'Updated planning',
    );
    expect(database.recentEntries(alpha).single.title, 'Updated plan');

    final renamed = database.updateProject(alpha, 'Work');
    expect(renamed.name, 'Work');
    database.setSetting('color_mode', 'light');
    expect(database.setting('color_mode'), 'light');
    database.deleteProject(renamed);
    expect(database.projects().map((project) => project.name), ['Bravo']);
  });

  test('serializes and merges sync payloads', () {
    final database = RttDatabase.inMemory();
    final local = database.addProject('Local');
    database.addEntry(
      local,
      DateTime.utc(2026, 1, 1, 9),
      DateTime.utc(2026, 1, 1, 10),
      'Local work',
      'Already here',
    );

    final localPayload = database.syncPayload();
    expect(localPayload['projects'], isA<List>());
    expect(localPayload['entries'], isA<List>());

    final remoteProjectId = '11111111111111111111111111111111';
    final remoteEntryId = '22222222222222222222222222222222';
    final conflicts = database.mergeSyncPayload({
      'projects': [
        {
          'syncId': remoteProjectId,
          'name': 'Remote',
          'color': 4292466762,
          'createdAt': '2026-01-02T00:00:00Z',
          'updatedAt': '2026-01-02T00:00:00Z',
          'deletedAt': null,
        },
      ],
      'entries': [
        {
          'syncId': remoteEntryId,
          'projectSyncId': remoteProjectId,
          'startedAt': '2026-01-02T09:00:00Z',
          'endedAt': '2026-01-02T10:00:00Z',
          'title': 'Remote work',
          'description': 'Pulled from server',
          'createdAt': '2026-01-02T09:00:00Z',
          'updatedAt': '2026-01-02T10:00:00Z',
          'deletedAt': null,
        },
      ],
    });

    final remote = database.projects().singleWhere(
      (project) => project.name == 'Remote',
    );
    expect(conflicts, 0);
    expect(database.entriesForProject(remote).single.title, 'Remote work');
  });

  test('stores pause intervals and deducts them from duration', () {
    final database = RttDatabase.inMemory();
    final project = database.addProject('Pause test');

    database.start(project, 'Focused work', '');
    var running = database.runningEntry()!;
    database.pause(running);
    running = database.runningEntry()!;
    expect(running.isPaused, isTrue);
    expect(running.pauses, hasLength(1));

    database.resume(running);
    running = database.runningEntry()!;
    expect(running.isPaused, isFalse);
    expect(running.pauses, hasLength(1));
    expect(running.pauses.single.endedAt, isNotNull);

    final payload = database.syncPayload();
    final entries = payload['entries']! as List;
    expect(entries.single['pausesJson'], contains('pause_start'));
  });

  test('opens a selected SQLite database path', () async {
    final directory = await Directory.systemTemp.createTemp('rtt-db-test-');
    final path = '${directory.path}${Platform.pathSeparator}selected.sqlite3';
    final first = await RttDatabase.openPath(path);
    first.addProject('Selected DB');
    first.close();

    final second = await RttDatabase.openPath(path);
    expect(second.projects().map((project) => project.name), ['Selected DB']);
    second.close();
    await directory.delete(recursive: true);
  });
}
