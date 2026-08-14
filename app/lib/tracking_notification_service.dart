import 'dart:io';

import 'package:flutter/services.dart';

import 'formatters.dart';
import 'models.dart';

class TrackingNotificationService {
  static const pauseAction = 'pause_tracking';
  static const resumeAction = 'resume_tracking';
  static const stopAction = 'stop_tracking';
  static const breakPauseAction = 'break_pause';
  static const breakContinueAction = 'break_continue';
  static const showBreakReminderAction = 'show_break_reminder';
  static const _channel = MethodChannel('rtt/window');

  void Function(String action)? _onAction;
  bool _initialized = false;

  Future<void> initialize({
    required void Function(String action) onAction,
  }) async {
    _onAction = onAction;
    if (_initialized) return;
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'trackingNotificationAction') return;
      final action = call.arguments;
      if (action is String && action.isNotEmpty) _onAction?.call(action);
    });
    _initialized = true;
  }

  Future<void> show(TimeEntry entry) async {
    if (!Platform.isAndroid || !_initialized) return;
    final elapsed = formatDuration(entry.duration);
    final activity = entry.title.trim().isEmpty
        ? 'Tracking'
        : entry.title.trim();
    final project = entry.project.name;
    await _channel.invokeMethod<void>(
      'showTrackingNotification',
      {
        'title': 'RTT • $elapsed',
        'text': '$project • $activity',
        'paused': entry.isPaused,
      },
    );
  }

  Future<void> cancel() async {
    if (!Platform.isAndroid || !_initialized) return;
    await _channel.invokeMethod<void>('cancelTrackingNotification');
  }

  Future<void> showBreakReminder() async {
    if (!Platform.isAndroid || !_initialized) return;
    await _channel.invokeMethod<void>('showBreakReminderNotification');
  }

  Future<void> cancelBreakReminder() async {
    if (!Platform.isAndroid || !_initialized) return;
    await _channel.invokeMethod<void>('cancelBreakReminderNotification');
  }

  Future<void> scheduleBreakReminder(Duration delay) async {
    if (!Platform.isAndroid || !_initialized) return;
    await _channel.invokeMethod<void>(
      'scheduleBreakReminderAlarm',
      {'minutes': delay.inMinutes.clamp(1, 1440).toInt()},
    );
  }

  Future<void> cancelScheduledBreakReminder() async {
    if (!Platform.isAndroid || !_initialized) return;
    await _channel.invokeMethod<void>('cancelBreakReminderAlarm');
  }
}
