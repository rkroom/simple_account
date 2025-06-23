import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:intl/intl.dart';

import 'config_enum.dart';
import 'config_service.dart';
import 'notification_service.dart';
import 'tools.dart';
import 'db.dart';

class WorkmanagerTasks {
  // 每日统计任务
  static const String dailyUniqueName = "dailyTask";
  static const String dailyTaskName = "dailyNotificationTask";

  // 计划任务提醒
  static const String scheduleUniqueName = "scheduleTask";
  static const String scheduleTaskName = "scheduleNotification";
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      bool taskSuccess = false;
      switch (task) {
        case WorkmanagerTasks.dailyTaskName:
          var response = await periodicStatistics();
          await NotificationService().showNotification(
            0,
            "statistics",
            '昨日：${response['previousDayConsumption']}，今日：${response['todayConsumption']}，本月：${response['currentlyMonthConsumption']}',
          );
          taskSuccess = true;
          break;

        case WorkmanagerTasks.scheduleTaskName:
          await handleScheduledNotifications();
          taskSuccess = true;
          break;

        default:
          debugPrint("接收到未知任务: $task");
          taskSuccess = false;
          break;
      }

      if (taskSuccess) {
        await ConfigService().setScheduledTaskTime(DateTime.now());
      }
      return Future.value(taskSuccess);
    } catch (e) {
      return Future.value(false);
    } finally {
      if (task == WorkmanagerTasks.dailyTaskName) {
        await WorkmanagerTool.scheduleDailyTask();
      } else if (task == WorkmanagerTasks.scheduleTaskName) {
        await WorkmanagerTool.scheduleNotificationTask();
      }
    }
  });
}

class WorkmanagerTool {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    _isInitialized = true;
  }

  static Future<void> setupAndScheduleTasks() async {
    await initialize();

    final isDailyTaskEnabled =
        await ConfigService().getNotificationTaskStatus();
    if (isDailyTaskEnabled) {
      await scheduleDailyTask();
    }

    final isScheduleTaskEnabled =
        await ConfigService().getScheduleNotificationTaskStatus();
    if (isScheduleTaskEnabled) {
      await scheduleNotificationTask();
    }

    ConfigService().setScheduledTaskTime(DateTime.now());
  }

  static Future<void> scheduleDailyTask() async {
    await _scheduleGenericTask(
      uniqueName: WorkmanagerTasks.dailyUniqueName,
      taskName: WorkmanagerTasks.dailyTaskName,
      timeConfigFetcher: () => ConfigService().getNotificationTaskTime(),
    );
  }

  static Future<void> scheduleNotificationTask() async {
    await _scheduleGenericTask(
      uniqueName: WorkmanagerTasks.scheduleUniqueName,
      taskName: WorkmanagerTasks.scheduleTaskName,
      timeConfigFetcher:
          () => ConfigService().getScheduleNotificationTaskTime(),
    );
  }

  static Future<void> _scheduleGenericTask({
    required String uniqueName,
    required String taskName,
    required Future<Map<String, int>> Function() timeConfigFetcher,
  }) async {
    await initialize();
    final taskTime = await timeConfigFetcher();
    DateTime now = DateTime.now();
    DateTime nextTime = DateTime(
      now.year,
      now.month,
      now.day,
      taskTime['hour']!,
      taskTime['minute']!,
      taskTime['second']!,
    );

    if (now.isAfter(nextTime)) {
      nextTime = nextTime.add(const Duration(days: 1));
    }

    final initialDelay = nextTime.difference(now);

    await Workmanager().registerOneOffTask(
      uniqueName,
      taskName,
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> cancelDailyTask() async {
    await initialize();
    await Workmanager().cancelByUniqueName(WorkmanagerTasks.dailyUniqueName);
  }

  static Future<void> cancelScheduleNotificationTask() async {
    await initialize();
    await Workmanager().cancelByUniqueName(WorkmanagerTasks.scheduleUniqueName);
  }
}

Future<void> handleScheduledNotifications() async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final List tasks = await DB().getContinuingSchedules();
  final notificationService = NotificationService();

  for (var task in tasks) {
    final round = ScheduleCycle.fromString(task['round']);
    DateTime? targetDate;

    final String? finalDatefValue = task['finaldatef']?.toString();

    switch (round) {
      case ScheduleCycle.day:
        targetDate = today;
        break;
      case ScheduleCycle.week:
        final int dayOfWeek = int.tryParse(task['datesign'].toString()) ?? -1;
        if (dayOfWeek == -1) continue;
        targetDate = today;
        while (targetDate!.weekday != dayOfWeek) {
          targetDate = targetDate.add(const Duration(days: 1));
        }
        break;
      case ScheduleCycle.month:
        final int dayOfMonth = int.tryParse(task['datesign'].toString()) ?? -1;
        if (dayOfMonth < 1 || dayOfMonth > 31) continue;
        final int daysInCurrentMonth =
            DateTime(today.year, today.month + 1, 0).day;
        final int effectiveDayThisMonth = min(dayOfMonth, daysInCurrentMonth);
        DateTime potentialTargetThisMonth = DateTime(
          today.year,
          today.month,
          effectiveDayThisMonth,
        );
        if (potentialTargetThisMonth.isBefore(today)) {
          final DateTime nextMonthFirstDay = DateTime(
            today.year,
            today.month + 1,
            1,
          );
          final int daysInNextMonth =
              DateTime(
                nextMonthFirstDay.year,
                nextMonthFirstDay.month + 1,
                0,
              ).day;
          final int effectiveDayNextMonth = min(dayOfMonth, daysInNextMonth);
          targetDate = DateTime(
            nextMonthFirstDay.year,
            nextMonthFirstDay.month,
            effectiveDayNextMonth,
          );
        } else {
          targetDate = potentialTargetThisMonth;
        }
        break;
      case ScheduleCycle.year:
        if (finalDatefValue != null && finalDatefValue.length >= 10) {
          try {
            final DateFormat parser = DateFormat('yyyy-MM-dd');
            final DateTime parsedFinalDate = parser.parse(finalDatefValue);

            final int targetMonth = parsedFinalDate.month;
            final int targetDay = parsedFinalDate.day;

            int yearToConsider = today.year;
            DateTime potentialTargetDate = DateTime(
              yearToConsider,
              targetMonth,
              targetDay,
            );

            if (potentialTargetDate.isBefore(today)) {
              yearToConsider++;
              final int daysInTargetMonthNextYear =
                  DateTime(yearToConsider, targetMonth + 1, 0).day;
              potentialTargetDate = DateTime(
                yearToConsider,
                targetMonth,
                min(targetDay, daysInTargetMonthNextYear),
              );
            }
            targetDate = potentialTargetDate;
          } catch (e) {
            debugPrint('解析年度计划任务 finaldatef 失败: $finalDatefValue, 错误: $e');
            continue;
          }
        } else {
          debugPrint('年度计划任务 finaldatef 格式不正确或为空: $finalDatefValue');
          continue;
        }
        break;
      case ScheduleCycle.once:
        try {
          targetDate = DateTime.parse(task['finaldate']);
        } catch (e) {
          debugPrint(
            '解析一次性计划任务 finaldate 失败: ${task['finaldatef'] ?? task['datesign']}, 错误: $e',
          );
          continue;
        }
        break;

      case ScheduleCycle.custom:
        try {
          final DateTime baseDate = DateTime.parse(
            task['finaldatef'].toString(),
          );
          final int intervalDays =
              int.tryParse(task['datesign'].toString()) ?? 0;

          if (intervalDays <= 0) {
            continue;
          }

          if (baseDate.isAfter(today) || baseDate.isAtSameMomentAs(today)) {
            targetDate = baseDate;
          } else {
            final int diffInDays = today.difference(baseDate).inDays;
            final int intervalsNeeded =
                (diffInDays.toDouble() / intervalDays).ceil();
            targetDate = baseDate.add(
              Duration(days: intervalsNeeded * intervalDays),
            );
          }
        } catch (e) {
          debugPrint(
            '解析自定义计划任务 finaldatef/datesign 失败: ${task['finaldatef'] ?? task['datesign']}, 错误: $e',
          );
          continue;
        }
        break;
    }

    if (targetDate.isBefore(today)) {
      continue;
    }

    final int daysUntil = targetDate.difference(today).inDays;
    bool shouldNotify = false;
    String notificationTitle = "提醒";

    switch (round) {
      case ScheduleCycle.day:
        if (daysUntil == 0) {
          shouldNotify = true;
          notificationTitle = "今天";
        }
        break;

      case ScheduleCycle.week:
        if (daysUntil == 1) {
          shouldNotify = true;
          notificationTitle = "明天";
        } else if (daysUntil == 0) {
          shouldNotify = true;
          notificationTitle = "今天";
        }
        break;

      case ScheduleCycle.month:
      case ScheduleCycle.year:
      case ScheduleCycle.once:
        if (daysUntil >= 0 && daysUntil <= 2) {
          shouldNotify = true;
          if (daysUntil == 2) {
            notificationTitle = "后天";
          } else if (daysUntil == 1) {
            notificationTitle = "明天";
          } else {
            notificationTitle = "今天";
          }
        }
        break;

      case ScheduleCycle.custom:
        final int intervalDays = int.tryParse(task['datesign'].toString()) ?? 0;

        if (intervalDays > 0 && intervalDays < 3) {
          if (daysUntil == 0) {
            shouldNotify = true;
            notificationTitle = "今天";
          }
        } else {
          if (daysUntil >= 0 && daysUntil <= 2) {
            shouldNotify = true;
            if (daysUntil == 2) {
              notificationTitle = "后天";
            } else if (daysUntil == 1) {
              notificationTitle = "明天";
            } else {
              notificationTitle = "今天";
            }
          }
        }
        break;
    }

    if (shouldNotify) {
      final int notificationId = task['id'];
      final String taskComment = task['content'] ?? '您有一个计划待处理，点击查看详情。';
      await notificationService.showScheduleNotification(
        notificationId,
        notificationTitle,
        taskComment,
      );
    }
  }
}
