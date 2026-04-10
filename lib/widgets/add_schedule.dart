import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/tools.dart';
import 'schedule_form.dart';

class AddScheduleWidget extends StatelessWidget {
  const AddScheduleWidget({super.key});

  static const String _dateTimeFormat = 'yyyy-MM-dd HH:mm:ss';
  static const String _dateFormat = 'yyyy-MM-dd';

  Future<bool> _onSave({
    required BuildContext context,
    required ScheduleCycle cycle,
    required String content,
    DateTime? createDate,
    DateTime? expectDate,
    int? selectedDay,
    String? dateSign,
    int? quarterMonthOfQuarter,
    int? quarterDayOfMonth,
    int? quarterDayOfQuarter,
    int? monthAfterAnchorDay,
    int? monthAfterOffsetDays,
  }) async {
    try {
      if (createDate == null) {
        throw '创建日期丢失';
      }

      final Map<String, dynamic> scheduleMap = {
        'created': DateFormat(_dateTimeFormat).format(createDate),
        'content': content,
        'round': cycle.name,
        'rule_type': cycle.name,
      };

      switch (cycle) {
        case ScheduleCycle.once:
        case ScheduleCycle.year:
          if (expectDate == null) throw '请选择预计日期';
          scheduleMap['finaldate'] = DateFormat(_dateFormat).format(expectDate);
          break;

        case ScheduleCycle.day:
          break;

        case ScheduleCycle.week:
        case ScheduleCycle.month:
          if (selectedDay == null) throw '请选择日期';
          scheduleMap['datesign'] = selectedDay.toString();
          break;

        case ScheduleCycle.custom:
          if (expectDate == null || dateSign == null || dateSign.isEmpty) {
            throw '请填写起始日期和天数';
          }
          scheduleMap['finaldate'] = DateFormat(_dateFormat).format(expectDate);
          scheduleMap['datesign'] = dateSign;
          break;

        case ScheduleCycle.quarterMonthDay:
          if (quarterMonthOfQuarter == null || quarterDayOfMonth == null) {
            throw '请填写季度内月份和日期';
          }
          scheduleMap['rule_params'] = jsonEncode({
            'monthOfQuarter': quarterMonthOfQuarter,
            'dayOfMonth': quarterDayOfMonth,
          });
          break;

        case ScheduleCycle.quarterDay:
          if (quarterDayOfQuarter == null || quarterDayOfQuarter <= 0) {
            throw '请填写季度第几天';
          }
          scheduleMap['rule_params'] = jsonEncode({
            'dayOfQuarter': quarterDayOfQuarter,
          });
          break;

        case ScheduleCycle.monthAfterDay:
          if (monthAfterAnchorDay == null ||
              monthAfterOffsetDays == null ||
              monthAfterOffsetDays <= 0) {
            throw '请填写每月几号之后和之后第几天';
          }
          scheduleMap['rule_params'] = jsonEncode({
            'anchorDay': monthAfterAnchorDay,
            'offsetDays': monthAfterOffsetDays,
          });
          break;
      }

      await DB().addSchedule(scheduleMap);
      if (!context.mounted) return false;
      showNoticeSnackBar(context, '日程已保存！');
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      showNoticeSnackBar(context, '日程保存失败: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScheduleForm(
      appBarTitle: '创建日程',
      submitButtonText: '保存',
      onSave: _onSave,
    );
  }
}
