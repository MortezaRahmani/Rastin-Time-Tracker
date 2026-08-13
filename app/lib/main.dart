import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import 'app_store.dart';
import 'date_time_picker.dart';
import 'formatters.dart';
import 'models.dart';
import 'rtt_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(await RttDatabase.open());
  await store.load();
  runApp(RttApp(store: store));
}

class RttApp extends StatefulWidget {
  const RttApp({super.key, required this.store});

  final AppStore store;

  @override
  State<RttApp> createState() => _RttAppState();
}

class _RttAppState extends State<RttApp> with TrayListener {
  static const _windowChannel = MethodChannel('rtt/window');
  String? _windowTitle;
  int? _trackingEntryId;
  bool? _trackingPaused;
  int? _trackingPausedSeconds;
  bool? _trayEnabled;
  late ThemeMode _themeMode;
  late double _textScale;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.store.themeMode;
    _textScale = widget.store.textScale;
    widget.store.addListener(_onStoreChanged);
    widget.store.syncWindowPreferences();
    _onStoreChanged();
    if (Platform.isWindows) trayManager.addListener(this);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    if (Platform.isWindows) trayManager.removeListener(this);
    super.dispose();
  }

  void _onStoreChanged() {
    unawaited(_syncTray());
    _updateWindowTitle(widget.store.runningEntry);
    final themeMode = widget.store.themeMode;
    final textScale = widget.store.textScale;
    if (themeMode == _themeMode && textScale == _textScale) return;
    setState(() {
      _themeMode = themeMode;
      _textScale = textScale;
    });
  }

  void _updateWindowTitle(TimeEntry? running) {
    final title = running == null
        ? 'Rastin Time Tracker'
        : 'RTT • ${formatDuration(running.duration)}';
    if (!Platform.isWindows) return;
    if (running == null) {
      if (_trackingEntryId == null && _windowTitle == title) return;
      _windowTitle = title;
      _trackingEntryId = null;
      _trackingPaused = null;
      _trackingPausedSeconds = null;
      unawaited(_windowChannel.invokeMethod<void>('setTitle', title));
      return;
    }
    final pausedSeconds = running.pausedDuration.inSeconds;
    if (running.isPaused) {
      if (_trackingEntryId == running.id &&
          _trackingPaused == true &&
          _trackingPausedSeconds == pausedSeconds &&
          _windowTitle == title) {
        return;
      }
      _windowTitle = title;
      _trackingEntryId = running.id;
      _trackingPaused = true;
      _trackingPausedSeconds = pausedSeconds;
      unawaited(_windowChannel.invokeMethod<void>('setTitle', title));
      return;
    }
    if (_trackingEntryId == running.id &&
        _trackingPaused == false &&
        _trackingPausedSeconds == pausedSeconds) {
      return;
    }
    _windowTitle = title;
    _trackingEntryId = running.id;
    _trackingPaused = false;
    _trackingPausedSeconds = pausedSeconds;
    unawaited(
      _windowChannel.invokeMethod<void>('startTrackingTitle', {
        'startedAt': running.startedAt.toUtc().millisecondsSinceEpoch,
        'pausedSeconds': pausedSeconds,
      }),
    );
  }

  Future<void> _syncTray() async {
    if (!Platform.isWindows || _trayEnabled == widget.store.minimizeToTray) {
      return;
    }
    _trayEnabled = widget.store.minimizeToTray;
    if (!widget.store.minimizeToTray) {
      await trayManager.destroy();
      return;
    }
    await trayManager.setIcon('assets/app_icon.ico');
    await trayManager.setToolTip('Rastin Time Tracker');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: 'Show Window'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'Exit'),
        ],
      ),
    );
  }

  Future<void> _showWindow() async {
    if (!Platform.isWindows) return;
    await _windowChannel.invokeMethod<void>('showWindow');
  }

  Future<void> _exitApp() async {
    if (!Platform.isWindows) return;
    await trayManager.destroy();
    await _windowChannel.invokeMethod<void>('exitApp');
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_showWindow());
      case 'exit_app':
        unawaited(_exitApp());
    }
  }

  @override
  Widget build(BuildContext context) => Title(
    title: 'Rastin Time Tracker',
    color: const Color(0xffd97706),
    child: MaterialApp(
      title: 'Rastin Time Tracker',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_textScale)),
        child: child!,
      ),
      home: TrackerPage(store: widget.store),
    ),
  );
}

ThemeData _theme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: const Color(0xffd97706),
    surface: isDark ? const Color(0xff1f1e27) : const Color(0xfffffbff),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xff0f172a)
        : const Color(0xfffffbff),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key, required this.store});

  final AppStore store;

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  final _activityTitle = TextEditingController();
  final _description = TextEditingController();
  var _exporting = false;

  @override
  void dispose() {
    _activityTitle.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<bool> _editProject([Project? project]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ProjectNameDialog(initialName: project?.name),
    );
    if (name == null || !mounted) return false;
    final error = project == null
        ? widget.store.addProject(name)
        : widget.store.updateProject(project, name);
    if (error != null) {
      _showError(error);
      return false;
    }
    setState(() {});
    return true;
  }

  Future<void> _manageProjects() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Projects'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: widget.store.projects
                  .map(
                    (project) => ListTile(
                      title: Text(project.name),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Edit ${project.name}',
                            onPressed: () async {
                              if (await _editProject(project)) {
                                setDialogState(() {});
                              }
                            },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Export ${project.name} to CSV',
                            onPressed: _exporting
                                ? null
                                : () => _exportProject(project),
                            icon: const Icon(Icons.file_download_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete ${project.name}',
                            onPressed: () async {
                              if (!await _confirmDelete(
                                'Delete ${project.name}?',
                                'Its activities will also be deleted.',
                              )) {
                                return;
                              }
                              final error = widget.store.deleteProject(project);
                              if (error != null) _showError(error);
                              if (context.mounted) setDialogState(() {});
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                if (await _editProject()) {
                  setDialogState(() {});
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editActivity([TimeEntry? entry]) async {
    final initialProject = entry == null
        ? widget.store.selectedProject!
        : widget.store.projects.firstWhere(
            (item) => item.id == entry.project.id,
            orElse: () => widget.store.selectedProject!,
          );
    final draft = await showDialog<_ActivityDraft>(
      context: context,
      builder: (_) => _ActivityDialog(
        entry: entry,
        projects: widget.store.projects,
        initialProject: initialProject,
      ),
    );
    if (draft == null || !mounted) return;
    final error = entry == null
        ? widget.store.addManual(
            draft.project,
            draft.startedAt,
            draft.endedAt,
            draft.title,
            draft.description,
          )
        : widget.store.updateManual(
            entry,
            draft.project,
            draft.startedAt,
            draft.endedAt,
            draft.title,
            draft.description,
          );
    if (error != null) _showError(error);
  }

  Future<bool> _confirmDelete(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteActivity(TimeEntry entry) async {
    if (!await _confirmDelete('Delete activity?', 'This cannot be undone.')) {
      return;
    }
    final error = widget.store.deleteEntry(entry);
    if (error != null) _showError(error);
  }

  Future<void> _exportProject([Project? project]) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = project == null
          ? await widget.store.exportSelectedProjectToUserLocation()
          : await widget.store.exportProjectToUserLocation(project);
      if (path == null) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('CSV saved to $path')));
      }
    } catch (_) {
      _showError('Could not export the project CSV.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportAllProjects() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await widget.store.exportAllProjectsToUserLocation();
      if (path == null) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('CSV saved to $path')));
      }
    } catch (_) {
      _showError('Could not export all projects CSV.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _settings() async {
    final endpoint = TextEditingController(text: widget.store.remoteEndpoint);
    final key = TextEditingController();
    final breakMinutes = TextEditingController(
      text: widget.store.breakReminderMinutes.toString(),
    );
    var remote = widget.store.remoteMode;
    final submittedBreakMinutes = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsSection(
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<ThemeMode>(
                          initialValue: widget.store.themeMode,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w400),
                          decoration: const InputDecoration(
                            labelText: 'Color mode',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('System'),
                            ),
                          ],
                          onChanged: (mode) {
                            if (mode == null) return;
                            widget.store.setThemeMode(mode);
                            setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: widget.store.fontSize,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w400),
                          decoration: const InputDecoration(
                            labelText: 'Font size',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'tiny',
                              child: Text('Tiny'),
                            ),
                            DropdownMenuItem(
                              value: 'small',
                              child: Text('Small'),
                            ),
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text('Normal'),
                            ),
                            DropdownMenuItem(
                              value: 'large',
                              child: Text('Large'),
                            ),
                            DropdownMenuItem(
                              value: 'huge',
                              child: Text('Huge'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            widget.store.setFontSize(value);
                            setDialogState(() {});
                          },
                        ),
                        if (Platform.isWindows) ...[
                          const SizedBox(height: 10),
                          _CompactSwitchRow(
                            title: 'Minimize to Tray',
                            subtitle:
                                'Hide RTT in the Windows tray when minimized.',
                            value: widget.store.minimizeToTray,
                            onChanged: (value) {
                              widget.store.setMinimizeToTray(value);
                              setDialogState(() {});
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSection(
                    icon: Icons.self_improvement_outlined,
                    title: 'Break reminder',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CompactSwitchRow(
                          title: 'Enable break reminder',
                          subtitle: 'Shows an in-app reminder while tracking.',
                          value: widget.store.breakReminderEnabled,
                          onChanged: (value) {
                            widget.store.setBreakReminderEnabled(value);
                            setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: breakMinutes,
                          enabled: widget.store.breakReminderEnabled,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Reminder time (minutes)',
                          ),
                          onSubmitted: (value) {
                            widget.store.setBreakReminderMinutes(
                              int.tryParse(value) ?? 30,
                            );
                            breakMinutes.text = widget
                                .store
                                .breakReminderMinutes
                                .toString();
                            setDialogState(() {});
                          },
                          onTapOutside: (_) {
                            widget.store.setBreakReminderMinutes(
                              int.tryParse(breakMinutes.text) ?? 30,
                            );
                            breakMinutes.text = widget
                                .store
                                .breakReminderMinutes
                                .toString();
                            setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 10),
                        _CompactSwitchRow(
                          title: 'Reminder sound',
                          subtitle: 'Play a sound when the reminder appears.',
                          value: widget.store.reminderSoundEnabled,
                          onChanged: (value) {
                            widget.store.setReminderSoundEnabled(value);
                            setDialogState(() {});
                          },
                        ),
                        if (Platform.isWindows || Platform.isAndroid) ...[
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: widget.store.reminderSoundEnabled
                                ? () async {
                                    await widget.store
                                        .chooseReminderSoundFile();
                                    setDialogState(() {});
                                  }
                                : null,
                            icon: const Icon(Icons.library_music_outlined),
                            label: Text(
                              widget.store.reminderSoundPath == null
                                  ? 'Custom reminder sound'
                                  : 'Change custom sound',
                            ),
                          ),
                          if (widget.store.reminderSoundPath != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    widget.store.reminderSoundPath!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  TextButton.icon(
                                    onPressed: () {
                                      widget.store.useDefaultReminderSound();
                                      setDialogState(() {});
                                    },
                                    icon: const Icon(Icons.restore_outlined),
                                    label: const Text('Use default sound'),
                                  ),
                                ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSection(
                    icon: Icons.storage_outlined,
                    title: 'Data mode',
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.computer_outlined),
                          label: Text('Local'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.cloud_outlined),
                          label: Text('Remote'),
                        ),
                      ],
                      selected: {remote},
                      onSelectionChanged: (value) {
                        remote = value.single;
                        if (!remote) widget.store.useLocalMode();
                        setDialogState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!remote && Platform.isWindows)
                    _SettingsSection(
                      icon: Icons.folder_open_outlined,
                      title: 'Local database',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.store.localDatabasePath,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final path = await widget.store
                                  .chooseLocalDatabaseFile();
                              if (path == null) return;
                              final error = await widget.store
                                  .loadLocalDatabase(path);
                              if (error != null) {
                                _showError(error);
                                return;
                              }
                              setDialogState(() {});
                            },
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Load SQLite database'),
                          ),
                        ],
                      ),
                    ),
                  if (remote)
                    _SettingsSection(
                      icon: Icons.sync_outlined,
                      title: 'Remote sync',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: endpoint,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Server URL',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: key,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Sync key',
                            ),
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: widget.store.syncing
                                ? null
                                : () async {
                                    final error = await widget.store
                                        .configureRemote(
                                          endpoint.text,
                                          key.text,
                                        );
                                    if (error != null) {
                                      _showError(error);
                                      return;
                                    }
                                    final connectionError = await widget.store
                                        .testRemoteConnection();
                                    if (connectionError != null) {
                                      _showError(connectionError);
                                    }
                                    setDialogState(() {});
                                  },
                            icon: const Icon(Icons.cloud_done_outlined),
                            label: const Text('Save and test connection'),
                          ),
                          OutlinedButton.icon(
                            onPressed: widget.store.syncing
                                ? null
                                : () async {
                                    final error = await widget.store.syncNow();
                                    if (error != null) _showError(error);
                                    setDialogState(() {});
                                  },
                            icon: widget.store.syncing
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.sync_outlined),
                            label: const Text('Sync now'),
                          ),
                          if (widget.store.lastSyncStatus != null)
                            Text(widget.store.lastSyncStatus!),
                          if (widget.store.lastSyncError != null)
                            Text(
                              widget.store.lastSyncError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  _SettingsSection(
                    icon: Icons.file_download_outlined,
                    title: 'Export',
                    child: OutlinedButton.icon(
                      onPressed: _exporting
                          ? null
                          : () {
                              Navigator.pop(context);
                              _exportAllProjects();
                            },
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Export all projects to CSV'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context, breakMinutes.text);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (submittedBreakMinutes != null && mounted) {
      widget.store.setBreakReminderMinutes(
        int.tryParse(submittedBreakMinutes) ?? 30,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Rastin Time Tracker'),
      actions: [
        IconButton(
          tooltip: 'Add activity',
          onPressed: _editActivity,
          icon: const Icon(Icons.edit_calendar_outlined),
        ),
        PopupMenuButton<_AppAction>(
          tooltip: 'More options',
          onSelected: (action) {
            switch (action) {
              case _AppAction.projects:
                _manageProjects();
              case _AppAction.settings:
                _settings();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _AppAction.projects,
              child: ListTile(
                leading: Icon(Icons.folder_outlined),
                title: Text('Projects'),
              ),
            ),
            PopupMenuItem(
              value: _AppAction.settings,
              child: ListTile(
                leading: Icon(Icons.settings_outlined),
                title: Text('Settings'),
              ),
            ),
          ],
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final running = widget.store.runningEntry;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
          children: [
            if (widget.store.breakReminderVisible) ...[
              _BreakReminderCard(store: widget.store),
              const SizedBox(height: 10),
            ],
            Center(
              child: _TimerCard(
                store: widget.store,
                title: _activityTitle,
                description: _description,
                running: running,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Project Activities - Total: ${formatHoursMinutes(widget.store.selectedProjectTotal)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip:
                      'Export ${widget.store.selectedProject!.name} to CSV',
                  onPressed: _exporting ? null : _exportProject,
                  icon: _exporting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (widget.store.entries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.history_toggle_off_outlined),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('No activity for this project yet.'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...widget.store.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _EntryTile(
                    entry,
                    onEdit: () => _editActivity(entry),
                    onDelete: () => _deleteActivity(entry),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({required this.initialName});

  final String? initialName;

  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      Navigator.pop(context, name);
      return;
    }
    setState(() => _error = 'Enter a project name.');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initialName == null ? 'New project' : 'Edit project'),
    content: TextField(
      autofocus: true,
      controller: _controller,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Project name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.initialName == null ? 'Add' : 'Save'),
      ),
    ],
  );
}

class _ActivityDraft {
  const _ActivityDraft({
    required this.project,
    required this.startedAt,
    required this.endedAt,
    required this.title,
    required this.description,
  });

  final Project project;
  final DateTime startedAt;
  final DateTime endedAt;
  final String title;
  final String description;
}

class _ActivityDialog extends StatefulWidget {
  const _ActivityDialog({
    required this.entry,
    required this.projects,
    required this.initialProject,
  });

  final TimeEntry? entry;
  final List<Project> projects;
  final Project initialProject;

  @override
  State<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<_ActivityDialog> {
  late Project _project;
  late DateTime _startedAt;
  late DateTime _endedAt;
  late final TextEditingController _title;
  late final TextEditingController _description;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _project = widget.initialProject;
    _startedAt =
        entry?.startedAt ?? DateTime.now().subtract(const Duration(hours: 1));
    _endedAt = entry?.endedAt ?? DateTime.now();
    _title = TextEditingController(text: entry?.title);
    _description = TextEditingController(text: entry?.description);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_endedAt.isAfter(_startedAt)) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }
    Navigator.pop(
      context,
      _ActivityDraft(
        project: _project,
        startedAt: _startedAt,
        endedAt: _endedAt,
        title: _title.text,
        description: _description.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? 'Add activity' : 'Edit activity'),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<Project>(
              initialValue: _project,
              decoration: const InputDecoration(labelText: 'Project'),
              items: widget.projects
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.name)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _project = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: _popupInputDecoration(context, 'Activity title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 3,
              decoration: _popupInputDecoration(
                context,
                'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            DateTimePicker(
              label: 'Started',
              value: _startedAt,
              onChanged: (value) => setState(() => _startedAt = value),
            ),
            const SizedBox(height: 8),
            DateTimePicker(
              label: 'Ended',
              value: _endedAt,
              onChanged: (value) => setState(() => _endedAt = value),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({
    required this.store,
    required this.title,
    required this.description,
    required this.running,
  });

  final AppStore store;
  final TextEditingController title;
  final TextEditingController description;
  final TimeEntry? running;

  @override
  Widget build(BuildContext context) {
    final active = running != null;
    return SizedBox(
      width: 398,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    active ? Icons.fiber_manual_record : Icons.timer_outlined,
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active
                        ? running!.isPaused
                              ? 'Paused'
                              : 'Tracking now'
                        : 'Ready to track',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                active ? formatDuration(running!.duration) : '00:00:00',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              if (active) ...[
                const SizedBox(height: 6),
                Text(
                  running!.project.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
              SizedBox(height: active ? 18 : 16),
              if (!active) ...[
                DropdownButtonFormField<Project>(
                  key: ValueKey(store.selectedProject?.id),
                  initialValue: store.selectedProject,
                  decoration: _mainInputDecoration(context, 'Project'),
                  items: store.projects
                      .map(
                        (project) => DropdownMenuItem(
                          value: project,
                          child: Text(project.name),
                        ),
                      )
                      .toList(),
                  onChanged: store.selectProject,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _mainInputDecoration(context, 'Activity title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _mainInputDecoration(
                    context,
                    'What are you working on? (optional)',
                  ),
                ),
                const SizedBox(height: 10),
              ] else if (running!.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    running!.description,
                    textAlign: TextAlign.center,
                  ),
                ),
              if (active && running!.pausedDuration > Duration.zero)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Paused ${formatDuration(running!.pausedDuration)} total',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (active)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: running!.isPaused
                            ? store.resume
                            : store.pause,
                        icon: Icon(
                          running!.isPaused
                              ? Icons.play_circle_outline
                              : Icons.pause_circle_outline,
                        ),
                        label: Text(running!.isPaused ? 'Resume' : 'Pause'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: store.stop,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop timer'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                        ),
                      ),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: () {
                    store.start(title.text, description.text);
                    title.clear();
                    description.clear();
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Start timer'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _mainInputDecoration(BuildContext context, String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: Theme.of(context).textTheme.bodySmall,
    floatingLabelStyle: Theme.of(context).textTheme.bodySmall,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
  );
}

InputDecoration _popupInputDecoration(BuildContext context, String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: Theme.of(context).textTheme.bodySmall,
    floatingLabelStyle: Theme.of(context).textTheme.bodySmall,
  );
}

class _BreakReminderCard extends StatelessWidget {
  const _BreakReminderCard({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.self_improvement_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            const Expanded(child: Text('Wanna take a break?')),
            TextButton(
              onPressed: store.continueAfterBreakReminder,
              child: const Text('Continue'),
            ),
            FilledButton.tonalIcon(
              onPressed: store.pause,
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('Pause'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry, {required this.onEdit, required this.onDelete});

  final TimeEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 0),
      title: Text(entry.title.isEmpty ? entry.project.name : entry.title),
      subtitle: Text(
        '${entry.project.name} • ${TimeOfDay.fromDateTime(entry.startedAt).format(context)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatDuration(entry.duration)),
          Transform.translate(
            offset: const Offset(0, 0),
            child: PopupMenuButton<_EntryAction>(
              tooltip: 'Activity actions',
              onSelected: (action) {
                switch (action) {
                  case _EntryAction.edit:
                    onEdit();
                  case _EntryAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _EntryAction.edit,
                  enabled: !entry.isRunning,
                  child: const Text('Edit'),
                ),
                PopupMenuItem(
                  value: _EntryAction.delete,
                  enabled: !entry.isRunning,
                  child: const Text('Delete'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _CompactSwitchRow extends StatelessWidget {
  const _CompactSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Transform.scale(
          scale: 0.78,
          alignment: Alignment.centerRight,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

enum _EntryAction { edit, delete }

enum _AppAction { projects, settings }
