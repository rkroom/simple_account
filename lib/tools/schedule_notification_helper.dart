import 'config_enum.dart';
import 'schedule_rule_helper.dart';

class ScheduleNotificationDecision {
  final bool shouldNotify;
  final String title;

  const ScheduleNotificationDecision({
    required this.shouldNotify,
    required this.title,
  });
}

ScheduleNotificationDecision decideScheduleNotification({
  required ScheduleCycle cycle,
  required int daysUntil,
  Map<String, dynamic>? ruleParams,
  String? legacyDateSign,
}) {
  if (daysUntil < 0) {
    return const ScheduleNotificationDecision(shouldNotify: false, title: '提醒');
  }

  switch (cycle) {
    case ScheduleCycle.day:
      return _buildDecision(shouldNotify: daysUntil == 0, daysUntil: daysUntil);
    case ScheduleCycle.week:
      return _buildDecision(
        shouldNotify: daysUntil == 0 || daysUntil == 1,
        daysUntil: daysUntil,
      );
    case ScheduleCycle.month:
    case ScheduleCycle.year:
    case ScheduleCycle.once:
    case ScheduleCycle.quarterMonthDay:
    case ScheduleCycle.quarterDay:
    case ScheduleCycle.monthAfterDay:
      return _buildDecision(shouldNotify: daysUntil <= 2, daysUntil: daysUntil);
    case ScheduleCycle.custom:
      return _decideCustomNotification(
        daysUntil: daysUntil,
        ruleParams: ruleParams,
        legacyDateSign: legacyDateSign,
      );
  }
}

ScheduleNotificationDecision _decideCustomNotification({
  required int daysUntil,
  Map<String, dynamic>? ruleParams,
  String? legacyDateSign,
}) {
  if (daysUntil < 0) {
    return const ScheduleNotificationDecision(shouldNotify: false, title: '提醒');
  }

  final int? intervalFromRule = readRuleInt(ruleParams, 'interval');
  final String? unitStr = readRuleString(ruleParams, 'unit');
  final int? legacyInterval = int.tryParse(legacyDateSign ?? '');

  final int interval =
      (intervalFromRule != null && intervalFromRule > 0)
          ? intervalFromRule
          : ((legacyInterval != null && legacyInterval > 0)
              ? legacyInterval
              : 0);

  final CustomIntervalUnit unit =
      intervalFromRule != null && intervalFromRule > 0
          ? CustomIntervalUnit.fromString(unitStr)
          : CustomIntervalUnit.day;

  switch (unit) {
    case CustomIntervalUnit.day:
      if (interval > 0 && interval < 3) {
        return _buildDecision(
          shouldNotify: daysUntil == 0,
          daysUntil: daysUntil,
        );
      }
      return _buildDecision(shouldNotify: daysUntil <= 2, daysUntil: daysUntil);

    case CustomIntervalUnit.week:
      if (interval == 1) {
        return _buildDecision(
          shouldNotify: daysUntil == 0 || daysUntil == 1,
          daysUntil: daysUntil,
        );
      }
      return _buildDecision(shouldNotify: daysUntil <= 2, daysUntil: daysUntil);

    case CustomIntervalUnit.month:
    case CustomIntervalUnit.quarter:
    case CustomIntervalUnit.year:
      return _buildDecision(shouldNotify: daysUntil <= 2, daysUntil: daysUntil);
  }
}

ScheduleNotificationDecision _buildDecision({
  required bool shouldNotify,
  required int daysUntil,
}) {
  return ScheduleNotificationDecision(
    shouldNotify: shouldNotify,
    title: shouldNotify ? notificationTitleFromDaysUntil(daysUntil) : '提醒',
  );
}

String notificationTitleFromDaysUntil(int daysUntil) {
  switch (daysUntil) {
    case 0:
      return '今天';
    case 1:
      return '明天';
    case 2:
      return '后天';
    default:
      return '提醒';
  }
}
