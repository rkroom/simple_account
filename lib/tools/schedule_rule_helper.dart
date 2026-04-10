import 'dart:convert';

import 'package:intl/intl.dart';

import 'config_enum.dart';
import 'entity.dart';

Map<String, dynamic>? parseRuleParams(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;

  final text = raw.toString().trim();
  if (text.isEmpty) return null;

  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {}
  return null;
}

int? readRuleInt(Map<String, dynamic>? params, String key) {
  if (params == null) return null;
  final value = params[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _safeDate(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  final targetDay = day < 1 ? 1 : (day > lastDay ? lastDay : day);
  return DateTime(year, month, targetDay);
}

DateTime _subtractMonths(DateTime from, int months) {
  int targetYear = from.year;
  int targetMonth = from.month - months;

  while (targetMonth <= 0) {
    targetMonth += 12;
    targetYear -= 1;
  }

  final lastDayOfTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
  final day = from.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : from.day;

  return DateTime(
    targetYear,
    targetMonth,
    day,
    from.hour,
    from.minute,
    from.second,
    from.millisecond,
    from.microsecond,
  );
}

DateTime _nextQuarterMonthDay(
  DateTime now,
  int monthOfQuarter,
  int dayOfMonth,
) {
  final today = _dateOnly(now);
  final currentQuarterStartMonth = ((today.month - 1) ~/ 3) * 3 + 1;

  for (int i = 0; i < 12; i++) {
    final baseMonthIndex = currentQuarterStartMonth - 1 + i * 3;
    final year = today.year + baseMonthIndex ~/ 12;
    final quarterStartMonth = baseMonthIndex % 12 + 1;

    final targetMonth = quarterStartMonth + monthOfQuarter - 1;
    final candidate = _safeDate(year, targetMonth, dayOfMonth);

    if (!candidate.isBefore(today)) {
      return candidate;
    }
  }

  throw StateError('无法计算下一次季度任务日期');
}

DateTime _nextQuarterDay(DateTime now, int dayOfQuarter) {
  final today = _dateOnly(now);
  final currentQuarterStartMonth = ((today.month - 1) ~/ 3) * 3 + 1;

  for (int i = 0; i < 12; i++) {
    final baseMonthIndex = currentQuarterStartMonth - 1 + i * 3;
    final year = today.year + baseMonthIndex ~/ 12;
    final quarterStartMonth = baseMonthIndex % 12 + 1;

    final quarterStart = DateTime(year, quarterStartMonth, 1);
    final quarterEnd = DateTime(year, quarterStartMonth + 3, 0);

    DateTime candidate = quarterStart.add(Duration(days: dayOfQuarter - 1));
    if (candidate.isAfter(quarterEnd)) {
      candidate = quarterEnd;
    }

    if (!candidate.isBefore(today)) {
      return candidate;
    }
  }

  throw StateError('无法计算下一次季度任务自定义日期');
}

DateTime _nextMonthAfterDay(DateTime now, int anchorDay, int offsetDays) {
  final today = _dateOnly(now);

  for (int i = 0; i < 24; i++) {
    final monthIndex = today.month - 1 + i;
    final year = today.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;

    final anchorDate = _safeDate(year, month, anchorDay);
    final dueDate = _dateOnly(anchorDate.add(Duration(days: offsetDays)));

    if (!dueDate.isBefore(today)) {
      return dueDate;
    }
  }

  throw StateError('无法计算每月自定义任务日期');
}

String calcNextScheduleDate({
  required DateTime now,
  required ScheduleCycle cycle,
  String? dateSign,
  String? finalDateValue,
  Map<String, dynamic>? ruleParams,
}) {
  final formatter = DateFormat('yyyy-MM-dd');
  final today = _dateOnly(now);

  switch (cycle) {
    case ScheduleCycle.day:
      return formatter.format(today);

    case ScheduleCycle.week:
      final targetWeekday = int.tryParse(dateSign ?? '');
      if (targetWeekday == null || targetWeekday < 1 || targetWeekday > 7) {
        throw const FormatException('week 类型缺少有效 weekday');
      }
      int daysToAdd = targetWeekday - today.weekday;
      if (daysToAdd < 0) {
        daysToAdd += 7;
      }
      return formatter.format(today.add(Duration(days: daysToAdd)));

    case ScheduleCycle.month:
      final targetDay = int.tryParse(dateSign ?? '');
      if (targetDay == null || targetDay < 1) {
        throw const FormatException('month 类型缺少有效 day');
      }
      DateTime candidate = _safeDate(today.year, today.month, targetDay);
      if (candidate.isBefore(today)) {
        final nextMonth = DateTime(today.year, today.month + 1, 1);
        candidate = _safeDate(nextMonth.year, nextMonth.month, targetDay);
      }
      return formatter.format(candidate);

    case ScheduleCycle.year:
      if (finalDateValue == null || finalDateValue.isEmpty) {
        throw const FormatException('year 类型缺少 finalDate');
      }
      final parsed = normalizeDate(DateTime.parse(finalDateValue));
      DateTime candidate = _safeDate(today.year, parsed.month, parsed.day);
      if (candidate.isBefore(today)) {
        candidate = _safeDate(today.year + 1, parsed.month, parsed.day);
      }
      return formatter.format(candidate);

    case ScheduleCycle.once:
      if (finalDateValue != null && finalDateValue.isNotEmpty) {
        return formatter.format(normalizeDate(DateTime.parse(finalDateValue)));
      }
      if (dateSign != null && dateSign.isNotEmpty) {
        return formatter.format(normalizeDate(DateTime.parse(dateSign)));
      }
      throw const FormatException('once 类型缺少日期');

    case ScheduleCycle.custom:
      if (finalDateValue == null || finalDateValue.isEmpty) {
        throw const FormatException('custom 类型缺少起始日期');
      }
      final startDate = normalizeDate(DateTime.parse(finalDateValue));
      final intervalDays = int.tryParse(dateSign ?? '');
      if (intervalDays == null || intervalDays <= 0) {
        throw const FormatException('custom 类型缺少有效的间隔天数');
      }

      if (startDate.isAfter(today)) {
        return formatter.format(startDate);
      }

      final diff = today.difference(startDate).inDays;
      final passed = diff ~/ intervalDays;
      DateTime candidate = startDate.add(Duration(days: passed * intervalDays));
      if (candidate.isBefore(today)) {
        candidate = candidate.add(Duration(days: intervalDays));
      }
      return formatter.format(candidate);

    case ScheduleCycle.quarterMonthDay:
      final monthOfQuarter = readRuleInt(ruleParams, 'monthOfQuarter');
      final dayOfMonth = readRuleInt(ruleParams, 'dayOfMonth');
      if (monthOfQuarter == null ||
          monthOfQuarter < 1 ||
          monthOfQuarter > 3 ||
          dayOfMonth == null ||
          dayOfMonth < 1) {
        throw const FormatException('quarterMonthDay 参数无效');
      }
      return formatter.format(
        _nextQuarterMonthDay(today, monthOfQuarter, dayOfMonth),
      );

    case ScheduleCycle.quarterDay:
      final dayOfQuarter = readRuleInt(ruleParams, 'dayOfQuarter');
      if (dayOfQuarter == null || dayOfQuarter < 1) {
        throw const FormatException('quarterDay 参数无效');
      }
      return formatter.format(_nextQuarterDay(today, dayOfQuarter));

    case ScheduleCycle.monthAfterDay:
      final anchorDay = readRuleInt(ruleParams, 'anchorDay');
      final offsetDays = readRuleInt(ruleParams, 'offsetDays');
      if (anchorDay == null ||
          anchorDay < 1 ||
          offsetDays == null ||
          offsetDays < 1) {
        throw const FormatException('monthAfterDay 参数无效');
      }
      return formatter.format(_nextMonthAfterDay(today, anchorDay, offsetDays));
  }
}

String formatScheduleCycle(ScheduleItem item) {
  switch (item.cycleValue) {
    case ScheduleCycle.day:
      return '每天';
    case ScheduleCycle.week:
      const weekMap = {
        '1': '一',
        '2': '二',
        '3': '三',
        '4': '四',
        '5': '五',
        '6': '六',
        '7': '日',
      };
      return '每周${weekMap[item.dateSign] ?? ''}';
    case ScheduleCycle.month:
      final day = int.tryParse(item.dateSign);
      return day == null ? '每月${item.dateSign}日' : '每月$day日';
    case ScheduleCycle.year:
      if (item.finalDate != null && item.finalDate!.isNotEmpty) {
        try {
          final date = DateTime.parse(item.finalDate!);
          return '每年${DateFormat('M月d日', 'zh_CN').format(date)}';
        } catch (_) {}
      }
      return '每年';
    case ScheduleCycle.custom:
      return '每${item.dateSign}天';
    case ScheduleCycle.once:
      return '';
    case ScheduleCycle.quarterMonthDay:
      final monthOfQuarter = readRuleInt(item.ruleParams, 'monthOfQuarter');
      final dayOfMonth = readRuleInt(item.ruleParams, 'dayOfMonth');
      return '每季度第${monthOfQuarter ?? '?'}个月${dayOfMonth ?? '?'}日';
    case ScheduleCycle.quarterDay:
      final dayOfQuarter = readRuleInt(item.ruleParams, 'dayOfQuarter');
      return '每季度第${dayOfQuarter ?? '?'}天';
    case ScheduleCycle.monthAfterDay:
      final anchorDay = readRuleInt(item.ruleParams, 'anchorDay');
      final offsetDays = readRuleInt(item.ruleParams, 'offsetDays');
      return '每月${anchorDay ?? '?'}日之后第${offsetDays ?? '?'}天';
  }
}

DateTime? getPreviousDueDateForItem(
  ScheduleItem item,
  DateTime currentDueDate,
) {
  final normalizedCurrent = normalizeDate(currentDueDate);

  switch (item.cycleValue) {
    case ScheduleCycle.once:
      return null;

    case ScheduleCycle.day:
      return normalizedCurrent.subtract(const Duration(days: 1));

    case ScheduleCycle.week:
      return normalizedCurrent.subtract(const Duration(days: 7));

    case ScheduleCycle.custom:
      final days = int.tryParse(item.dateSign);
      if (days == null || days <= 0) return null;
      return normalizedCurrent.subtract(Duration(days: days));

    case ScheduleCycle.month:
      return _subtractMonths(normalizedCurrent, 1);

    case ScheduleCycle.year:
      return _subtractMonths(normalizedCurrent, 12);

    case ScheduleCycle.quarterMonthDay:
      final monthOfQuarter = readRuleInt(item.ruleParams, 'monthOfQuarter');
      final dayOfMonth = readRuleInt(item.ruleParams, 'dayOfMonth');
      if (monthOfQuarter == null || dayOfMonth == null) return null;

      final ref = DateTime(
        normalizedCurrent.year,
        normalizedCurrent.month - 3,
        1,
      );
      final quarterStartMonth = ((ref.month - 1) ~/ 3) * 3 + 1;
      return _safeDate(
        ref.year,
        quarterStartMonth + monthOfQuarter - 1,
        dayOfMonth,
      );

    case ScheduleCycle.quarterDay:
      final dayOfQuarter = readRuleInt(item.ruleParams, 'dayOfQuarter');
      if (dayOfQuarter == null || dayOfQuarter <= 0) return null;

      final ref = DateTime(
        normalizedCurrent.year,
        normalizedCurrent.month - 3,
        1,
      );
      final quarterStartMonth = ((ref.month - 1) ~/ 3) * 3 + 1;
      final quarterStart = DateTime(ref.year, quarterStartMonth, 1);
      final quarterEnd = DateTime(ref.year, quarterStartMonth + 3, 0);

      DateTime candidate = quarterStart.add(Duration(days: dayOfQuarter - 1));
      if (candidate.isAfter(quarterEnd)) {
        candidate = quarterEnd;
      }
      return normalizeDate(candidate);

    case ScheduleCycle.monthAfterDay:
      final anchorDay = readRuleInt(item.ruleParams, 'anchorDay');
      final offsetDays = readRuleInt(item.ruleParams, 'offsetDays');
      if (anchorDay == null || offsetDays == null) return null;

      final ref = DateTime(
        normalizedCurrent.year,
        normalizedCurrent.month - 1,
        1,
      );
      final anchorDate = _safeDate(ref.year, ref.month, anchorDay);
      return normalizeDate(anchorDate.add(Duration(days: offsetDays)));
  }
}
