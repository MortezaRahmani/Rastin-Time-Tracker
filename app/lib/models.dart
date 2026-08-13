class Project {
  const Project({required this.id, required this.name, required this.color});

  final int id;
  final String name;
  final int color;
}

class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.project,
    required this.title,
    required this.startedAt,
    required this.endedAt,
    required this.description,
    this.pauses = const [],
  });

  final int id;
  final Project project;
  final String title;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String description;
  final List<PauseInterval> pauses;

  Duration get duration {
    final raw = (endedAt ?? DateTime.now()).difference(startedAt);
    final active = raw - pausedDuration;
    return active.isNegative ? Duration.zero : active;
  }

  Duration get pausedDuration => pauses.fold(
    Duration.zero,
    (total, pause) => total + pause.duration,
  );

  PauseInterval? get activePause {
    for (final pause in pauses.reversed) {
      if (pause.endedAt == null) return pause;
    }
    return null;
  }

  bool get isPaused => activePause != null;
  bool get isRunning => endedAt == null;
}

class PauseInterval {
  const PauseInterval({required this.startedAt, required this.endedAt});

  final DateTime startedAt;
  final DateTime? endedAt;

  Duration get duration =>
      (endedAt ?? DateTime.now()).difference(startedAt).abs();
}
