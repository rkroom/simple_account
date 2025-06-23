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
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'content': content,
        'round': cycle.name,
        'datesign': null,
        'finaldate': null,
      };

      switch (cycle) {
        case ScheduleCycle.week:
        case ScheduleCycle.month:
          updates['datesign'] = selectedDay.toString();
          break;
        case ScheduleCycle.once:
        case ScheduleCycle.year:
          updates['finaldate'] = DateFormat('yyyy-MM-dd').format(expectDate!);
          break;
        case ScheduleCycle.custom:
          updates['finaldate'] = DateFormat('yyyy-MM-dd').format(expectDate!);
          updates['datesign'] = dateSign;
          break;
        default:
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
