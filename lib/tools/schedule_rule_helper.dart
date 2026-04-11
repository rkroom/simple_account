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

String? readRuleString(Map<String, dynamic>? params, String key) {
  if (params == null) return null;
  final value = params[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime _safeDate(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  final targetDay = day < 1 ? 1 : (day > lastDay ? lastDay : day);
  return DateTime(year, month, targetDay);
}

DateTime _addMonths(DateTime from, int months) {
  final totalMonths = from.year * 12 + (from.month - 1) + months;
  int year = totalMonths ~/ 12;
  int month = totalMonths % 12 + 1;

  if (month <= 0) {
    month += 12;
    year -= 1;
  }

  final lastDay = DateTime(year, month + 1, 0).day;
  final day = from.day > lastDay ? lastDay : from.day;

  return DateTime(
    year,
    month,
    day,
    from.hour,
    from.minute,
    from.second,
    from.millisecond,
    from.microsecond,
  );
}

DateTime _addYears(DateTime from, int years) {
  return _safeDate(from.year + years, from.month, from.day);
}

DateTime _addByCustomUnit(DateTime from, CustomIntervalUnit unit, int amount) {
  switch (unit) {
    case CustomIntervalUnit.day:
      return normalizeDate(from.add(Duration(days: amount)));
    case CustomIntervalUnit.week:
      return normalizeDate(from.add(Duration(days: amount * 7)));
    case CustomIntervalUnit.month:
      return normalizeDate(_addMonths(from, amount));
    case CustomIntervalUnit.quarter:
      return normalizeDate(_addMonths(from, amount * 3));
    case CustomIntervalUnit.year:
      return normalizeDate(_addYears(from, amount));
  }
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

class _CustomRule {
  final DateTime startDate;
  final int interval;
  final CustomIntervalUnit unit;
  final int offsetDays;

  const _CustomRule({
    required this.startDate,
    required this.interval,
    required this.unit,
    required this.offsetDays,
  });
}

_CustomRule _readCustomRule({
  required String? finalDateValue,
  required String? legacyDateSign,
  required Map<String, dynamic>? ruleParams,
}) {
  if (finalDateValue == null || finalDateValue.isEmpty) {
    throw const FormatException('custom 类型缺少起始日期');
  }

  final startDate = normalizeDate(DateTime.parse(finalDateValue));

  final interval = readRuleInt(ruleParams, 'interval');
  final unitStr = readRuleString(ruleParams, 'unit');
  final offsetDays = readRuleInt(ruleParams, 'offsetDays') ?? 0;

  if (interval != null && interval > 0) {
    return _CustomRule(
      startDate: startDate,
      interval: interval,
      unit: CustomIntervalUnit.fromString(unitStr),
      offsetDays: offsetDays < 0 ? 0 : offsetDays,
    );
  }

  // 兼容旧数据：custom = 起始日期 + 每 N 天
  final legacyInterval = int.tryParse(legacyDateSign ?? '');
  if (legacyInterval != null && legacyInterval > 0) {
    return _CustomRule(
      startDate: startDate,
      interval: legacyInterval,
      unit: CustomIntervalUnit.day,
      offsetDays: 0,
    );
  }

  throw const FormatException('custom 类型缺少有效 interval');
}

DateTime _customDueAtStep(_CustomRule rule, int step) {
  final anchor = _addByCustomUnit(
    rule.startDate,
    rule.unit,
    rule.interval * step,
  );
  return normalizeDate(anchor.add(Duration(days: rule.offsetDays)));
}

DateTime _nextCustomDueDate(DateTime today, _CustomRule rule) {
  for (int step = 0; step < 5000; step++) {
    final candidate = _customDueAtStep(rule, step);
    if (!candidate.isBefore(today)) {
      return candidate;
    }
  }
  throw StateError('无法计算下一次 custom 任务日期');
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
      final rule = _readCustomRule(
        finalDateValue: finalDateValue,
        legacyDateSign: dateSign,
        ruleParams: ruleParams,
      );
      return formatter.format(_nextCustomDueDate(today, rule));

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
          offsetDays < 0) {
        throw const FormatException('monthAfterDay 参数无效');
      }
      return formatter.format(_nextMonthAfterDay(today, anchorDay, offsetDays));
  }
}

List<DateTime> getScheduleDatesInRange({
  required ScheduleItem item,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final DateTime start = normalizeDate(rangeStart);
  final DateTime end = normalizeDate(rangeEnd);

  if (start.isAfter(end)) return [];

  final List<DateTime> result = [];

  // once 单独处理，避免旧日期导致游标回退
  if (item.cycleValue == ScheduleCycle.once) {
    try {
      final String dueDateText = calcNextScheduleDate(
        now: start,
        cycle: item.cycleValue,
        dateSign: item.dateSign,
        finalDateValue: item.finalDate,
        ruleParams: item.ruleParams,
      );
      final DateTime dueDate = normalizeDate(DateTime.parse(dueDateText));
      if (!dueDate.isBefore(start) && !dueDate.isAfter(end)) {
        result.add(dueDate);
      }
    } catch (_) {}
    return result;
  }

  DateTime cursor = start;
  int guard = 0;

  while (!cursor.isAfter(end) && guard < 2000) {
    guard++;

    try {
      final String nextDateText = calcNextScheduleDate(
        now: cursor,
        cycle: item.cycleValue,
        dateSign: item.dateSign,
        finalDateValue: item.finalDate,
        ruleParams: item.ruleParams,
      );

      final DateTime nextDate = normalizeDate(DateTime.parse(nextDateText));

      if (nextDate.isAfter(end)) {
        break;
      }

      // 防御性处理，避免异常规则导致死循环
      if (nextDate.isBefore(cursor)) {
        cursor = cursor.add(const Duration(days: 1));
        continue;
      }

      result.add(nextDate);
      cursor = nextDate.add(const Duration(days: 1));
    } catch (_) {
      break;
    }
  }

  return result;
}

String _customUnitText(CustomIntervalUnit unit) {
  switch (unit) {
    case CustomIntervalUnit.day:
      return '天';
    case CustomIntervalUnit.week:
      return '周';
    case CustomIntervalUnit.month:
      return '个月';
    case CustomIntervalUnit.quarter:
      return '个季度';
    case CustomIntervalUnit.year:
      return '年';
  }
}

String _formatCustomRuleText({
  required int interval,
  required CustomIntervalUnit unit,
  required int offsetDays,
}) {
  if (offsetDays <= 0) {
    if (interval == 1) {
      switch (unit) {
        case CustomIntervalUnit.day:
          return '每天';
        case CustomIntervalUnit.week:
          return '每周';
        case CustomIntervalUnit.month:
          return '每月';
        case CustomIntervalUnit.quarter:
          return '每季度';
        case CustomIntervalUnit.year:
          return '每年';
      }
    }
    return '每$interval${_customUnitText(unit)}';
  }

  return '每$interval${_customUnitText(unit)}后$offsetDays日';
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
      final interval = readRuleInt(item.ruleParams, 'interval');
      final unitStr = readRuleString(item.ruleParams, 'unit');
      final offsetDays = readRuleInt(item.ruleParams, 'offsetDays') ?? 0;

      if (interval != null && interval > 0) {
        return _formatCustomRuleText(
          interval: interval,
          unit: CustomIntervalUnit.fromString(unitStr),
          offsetDays: offsetDays,
        );
      }

      // 兼容旧数据
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

      if (anchorDay == null || offsetDays == null) {
        return '每月?日之后第?天';
      }

      if (offsetDays == 0) {
        return '每月$anchorDay日';
      }

      return '每月$anchorDay日后$offsetDays天';
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
      try {
        final rule = _readCustomRule(
          finalDateValue: item.finalDate,
          legacyDateSign: item.dateSign,
          ruleParams: item.ruleParams,
        );

        DateTime? previous;
        for (int step = 0; step < 5000; step++) {
          final candidate = _customDueAtStep(rule, step);

          if (_sameDate(candidate, normalizedCurrent)) {
            return previous;
          }
          if (candidate.isAfter(normalizedCurrent)) {
            return previous;
          }
          previous = candidate;
        }
        return previous;
      } catch (_) {
        return null;
      }

    case ScheduleCycle.month:
      final targetDay = int.tryParse(item.dateSign);
      if (targetDay == null || targetDay < 1) return null;

      final prevMonthBase = DateTime(
        normalizedCurrent.year,
        normalizedCurrent.month - 1,
        1,
      );
      return _safeDate(prevMonthBase.year, prevMonthBase.month, targetDay);

    case ScheduleCycle.year:
      if (item.finalDate == null || item.finalDate!.isEmpty) return null;

      try {
        final parsed = DateTime.parse(item.finalDate!);
        return _safeDate(normalizedCurrent.year - 1, parsed.month, parsed.day);
      } catch (_) {
        return null;
      }

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
