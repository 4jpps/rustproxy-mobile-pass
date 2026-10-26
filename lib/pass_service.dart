// Runs the check-in loop while the switch is on. Android: a foreground service (with its required
// notification) so check-ins continue in the background and resume after a reboot. Elsewhere: a timer
// inside the app, which on iOS only runs while the app is open (the pass then lapses on its own).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'pass_client.dart';
import 'pass_loop.dart';

bool get usesForegroundService => !kIsWeb && Platform.isAndroid;

@pragma('vm:entry-point')
void startPassTask() {
  FlutterForegroundTask.setTaskHandler(_PassTaskHandler());
}

class _PassTaskHandler extends TaskHandler {
  late final PassLoop _loop = PassLoop(_report);

  void _report(PassStatus s) {
    final when = '${s.at.hour.toString().padLeft(2, '0')}:${s.at.minute.toString().padLeft(2, '0')}';
    FlutterForegroundTask.updateService(
      notificationTitle: s.ok ? 'Mobile pass on' : 'Mobile pass: not active',
      notificationText: s.ok ? 'Let in as ${s.ip ?? 'this phone'} · checked in $when' : (s.error ?? 'Trying again shortly'),
    );
    FlutterForegroundTask.sendDataToMain(s.toMap());
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _loop.start();

  @override
  void onRepeatEvent(DateTime timestamp) => _loop.poll();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class PassService {
  final void Function(PassStatus) onStatus;
  Timer? _timer;
  PassLoop? _loop;

  PassService(this.onStatus);

  static void init() {
    if (!usesForegroundService) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mobile_pass',
        channelName: 'Mobile pass',
        channelDescription: 'Shown while the mobile pass is on',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(tick.inMilliseconds),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  void _onTaskData(Object data) {
    if (data is Map) onStatus(PassStatus.fromMap(data));
  }

  Future<bool> get running async => usesForegroundService ? FlutterForegroundTask.isRunningService : _timer != null;

  /// Listens to the background service (if it is already running, e.g. after reopening the app).
  void attach() {
    if (usesForegroundService) FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  void detach() {
    if (usesForegroundService) FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
  }

  Future<String?> start() async {
    if (usesForegroundService) {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      final r = await FlutterForegroundTask.startService(
        serviceId: 4711,
        notificationTitle: 'Mobile pass on',
        notificationText: 'Checking in…',
        callback: startPassTask,
      );
      return r is ServiceRequestFailure ? 'Could not start: ${r.error}' : null;
    }
    _loop = PassLoop(onStatus);
    await _loop!.start();
    _timer = Timer.periodic(tick, (_) => _loop?.poll());
    return null;
  }

  /// Stops checking in and signs the phone out, so its pass ends now rather than in 10 minutes.
  Future<CheckIn?> stop() async {
    if (usesForegroundService) {
      await FlutterForegroundTask.stopService();
    }
    _timer?.cancel();
    _timer = null;
    _loop = null;
    final cfg = await PassConfig.load();
    return cfg == null ? null : signOut(cfg);
  }
}
