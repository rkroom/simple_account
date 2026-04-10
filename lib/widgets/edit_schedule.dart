import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/entity.dart';
import '../tools/tools.dart';
import 'schedule_form.dart';

class EditScheduleWidget extends StatelessWidget {
  final ScheduleItem item;

  const EditScheduleWidget({super.key, required this.item});

  Future<bool> _onUpdate({
    required BuildContext context,
    required ScheduleCycle cycle,
    required String content,
    DateTime? expectDate,
    int? selectedDay,
    String? dateSign,
    DateTime? createDate,

    // 新增参数，要和 ScheduleForm 的 OnSaveCallback 保持一致
    int? quarterMonthOfQuarter,
    int? quarterDayOfMonth,
    int? quarterDayOfQuarter,
    int? monthAfterAnchorDay,
    int? monthAfterOffsetDays,
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'content': content,
        'round': cycle.name,
        'rule_type': cycle.name,

        // 先清空，再按周期写入
        'datesign': null,
        'finaldate': null,
        'rule_params': null,
      };

      switch (cycle) {
        case ScheduleCycle.week:
        case ScheduleCycle.month:
          if (selectedDay == null) {
            throw '请选择日期';
          }
          updates['datesign'] = selectedDay.toString();
          break;

        case ScheduleCycle.once:
        case ScheduleCycle.year:
          if (expectDate == null) {
            throw '请选择预计日期';
          }
          updates['finaldate'] = DateFormat('yyyy-MM-dd').format(expectDate);
          break;

        case ScheduleCycle.custom:
          if (expectDate == null || dateSign == null || dateSign.isEmpty) {
            throw '请填写起始日期和天数';
          }
          updates['finaldate'] = DateFormat('yyyy-MM-dd').format(expectDate);
          updates['datesign'] = dateSign;
          break;

        case ScheduleCycle.day:
          break;

        case ScheduleCycle.quarterMonthDay:
          if (quarterMonthOfQuarter == null || quarterDayOfMonth == null) {
            throw '请填写季度内月份和日期';
          }
          updates['rule_params'] = jsonEncode({
            'monthOfQuarter': quarterMonthOfQuarter,
            'dayOfMonth': quarterDayOfMonth,
          });
          break;

        case ScheduleCycle.quarterDay:
          if (quarterDayOfQuarter == null || quarterDayOfQuarter <= 0) {
            throw '请填写季度第几天';
          }
          updates['rule_params'] = jsonEncode({
            'dayOfQuarter': quarterDayOfQuarter,
          });
          break;

        case ScheduleCycle.monthAfterDay:
          if (monthAfterAnchorDay == null ||
              monthAfterOffsetDays == null ||
              monthAfterOffsetDays <= 0) {
            throw '请填写每月几号之后和之后第几天';
          }
          updates['rule_params'] = jsonEncode({
            'anchorDay': monthAfterAnchorDay,
            'offsetDays': monthAfterOffsetDays,
          });
          break;
      }

      await DB().updateScheduleDetails(item.id, updates);

      if (!context.mounted) return false;

      showNoticeSnackBar(context, '日程已更新！');
      Navigator.of(context).pop(true);
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      showNoticeSnackBar(context, '更新失败: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScheduleForm(
      appBarTitle: '编辑日程',
      submitButtonText: '更新',
      initialItem: item,
      onSave: _onUpdate,
    );
  }
}
