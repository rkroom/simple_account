import 'package:simple_account/tools/config_service.dart';
import 'package:workmanager/workmanager.dart';
import 'notification_service.dart';
import 'tools.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    var response = await periodicStatistics();

    await NotificationService().showNotification(
      0,
      "statistics",
      '昨日：${response['previousDayConsumption']}，今日：${response['todayConsumption']}，本月：${response['currentlyMonthConsumption']}',
    );

    // 在任务执行完后重新注册下次任务
    scheduleDailyTask();
    ConfigService().setScheduledTaskTime(DateTime.now());
    return Future.value(true);
  });
}

void scheduleDailyTask() async {
  final notificationTaskTime = await ConfigService().getNotificationTaskTime();

  // 获取当前时间
  DateTime now = DateTime.now();

  // 下一个时间
  DateTime nextTime = DateTime(
    now.year,
    now.month,
    now.day,
    notificationTaskTime['hour']!,
    notificationTaskTime['minute']!,
    notificationTaskTime['second']!,
  );

  // 如果当前时间已经过了设定时间，设置为明天的同一时间
  if (now.isAfter(nextTime)) {
    nextTime = nextTime.add(const Duration(days: 1));
  }

  // 计算当前时间到设定时间的时间差
  Duration initialDelay = nextTime.difference(now);

  //取消之前任务，避免重复执行
  await Workmanager().cancelByUniqueName("dailyTask");
  // 注册一次性任务，延迟到设定时间
  await Workmanager().registerOneOffTask(
    "dailyTask", // 唯一的任务名，确保不会重复注册
    "dailyNotificationTask",
    initialDelay: initialDelay,
    existingWorkPolicy: ExistingWorkPolicy.replace, // 确保旧任务被替换
  );
}

void cancelDailyTask() async {
  await Workmanager().cancelByUniqueName("dailyTask");
}
