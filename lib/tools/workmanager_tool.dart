import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'config_enum.dart';
import 'config_service.dart';
import 'notification_service.dart';
import 'tools.dart';
import 'db.dart';
import 'schedule_rule_helper.dart';
import 'schedule_notification_helper.dart';
import 'entity.dart';

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
      debugPrint('Workmanager 执行失败: $e');
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

  for (final task in tasks) {
    try {
      final String cycleRaw =
          (task['rule_type'] ?? task['round'] ?? '').toString();
      final ScheduleCycle cycle = ScheduleCycle.fromString(cycleRaw);

      final Map<String, dynamic>? ruleParams = parseRuleParams(
        task['rule_params'],
      );

      final String? finalDateValue =
          task['finaldatef']?.toString() ?? task['finaldate']?.toString();

      final String targetDateStr = calcNextScheduleDate(
        now: today,
        cycle: cycle,
        dateSign: task['datesign']?.toString(),
        finalDateValue: finalDateValue,
        ruleParams: ruleParams,
      );

      final DateTime targetDate = normalizeDate(DateTime.parse(targetDateStr));
      final int daysUntil = targetDate.difference(today).inDays;

      // 已经在当前周期完成过，就不再提醒
      final bool alreadyCompleted = _isCompletedInCurrentCycle(
        cycle: cycle,
        currentDueDateStr: targetDateStr,
        lastHandledDateStr: task['handledate']?.toString(),
        createdStr: (task['createdf'] ?? task['created'] ?? '').toString(),
        dateSign: task['datesign']?.toString(),
        finalDateValue: finalDateValue,
        ruleParams: ruleParams,
      );

      if (alreadyCompleted) {
        continue;
      }

      final decision = decideScheduleNotification(
        cycle: cycle,
        daysUntil: daysUntil,
        ruleParams: ruleParams,
        legacyDateSign: task['datesign']?.toString(),
      );

      if (!decision.shouldNotify) {
        continue;
      }

      final int notificationId = task['id'];
      final String taskComment =
          task['content']?.toString() ?? '您有一个计划待处理，点击查看详情。';

      await notificationService.showScheduleNotification(
        notificationId,
        decision.title,
        taskComment,
      );
    } catch (e) {
      debugPrint('处理计划提醒失败，任务ID=${task['id']}，错误: $e');
      continue;
    }
  }
}

bool _isCompletedInCurrentCycle({
  required ScheduleCycle cycle,
  required String currentDueDateStr,
  required String? lastHandledDateStr,
  required String createdStr,
  required String? dateSign,
  required String? finalDateValue,
  Map<String, dynamic>? ruleParams,
}) {
  final DateTime? lastHandled = DateTime.tryParse(lastHandledDateStr ?? '');
  if (lastHandled == null) return false;

  final DateTime dueDate = normalizeDate(DateTime.parse(currentDueDateStr));
  final DateTime handledDate = normalizeDate(lastHandled);

  // 一次性任务：只要已经处理过且处理日期不晚于本次到期日，就视为已完成
  if (cycle == ScheduleCycle.once) {
    return !handledDate.isAfter(dueDate);
  }

  final tempItem = ScheduleItem(
    id: 0,
    content: '',
    date: currentDueDateStr,
    lastCompletedDate: lastHandledDateStr,
    finished: null,
    cycleValue: cycle,
    created: createdStr,
    status: ScheduleStatus.continuing,
    dateSign: dateSign ?? '',
    finalDate: finalDateValue,
    ruleParams: ruleParams,
  );

  final DateTime? previousDueDate = getPreviousDueDateForItem(
    tempItem,
    dueDate,
  );

  if (previousDueDate == null) {
    return !handledDate.isAfter(dueDate);
  }

  final DateTime prev = normalizeDate(previousDueDate);

  // 只要“最后完成日期”落在 (上次应执行日, 本次应执行日] 内，
  // 就说明本周期已经完成，不应再提醒
  return handledDate.isAfter(prev) && !handledDate.isAfter(dueDate);
}
