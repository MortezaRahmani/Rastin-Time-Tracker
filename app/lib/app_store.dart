import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'csv_export.dart';
import 'models.dart';
import 'rtt_database.dart';
import 'tracking_notification_service.dart';

class AppStore extends ChangeNotifier {
  AppStore(this._database);

  static const _windowChannel = MethodChannel('rtt/window');
  static const _syncKeyName = 'rtt_sync_key';
  static const _secureStorage = FlutterSecureStorage();
  final _trackingNotifications = TrackingNotificationService();
  RttDatabase _database;
  final List<Project> projects = [];
  final List<TimeEntry> entries = [];
  TimeEntry? runningEntry;
  Project? selectedProject;
  Duration selectedProjectTotal = Duration.zero;
  ThemeMode themeMode = ThemeMode.dark;
  bool remoteMode = false;
  bool syncing = false;
  String? remoteEndpoint;
  String? lastSyncError;
  String? lastSyncStatus;
  String localDatabasePath = '';
  String fontSize = 'normal';
  bool breakReminderEnabled = false;
  int breakReminderMinutes = 30;
  bool breakReminderVisible = false;
  bool reminderSoundEnabled = false;
  String? reminderSoundPath;
  bool minimizeToTray = false;
  bool keepScreenAwake = false;
  Timer? _ticker;
  Timer? _breakReminderTimer;
  Timer? _breakReminderDismissTimer;

  double get textScale => switch (fontSize) {
    'tiny' => 0.88,
    'small' => 0.95,
    'large' => 1.10,
    'huge' => 1.20,
    _ => 1.0,
  };

  Future<void> load() async {
    await _trackingNotifications.initialize(
      onAction: _handleTrackingNotificationAction,
    );
    projects
      ..clear()
      ..addAll(_database.projects());
    if (projects.isEmpty) {
      projects.add(_database.addProject('General'));
    }
    themeMode = switch (_database.setting('color_mode')) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    remoteMode = _database.setting('sync_mode') == 'remote';
    remoteEndpoint = _database.setting('sync_endpoint');
    lastSyncStatus = _database.setting('last_sync_status');
    fontSize = _database.setting('font_size') ?? 'normal';
    breakReminderEnabled = _database.setting('break_reminder_enabled') == '1';
    breakReminderMinutes =
        int.tryParse(_database.setting('break_reminder_minutes') ?? '') ?? 30;
    reminderSoundEnabled = _database.setting('reminder_sound_enabled') == '1';
    reminderSoundPath = _database.setting('reminder_sound_path');
    minimizeToTray = _database.setting('minimize_to_tray') == '1';
    keepScreenAwake = _database.setting('keep_screen_awake') == '1';
    localDatabasePath = _database.path;
    selectedProject = projects.first;
    _refresh();
    _scheduleBreakReminder();
    _syncTrackingNotification();
    syncScreenAwakePreference();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
      _syncTrackingNotification();
    });
  }

  void selectProject(Project? project) {
    selectedProject = project;
    _refresh();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _database.setSetting('color_mode', mode.name);
    notifyListeners();
  }

  void setFontSize(String value) {
    fontSize = value;
    _database.setSetting('font_size', value);
    notifyListeners();
  }

  void setBreakReminderEnabled(bool value) {
    breakReminderEnabled = value;
    _database.setSetting('break_reminder_enabled', value.toString());
    if (value) {
      _scheduleBreakReminder();
    } else {
      _cancelBreakReminder();
      breakReminderVisible = false;
    }
    notifyListeners();
  }

  void setBreakReminderMinutes(int value) {
    breakReminderMinutes = value.clamp(1, 1440);
    _database.setSetting(
      'break_reminder_minutes',
      breakReminderMinutes.toString(),
    );
    _scheduleBreakReminder();
    notifyListeners();
  }

  void setReminderSoundEnabled(bool value) {
    reminderSoundEnabled = value;
    _database.setSetting('reminder_sound_enabled', value.toString());
    notifyListeners();
  }

  void setMinimizeToTray(bool value) {
    minimizeToTray = value;
    _database.setSetting('minimize_to_tray', value.toString());
    syncWindowPreferences();
    notifyListeners();
  }

  void setKeepScreenAwake(bool value) {
    keepScreenAwake = value;
    _database.setSetting('keep_screen_awake', value.toString());
    syncScreenAwakePreference();
    notifyListeners();
  }

  void syncScreenAwakePreference() {
    if (!Platform.isAndroid) return;
    unawaited(
      _windowChannel
          .invokeMethod<void>('setKeepScreenAwake', {
            'enabled': keepScreenAwake,
          })
          .catchError((_) {}),
    );
  }

  void syncWindowPreferences() {
    if (!Platform.isWindows) return;
    unawaited(
      _windowChannel
          .invokeMethod<void>('setMinimizeToTray', minimizeToTray)
          .catchError((_) {}),
    );
  }

  Future<void> chooseReminderSoundFile() async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      throw UnsupportedError(
        'Custom reminder sounds are available on Windows and Android.',
      );
    }
    final selected = await _windowChannel.invokeMethod<String>(
      'chooseReminderSoundFile',
    );
    if (selected == null || selected.isEmpty) return;
    reminderSoundPath = selected;
    _database.setSetting('reminder_sound_path', selected);
    notifyListeners();
  }

  void useDefaultReminderSound() {
    reminderSoundPath = null;
    _database.setSetting('reminder_sound_path', '');
    notifyListeners();
  }

  void useLocalMode() {
    remoteMode = false;
    lastSyncError = null;
    lastSyncStatus = null;
    _database.setSetting('sync_mode', 'local');
    notifyListeners();
  }

  Future<String?> configureRemote(String endpoint, String key) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Enter a valid HTTPS server URL.';
    }
    if (key.trim().length < 32) return 'Enter the complete sync key.';
    await _secureStorage.write(key: _syncKeyName, value: key.trim());
    remoteEndpoint = uri.toString();
    remoteMode = true;
    lastSyncError = null;
    lastSyncStatus = null;
    _database.setSetting('sync_endpoint', remoteEndpoint!);
    _database.setSetting('sync_mode', 'remote');
    notifyListeners();
    return null;
  }

  Future<String?> testRemoteConnection() async {
    final endpoint = remoteEndpoint;
    final key = await _secureStorage.read(key: _syncKeyName);
    if (!remoteMode || endpoint == null || key == null) {
      return 'Configure Remote Mode first.';
    }
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final response = await http
          .get(Uri.parse(endpoint), headers: {'Authorization': 'Bearer $key'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return 'Server rejected the connection (${response.statusCode}).';
      }
      _database.setSetting(
        'last_sync_at',
        DateTime.now().toUtc().toIso8601String(),
      );
      lastSyncStatus = 'Connection OK.';
      return null;
    } catch (_) {
      lastSyncError = 'Could not reach the sync server.';
      return lastSyncError;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<String?> syncNow() async {
    final endpoint = remoteEndpoint;
    final key = await _secureStorage.read(key: _syncKeyName);
    if (!remoteMode || endpoint == null || key == null) {
      return 'Configure Remote Mode first.';
    }
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final headers = {
        HttpHeaders.authorizationHeader: 'Bearer $key',
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      };
      final post = await http
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode(_database.syncPayload()),
          )
          .timeout(const Duration(seconds: 20));
      if (post.statusCode != 200) {
        lastSyncError = 'Sync push failed (${post.statusCode}).';
        return lastSyncError;
      }
      final cursor = _database.setting('sync_cursor');
      final uri = Uri.parse(endpoint).replace(
        queryParameters: {
          ...Uri.parse(endpoint).queryParameters,
          'since': ?cursor,
        },
      );
      final pull = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
      if (pull.statusCode != 200) {
        lastSyncError = 'Sync pull failed (${pull.statusCode}).';
        return lastSyncError;
      }
      final body = jsonDecode(pull.body);
      if (body is! Map ||
          body['projects'] is! List ||
          body['entries'] is! List) {
        lastSyncError = 'Sync server returned invalid data.';
        return lastSyncError;
      }
      final conflicts = _database.mergeSyncPayload(body);
      final nextCursor = body['cursor'];
      if (nextCursor is String) _database.setSetting('sync_cursor', nextCursor);
      final now = DateTime.now().toUtc().toIso8601String();
      _database.setSetting('last_sync_at', now);
      lastSyncStatus = conflicts == 0
          ? 'Sync complete.'
          : 'Sync complete with $conflicts conflict(s).';
      _database.setSetting('last_sync_status', lastSyncStatus!);
      _reloadFromDatabase();
      return null;
    } catch (_) {
      lastSyncError = 'Could not sync with the server.';
      return lastSyncError;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<File> exportSelectedProject(Directory directory) =>
      exportProject(selectedProject!, directory);

  Future<String?> exportSelectedProjectToUserLocation() =>
      exportProjectToUserLocation(selectedProject!);

  Future<String?> exportProjectToUserLocation(Project project) =>
      _exportCsvToUserLocation(
        '${_safeFileName(project.name)}-activities',
        activitiesCsv(_database.entriesForProject(project)),
      );

  Future<String?> exportAllProjectsToUserLocation() =>
      _exportCsvToUserLocation(
        'all-projects-activities',
        activitiesCsv(_database.allEntries()),
      );

  Future<File> exportProject(Project project, Directory directory) =>
      _writeExport(
        directory,
        '${_safeFileName(project.name)}-activities',
        activitiesCsv(_database.entriesForProject(project)),
      );

  Future<File> exportAllProjects(Directory directory) => _writeExport(
    directory,
    'all-projects-activities',
    activitiesCsv(_database.allEntries()),
  );

  Future<File> _writeExport(
    Directory directory,
    String name,
    String csv,
  ) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = '$name-$timestamp.csv';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    return file.writeAsString(csv, flush: true);
  }

  Future<String?> _exportCsvToUserLocation(String name, String csv) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = '$name-$timestamp.csv';
    if (Platform.isAndroid) {
      final uri = await _windowChannel.invokeMethod<String>('saveCsvFile', {
        'fileName': fileName,
        'content': csv,
      });
      return uri == null ? null : 'selected folder';
    }
    final directory = await chooseExportFolder();
    if (directory == null) return null;
    return _writeExport(directory, name, csv).then((file) => file.path);
  }

  Future<Directory?> chooseExportFolder() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Custom export folders are available on Windows.');
    }
    final selected = await _windowChannel.invokeMethod<String>(
      'chooseExportFolder',
    );
    return selected == null || selected.isEmpty ? null : Directory(selected);
  }

  Future<String?> chooseLocalDatabaseFile() async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Database file selection is available on Windows.',
      );
    }
    final selected = await _windowChannel.invokeMethod<String>(
      'chooseLocalDatabaseFile',
    );
    return selected == null || selected.isEmpty ? null : selected;
  }

  Future<String?> loadLocalDatabase(String path) async {
    if (remoteMode) return 'Switch to Local Mode first.';
    if (runningEntry != null) {
      return 'Stop the running timer before changing the database.';
    }
    try {
      final next = await RttDatabase.openPath(path);
      _database.close();
      _database = next;
      await RttDatabase.setPreferredPath(next.path);
      localDatabasePath = next.path;
      lastSyncError = null;
      lastSyncStatus = null;
      _cancelBreakReminder();
      _reloadFromDatabase();
      return null;
    } catch (_) {
      return 'Could not open the selected SQLite database.';
    }
  }

  String? addProject(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        projects.any(
          (project) => project.name.toLowerCase() == trimmed.toLowerCase(),
        )) {
      return 'Enter a unique project name.';
    }
    final project = _database.addProject(trimmed);
    projects.add(project);
    selectedProject = project;
    _refresh();
    return null;
  }

  String? updateProject(Project project, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        projects.any(
          (item) =>
              item.id != project.id &&
              item.name.toLowerCase() == trimmed.toLowerCase(),
        )) {
      return 'Enter a unique project name.';
    }
    final updated = _database.updateProject(project, trimmed);
    final index = projects.indexWhere((item) => item.id == project.id);
    projects[index] = updated;
    if (selectedProject?.id == project.id) {
      selectedProject = updated;
    }
    _refresh();
    return null;
  }

  String? deleteProject(Project project) {
    if (projects.length == 1) {
      return 'Keep at least one project.';
    }
    if (runningEntry?.project.id == project.id) {
      return 'Stop the running timer before deleting its project.';
    }
    _database.deleteProject(project);
    projects.removeWhere((item) => item.id == project.id);
    if (selectedProject?.id == project.id) {
      selectedProject = projects.first;
    }
    _refresh();
    return null;
  }

  void start(String title, String description) {
    final project = selectedProject;
    if (project == null || runningEntry != null) return;
    _database.start(project, title, description);
    _refresh();
    _scheduleBreakReminder();
    _syncTrackingNotification();
  }

  void stop() {
    final entry = runningEntry;
    if (entry == null) return;
    _stopReminderSound();
    _database.stop(entry);
    _cancelBreakReminder();
    breakReminderVisible = false;
    _refresh();
    _syncTrackingNotification();
  }

  void pause() {
    final entry = runningEntry;
    if (entry == null || entry.isPaused) return;
    _stopReminderSound();
    _database.pause(entry);
    _cancelBreakReminder();
    breakReminderVisible = false;
    _refresh();
    _syncTrackingNotification();
  }

  void resume() {
    final entry = runningEntry;
    if (entry == null || !entry.isPaused) return;
    _database.resume(entry);
    _refresh();
    _scheduleBreakReminder();
    _syncTrackingNotification();
  }

  void continueAfterBreakReminder() {
    _stopReminderSound();
    breakReminderVisible = false;
    _breakReminderDismissTimer?.cancel();
    unawaited(_trackingNotifications.cancelBreakReminder());
    notifyListeners();
  }

  String? addManual(
    Project project,
    DateTime startedAt,
    DateTime endedAt,
    String title,
    String description,
  ) {
    if (!endedAt.isAfter(startedAt)) {
      return 'End time must be after start time.';
    }
    _database.addEntry(project, startedAt, endedAt, title, description);
    _refresh();
    return null;
  }

  String? updateManual(
    TimeEntry entry,
    Project project,
    DateTime startedAt,
    DateTime endedAt,
    String title,
    String description,
  ) {
    if (entry.isRunning) {
      return 'Stop the running timer before editing it.';
    }
    if (!endedAt.isAfter(startedAt)) {
      return 'End time must be after start time.';
    }
    _database.updateEntry(
      entry,
      project,
      startedAt,
      endedAt,
      title,
      description,
    );
    _refresh();
    return null;
  }

  String? deleteEntry(TimeEntry entry) {
    if (entry.isRunning) {
      return 'Stop the running timer before deleting it.';
    }
    _database.deleteEntry(entry);
    _refresh();
    return null;
  }

  void _refresh() {
    runningEntry = _database.runningEntry();
    final projectEntries = _database.entriesForProject(selectedProject!);
    selectedProjectTotal = projectEntries.fold(
      Duration.zero,
      (total, entry) => total + entry.duration,
    );
    entries
      ..clear()
      ..addAll(projectEntries.take(20));
    notifyListeners();
  }

  void _scheduleBreakReminder() {
    _breakReminderTimer?.cancel();
    _breakReminderDismissTimer?.cancel();
    unawaited(_trackingNotifications.cancelScheduledBreakReminder());
    if (!breakReminderEnabled ||
        runningEntry == null ||
        runningEntry!.isPaused) {
      return;
    }
    final delay = Duration(minutes: breakReminderMinutes);
    unawaited(_trackingNotifications.scheduleBreakReminder(delay));
    _breakReminderTimer = Timer(delay, () {
      if (runningEntry == null || runningEntry!.isPaused) return;
      _showBreakReminder();
      _scheduleBreakReminder();
      _breakReminderDismissTimer?.cancel();
      _breakReminderDismissTimer = Timer(const Duration(seconds: 30), () {
        if (!breakReminderVisible) return;
        breakReminderVisible = false;
        unawaited(_trackingNotifications.cancelBreakReminder());
        notifyListeners();
      });
    });
  }

  void _showBreakReminder() {
    if (runningEntry == null || runningEntry!.isPaused) return;
    if (breakReminderVisible) return;
    breakReminderVisible = true;
    unawaited(_trackingNotifications.showBreakReminder());
    _playReminderSound();
    notifyListeners();
  }

  void _playReminderSound() {
    if (!reminderSoundEnabled) return;
    if (!Platform.isWindows && !Platform.isAndroid) return;
    unawaited(
      _windowChannel
          .invokeMethod<void>('playReminderSound', {'path': reminderSoundPath})
          .catchError((_) {}),
    );
  }

  void _stopReminderSound() {
    if (!Platform.isWindows && !Platform.isAndroid) return;
    unawaited(
      _windowChannel.invokeMethod<void>('stopReminderSound').catchError((_) {}),
    );
  }

  void _cancelBreakReminder() {
    _breakReminderTimer?.cancel();
    _breakReminderDismissTimer?.cancel();
    _breakReminderTimer = null;
    _breakReminderDismissTimer = null;
    unawaited(_trackingNotifications.cancelBreakReminder());
    unawaited(_trackingNotifications.cancelScheduledBreakReminder());
  }

  void _reloadFromDatabase() {
    projects
      ..clear()
      ..addAll(_database.projects());
    final selectedId = selectedProject?.id;
    selectedProject = null;
    if (selectedId != null) {
      for (final project in projects) {
        if (project.id == selectedId) {
          selectedProject = project;
          break;
        }
      }
    }
    selectedProject ??= projects.isEmpty ? null : projects.first;
    if (projects.isEmpty) projects.add(_database.addProject('General'));
    selectedProject ??= projects.first;
    _refresh();
    _syncTrackingNotification();
  }

  void _handleTrackingNotificationAction(String action) {
    switch (action) {
      case TrackingNotificationService.pauseAction:
        pause();
      case TrackingNotificationService.resumeAction:
        resume();
      case TrackingNotificationService.stopAction:
        stop();
      case TrackingNotificationService.breakPauseAction:
        pause();
      case TrackingNotificationService.breakContinueAction:
        continueAfterBreakReminder();
      case TrackingNotificationService.showBreakReminderAction:
        _showBreakReminder();
    }
  }

  void _syncTrackingNotification() {
    final entry = runningEntry;
    unawaited(
      entry == null
          ? _trackingNotifications.cancel()
          : _trackingNotifications.show(entry),
    );
  }

  String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  @override
  void dispose() {
    _ticker?.cancel();
    _cancelBreakReminder();
    super.dispose();
  }
}
