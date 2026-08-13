import 'formatters.dart';
import 'models.dart';

String projectActivitiesCsv(Project project, List<TimeEntry> entries) {
  return activitiesCsv(entries);
}

String activitiesCsv(List<TimeEntry> entries) {
  final output = StringBuffer(
    'Project,Title,Description,Started Date,Started Time,Ended Date,Ended Time,Paused Duration,Duration\r\n',
  );
  for (final entry in entries) {
    output
      ..write(
        [
          entry.project.name,
          entry.title,
          entry.description,
          _date(entry.startedAt),
          _time(entry.startedAt),
          entry.endedAt == null ? '' : _date(entry.endedAt!),
          entry.endedAt == null ? '' : _time(entry.endedAt!),
          formatDuration(entry.pausedDuration),
          formatDuration(entry.duration),
        ].map(_csvField).join(','),
      )
      ..write('\r\n');
  }
  return output.toString();
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';

String _csvField(String value) => '"${value.replaceAll('"', '""')}"';
