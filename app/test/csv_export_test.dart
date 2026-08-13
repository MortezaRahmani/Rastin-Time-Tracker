import 'package:flutter_test/flutter_test.dart';
import 'package:rastin_time_tracker/csv_export.dart';
import 'package:rastin_time_tracker/models.dart';

void main() {
  test('exports the requested columns with local date and time values', () {
    const project = Project(id: 1, name: 'Client, A', color: 0);
    final csv = projectActivitiesCsv(project, [
      TimeEntry(
        id: 1,
        project: project,
        title: 'Planning, call',
        startedAt: DateTime(2026, 1, 2, 9, 3, 4),
        endedAt: DateTime(2026, 1, 2, 10, 4, 5),
        description: 'Call "planning"',
        pauses: [
          PauseInterval(
            startedAt: DateTime(2026, 1, 2, 9, 30),
            endedAt: DateTime(2026, 1, 2, 9, 40),
          ),
        ],
      ),
    ]);

    expect(
      csv,
      startsWith(
        'Project,Title,Description,Started Date,Started Time,Ended Date,Ended Time,Paused Duration,Duration',
      ),
    );
    expect(
      csv,
      contains(
        '"Client, A","Planning, call","Call ""planning""","2026-01-02","09:03:04","2026-01-02","10:04:05","00:10:00","00:51:01"',
      ),
    );
  });
}
