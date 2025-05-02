import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform;
import 'dart:math' as math;

// Priority の名前の衝突を回避するためのインポート
import '../main.dart' as app;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false; // 初期化状態を追跡

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  // 通知の初期化
  Future<void> init() async {
    // すでに初期化済みなら何もしない
    if (_isInitialized) {
      debugPrint('通知サービスはすでに初期化されています');
      return;
    }

    try {
      debugPrint('通知サービスの初期化を開始します...');

      // タイムゾーンの初期化
      try {
        tz.initializeTimeZones();
        debugPrint('タイムゾーンの初期化に成功しました');
      } catch (e) {
        debugPrint('タイムゾーンの初期化に失敗しました: $e');
        // エラーがあっても処理を続行
      }

      // iOS/macOS向けの通知設定
      DarwinInitializationSettings? darwinSettings;

      if (Platform.isIOS || Platform.isMacOS) {
        try {
          darwinSettings = const DarwinInitializationSettings(
            requestAlertPermission: false, // ここで許可を求めない（後で行う）
            requestBadgePermission: false, // ここで許可を求めない（後で行う）
            requestSoundPermission: false, // ここで許可を求めない（後で行う）
          );
          debugPrint('Darwin設定を初期化しました');
        } catch (e) {
          debugPrint('Darwin設定の初期化に失敗しました: $e');
          // ダミー設定を作成して続行
          darwinSettings = const DarwinInitializationSettings();
        }
      } else {
        // iOSやmacOSでなければnullのままでOK
        darwinSettings = null;
      }

      // Android設定
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // 初期化設定
      final InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: darwinSettings,
            macOS: darwinSettings,
          );

      // 初期化処理
      try {
        await flutterLocalNotificationsPlugin.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (
            NotificationResponse notificationResponse,
          ) async {
            // 通知がタップされた時の処理
            final String? payload = notificationResponse.payload;
            if (payload != null) {
              debugPrint('通知ペイロード: $payload');
            }
          },
        );

        debugPrint('フラッターローカル通知の初期化に成功しました');
      } catch (e) {
        debugPrint('通知プラグインの初期化に失敗しました: $e');
        // 初期化に失敗してもアプリ自体は動くようにする
      }

      // iOSとmacOSで権限リクエスト（アプリが表示された後で安全に実行する）
      if (Platform.isIOS || Platform.isMacOS) {
        // 少し待機してから権限リクエスト（画面表示を安定させるため）
        await Future.delayed(const Duration(milliseconds: 500));
        await _requestNotificationPermissions();
      }

      // 初期化成功
      _isInitialized = true;
      debugPrint('通知サービスの初期化が完了しました');
    } catch (e) {
      debugPrint('通知サービスの初期化中にエラーが発生しました: $e');
      // エラーが発生しても初期化済みとマークして再試行を防止（アプリの動作を継続させる）
      _isInitialized = true;
    }
  }

  // 通知権限のリクエスト（iOSとmacOS用）
  Future<void> _requestNotificationPermissions() async {
    try {
      // プラットフォーム固有の初期化
      if (Platform.isIOS) {
        try {
          debugPrint('iOSの通知権限をリクエスト中...');
          final iosPlugin =
              flutterLocalNotificationsPlugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >();

          if (iosPlugin != null) {
            await iosPlugin.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
            debugPrint('iOS通知権限のリクエスト完了');
          }
        } catch (e) {
          debugPrint('iOS通知権限のリクエスト中にエラーが発生: $e');
        }
      } else if (Platform.isMacOS) {
        try {
          debugPrint('macOSの通知権限をリクエスト中...');
          final macPlugin =
              flutterLocalNotificationsPlugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >();

          if (macPlugin != null) {
            await macPlugin.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
            debugPrint('macOS通知権限のリクエスト完了');
          }
        } catch (e) {
          debugPrint('macOS通知権限のリクエスト中にエラーが発生: $e');
        }
      }
    } catch (e) {
      debugPrint('通知権限リクエスト中に一般エラーが発生: $e');
    }
  }

  // 通知設定を読み込む
  Future<Map<String, dynamic>> loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enableDueReminders': prefs.getBool('enableDueReminders') ?? false,
      'reminderTime': prefs.getInt('reminderMinutes') ?? 60, // デフォルトは60分（1時間）前
      'notifyHighPriority': prefs.getBool('notifyHighPriority') ?? false,
    };
  }

  // 通知設定を保存する
  Future<void> saveNotificationSettings({
    required bool enableDueReminders,
    required int reminderTime, // 分単位
    required bool notifyHighPriority,
    List<app.TodoItem>? todos, // 既存のタスクリスト
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enableDueReminders', enableDueReminders);
      await prefs.setInt('reminderMinutes', reminderTime);
      await prefs.setBool('notifyHighPriority', notifyHighPriority);

      // 設定変更時に既存のタスクの通知を再スケジュール
      if (todos != null && todos.isNotEmpty) {
        debugPrint('通知設定が変更されました。既存の通知を再スケジュールします。');
        await rescheduleAllNotifications(todos);
      }
    } catch (e) {
      debugPrint('通知設定の保存中にエラー発生: $e');
    }
  }

  // 期限日のリマインダー通知をスケジュール
  Future<void> scheduleDueReminder(app.TodoItem todo) async {
    // 初期化されていないか期限日がない場合は何もしない
    if (!_isInitialized || todo.dueDate == null) {
      return;
    }

    try {
      final settings = await loadNotificationSettings();
      if (!settings['enableDueReminders']) return;

      // 既存の通知をキャンセル
      await cancelNotification(todo.id);

      // 通知する時間（期限の何分前）
      final int minutesBeforeDue = settings['reminderTime'];
      debugPrint('通知設定：期限の$minutesBeforeDue分前に通知します');

      // タイムゾーン関連エラー対策
      tz.TZDateTime? scheduledDate;
      try {
        scheduledDate = tz.TZDateTime.from(
          todo.dueDate!.subtract(Duration(minutes: minutesBeforeDue)),
          tz.local,
        );

        debugPrint('期限日時: ${todo.dueDate}, 通知予定日時: $scheduledDate');

        // 現在時刻を過ぎている場合はスケジュールしない
        final now = tz.TZDateTime.now(tz.local);
        if (scheduledDate.isBefore(now)) {
          debugPrint('通知予定時刻が過去のため、通知をスキップします');
          return;
        }
      } catch (e) {
        debugPrint('タイムゾーン変換エラー: $e');
        return;
      }

      // 通知メッセージを作成
      String timeMessage;
      if (minutesBeforeDue < 60) {
        timeMessage = '$minutesBeforeDue分後が期限です';
      } else if (minutesBeforeDue == 60) {
        timeMessage = '1時間後が期限です';
      } else {
        final hours = minutesBeforeDue ~/ 60;
        final remainingMinutes = minutesBeforeDue % 60;
        if (remainingMinutes == 0) {
          timeMessage = '$hours時間後が期限です';
        } else {
          timeMessage = '$hours時間$remainingMinutes分後が期限です';
        }
      }

      // iOS/macOS用の通知詳細
      final darwinNotificationDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      // 通知をスケジュール
      final notificationId = _getNotificationIdFromTodoId(todo.id);
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        '${todo.title} の期限が近づいています',
        timeMessage,
        scheduledDate,
        NotificationDetails(
          android: const AndroidNotificationDetails(
            'due_reminder_channel',
            '期限リマインダー',
            channelDescription: 'TODOの期限が近づいたときに通知します',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: darwinNotificationDetails,
          macOS: darwinNotificationDetails,
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: todo.id,
      );

      debugPrint('通知をスケジュールしました: ID=$notificationId, 日時=$scheduledDate');
    } catch (e) {
      debugPrint('通知のスケジュール中にエラー発生: $e');
    }
  }

  // TodoIDから通知IDを取得（IDの衝突を避けるために整数に変換）
  int _getNotificationIdFromTodoId(String todoId) {
    try {
      // IDの先頭9文字を取得して整数に変換（範囲内に収める）
      return int.parse(todoId.substring(0, math.min(9, todoId.length))) %
          100000;
    } catch (e) {
      // 変換に失敗した場合はハッシュコードを使用
      return todoId.hashCode.abs() % 100000;
    }
  }

  // 優先度が高いタスクの通知
  Future<void> notifyHighPriorityTask(app.TodoItem todo) async {
    if (!_isInitialized || todo.priority != app.Priority.high) {
      return;
    }

    try {
      final settings = await loadNotificationSettings();
      if (!settings['notifyHighPriority']) return;

      // iOS/macOS用の通知詳細
      final darwinNotificationDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      final notificationId = _getNotificationIdFromTodoId(todo.id);
      await flutterLocalNotificationsPlugin.show(
        notificationId,
        '優先度の高いタスクが追加されました',
        todo.title,
        NotificationDetails(
          android: const AndroidNotificationDetails(
            'high_priority_channel',
            '優先度高タスク',
            channelDescription: '優先度の高いタスクについて通知します',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: darwinNotificationDetails,
          macOS: darwinNotificationDetails,
        ),
        payload: todo.id,
      );
    } catch (e) {
      debugPrint('高優先度タスク通知の送信中にエラー発生: $e');
    }
  }

  // 通知をキャンセル
  Future<void> cancelNotification(String todoId) async {
    if (!_isInitialized) return;

    try {
      final notificationId = _getNotificationIdFromTodoId(todoId);
      await flutterLocalNotificationsPlugin.cancel(notificationId);
    } catch (e) {
      debugPrint('通知のキャンセル中にエラー発生: $e');
    }
  }

  // すべての通知をキャンセル
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;

    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('全通知のキャンセル中にエラー発生: $e');
    }
  }

  // すべてのTODOの通知をスケジュールし直す
  Future<void> rescheduleAllNotifications(List<app.TodoItem> todos) async {
    if (!_isInitialized) {
      debugPrint('通知サービスが初期化されていません。通知を再スケジュールできません。');
      return;
    }

    try {
      // すべての通知をキャンセル
      await cancelAllNotifications();

      final settings = await loadNotificationSettings();
      if (!settings['enableDueReminders']) return;

      // 完了していないTODOでかつ期限日があるものだけ通知をスケジュール
      for (final todo in todos) {
        if (!todo.completed && todo.dueDate != null) {
          await scheduleDueReminder(todo);
        }
      }
    } catch (e) {
      debugPrint('通知の再スケジュール中にエラー発生: $e');
    }
  }
}
