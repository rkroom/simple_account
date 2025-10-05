import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';
import 'package:table_calendar/table_calendar.dart';
import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/entity.dart';
import 'edit_schedule.dart';
import '../tools/tools.dart';

class ScheduleCard extends StatelessWidget {
  final ScheduleItem item;
  final VoidCallback onDataRefreshed;

  const ScheduleCard({
    super.key,
    required this.item,
    required this.onDataRefreshed,
  });

  String _formatDate(String dateTimeString) {
    final dt = DateTime.parse(dateTimeString);
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  String _formatCycle(ScheduleItem item) {
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
        try {
          return '每月${int.parse(item.dateSign)}日';
        } catch (e) {
          return '每月${item.dateSign}日';
        }
      case ScheduleCycle.year:
        if (item.finalDate != null && item.finalDate!.isNotEmpty) {
          try {
            final date = DateTime.parse(item.finalDate!);
            return '每年${DateFormat('M月d日', 'zh_CN').format(date)}';
          } catch (e) {
            return '每年';
          }
        }
        return '每年';
      case ScheduleCycle.custom:
        return '每${item.dateSign}天';
      case ScheduleCycle.once:
        return '';
    }
  }

  Future<bool?> _showEditHandleDialog(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final int recordId = record['id'];
    final String initialDateStr = record['handledate'] ?? '';
    final String initialComment = record['comment'] ?? '';
    final formatter = DateFormat('yyyy-MM-dd');

    DateTime selectedDate = DateTime.tryParse(initialDateStr) ?? DateTime.now();
    final dateController = TextEditingController(
      text: formatter.format(selectedDate),
    );
    final commentController = TextEditingController(text: initialComment);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('编辑记录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: '日期',
                  icon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () {
                  DatePicker.showDatePicker(
                    context,
                    showTitleActions: true,
                    onConfirm: (date) {
                      selectedDate = date;
                      dateController.text = formatter.format(selectedDate);
                    },
                    currentTime: selectedDate,
                    locale: LocaleType.zh,
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '请输入备注信息',
                  icon: Icon(Icons.comment_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              child: const Text('保存'),
              onPressed: () async {
                final String newDate = dateController.text;
                final String newComment = commentController.text;
                Navigator.of(dialogContext);
                try {
                  await DB().updateScheduleRecord(
                    recordId,
                    newDate,
                    newComment,
                  );
                  if (context.mounted) {
                    Navigator.of(dialogContext).pop(true);
                    showNoticeSnackBar(context, '记录更新成功!');
                  }
                } catch (e) {
                  if (context.mounted) {
                    showNoticeSnackBar(context, '更新失败: $e');
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showDetailsDialog(BuildContext context) {
    final cycleText = _formatCycle(item);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            return AlertDialog(
              title: Text(item.content),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '当前状态: ',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            _showStatusUpdateDialog(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              item.status.label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline, size: 20),
                      title: Text('创建于: ${_formatDate(item.created)}'),
                    ),
                    if (item.finished != null && item.finished!.isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline, size: 20),
                        title: Text('结束于: ${item.finished}'),
                      ),
                    if (cycleText.isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.repeat_rounded, size: 20),
                        title: Text('周期: $cycleText'),
                      ),
                    _buildMissedTaskWarning(),
                    FutureBuilder(
                      future: DB().getHandleInfo(item.id),
                      builder: (context, AsyncSnapshot<dynamic> snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('读取历史记录出错: ${snapshot.error}'),
                          );
                        }
                        final history = snapshot.data as List?;
                        final handledDates =
                            (history)
                                ?.map(
                                  (e) => DateTime.tryParse(
                                    e['handledate']?.toString() ?? '',
                                  ),
                                )
                                .whereType<DateTime>()
                                .map(
                                  (d) => DateTime.utc(d.year, d.month, d.day),
                                )
                                .toSet() ??
                            {};
                        final nextDate = DateTime.tryParse(item.date);
                        final normalizedNextDate =
                            nextDate != null
                                ? DateTime.utc(
                                  nextDate.year,
                                  nextDate.month,
                                  nextDate.day,
                                )
                                : null;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.cycleValue == ScheduleCycle.day ||
                                item.cycleValue == ScheduleCycle.week)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 8.0,
                                  bottom: 8.0,
                                ),
                                child: TableCalendar(
                                  locale: 'zh_CN',
                                  daysOfWeekHeight: 22.0,
                                  rowHeight: 30.0,
                                  firstDay: DateTime.utc(2010, 1, 1),
                                  lastDay: DateTime.utc(2030, 12, 31),
                                  focusedDay:
                                      normalizedNextDate ?? DateTime.now(),
                                  calendarFormat: CalendarFormat.month,
                                  headerStyle: const HeaderStyle(
                                    titleCentered: true,
                                    formatButtonVisible: false,
                                  ),
                                  calendarBuilders: CalendarBuilders(
                                    dowBuilder: (context, day) {
                                      const dowText = {
                                        1: '一',
                                        2: '二',
                                        3: '三',
                                        4: '四',
                                        5: '五',
                                        6: '六',
                                        7: '日',
                                      };
                                      return Center(
                                        child: Text(
                                          dowText[day.weekday]!,
                                          style: const TextStyle(
                                            fontSize: 12.0,
                                          ),
                                        ),
                                      );
                                    },
                                    defaultBuilder: (context, day, focusedDay) {
                                      final normalizedDay = DateTime.utc(
                                        day.year,
                                        day.month,
                                        day.day,
                                      );
                                      if (handledDates.contains(
                                        normalizedDay,
                                      )) {
                                        return Container(
                                          margin: const EdgeInsets.all(3.0),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade200,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            day.day.toString(),
                                            style: const TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        );
                                      }
                                      if (normalizedDay == normalizedNextDate) {
                                        return Container(
                                          margin: const EdgeInsets.all(3.0),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.yellow.shade400,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            day.day.toString(),
                                            style: const TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        );
                                      }
                                      return null;
                                    },
                                    todayBuilder: (context, day, focusedDay) {
                                      final normalizedDay = DateTime.utc(
                                        day.year,
                                        day.month,
                                        day.day,
                                      );
                                      Color? bgColor;
                                      if (handledDates.contains(
                                        normalizedDay,
                                      )) {
                                        bgColor = Colors.green.shade200;
                                      } else if (normalizedDay ==
                                          normalizedNextDate) {
                                        bgColor = Colors.yellow.shade400;
                                      }

                                      if (bgColor != null) {
                                        return Container(
                                          margin: const EdgeInsets.all(3.0),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: bgColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).primaryColor,
                                              width: 2,
                                            ),
                                          ),
                                          child: Text(
                                            day.day.toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        );
                                      }
                                      return null;
                                    },
                                    outsideBuilder: (context, day, focusedDay) {
                                      final normalizedDay = DateTime.utc(
                                        day.year,
                                        day.month,
                                        day.day,
                                      );
                                      Color? bgColor;
                                      if (handledDates.contains(
                                        normalizedDay,
                                      )) {
                                        bgColor = Colors.green.shade100;
                                      } else if (normalizedDay ==
                                          normalizedNextDate) {
                                        bgColor = Colors.yellow.shade200;
                                      }

                                      if (bgColor != null) {
                                        return Container(
                                          margin: const EdgeInsets.all(3.0),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: bgColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            day.day.toString(),
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        );
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                            if (history == null || history.isEmpty)
                              const SizedBox.shrink()
                            else
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(),
                                  const Text(
                                    '历史记录',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: history.length,
                                    itemBuilder: (context, index) {
                                      final record = history[index];
                                      final String? comment =
                                          record['comment']?.toString();
                                      final bool hasComment =
                                          comment != null && comment.isNotEmpty;
                                      final int recordId = record['id'];

                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 2.0,
                                        ),
                                        child: ListTile(
                                          title: Text(
                                            '日期: ${record['handledate']}',
                                          ),
                                          subtitle:
                                              hasComment
                                                  ? Text('备注: $comment')
                                                  : null,
                                          onLongPress: () async {
                                            final String? action =
                                                await showDialog<String>(
                                                  context: context,
                                                  builder: (
                                                    BuildContext menuContext,
                                                  ) {
                                                    return SimpleDialog(
                                                      title: const Text('选择操作'),
                                                      children: <Widget>[
                                                        SimpleDialogOption(
                                                          onPressed: () {
                                                            Navigator.pop(
                                                              menuContext,
                                                              'edit',
                                                            );
                                                          },
                                                          child: const Text(
                                                            '编辑',
                                                          ),
                                                        ),
                                                        SimpleDialogOption(
                                                          onPressed: () {
                                                            Navigator.pop(
                                                              menuContext,
                                                              'delete',
                                                            );
                                                          },
                                                          child: const Text(
                                                            '删除',
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                            if (!context.mounted) return;
                                            if (action == 'edit') {
                                              final bool? updated =
                                                  await _showEditHandleDialog(
                                                    context,
                                                    record,
                                                  );
                                              if (updated == true) {
                                                dialogSetState(() {}); // 刷新对话框
                                                onDataRefreshed(); // 刷新主屏幕
                                              }
                                            } else if (action == 'delete') {
                                              final bool?
                                              confirmDelete = await showDialog<
                                                bool
                                              >(
                                                context: context,
                                                builder: (
                                                  BuildContext confirmCtx,
                                                ) {
                                                  return AlertDialog(
                                                    title: const Text('确认删除记录'),
                                                    content: Text(
                                                      '您确定要删除这条于 ${record['handledate']} 的记录吗？',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        child: const Text('取消'),
                                                        onPressed:
                                                            () => Navigator.of(
                                                              confirmCtx,
                                                            ).pop(false),
                                                      ),
                                                      TextButton(
                                                        style:
                                                            TextButton.styleFrom(
                                                              foregroundColor:
                                                                  Colors.red,
                                                            ),
                                                        child: const Text('删除'),
                                                        onPressed:
                                                            () => Navigator.of(
                                                              confirmCtx,
                                                            ).pop(true),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                              if (confirmDelete == true) {
                                                try {
                                                  await DB()
                                                      .deleteScheduleRecord(
                                                        recordId,
                                                      );
                                                  if (context.mounted) {
                                                    showNoticeSnackBar(
                                                      context,
                                                      '记录已删除',
                                                    );
                                                    dialogSetState(
                                                      () {},
                                                    ); // 刷新对话框
                                                    onDataRefreshed(); // 刷新主屏幕
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    showNoticeSnackBar(
                                                      context,
                                                      '删除失败: $e',
                                                    );
                                                  }
                                                }
                                              }
                                            }
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('编辑'),
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditScheduleWidget(item: item),
                      ),
                    );
                    if (result == true) {
                      onDataRefreshed();
                    }
                  },
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('删除'),
                  onPressed: () async {
                    final dialogNavigator = Navigator.of(context);
                    final bool? confirmDelete = await showDialog<bool>(
                      context: dialogContext,
                      builder: (BuildContext confirmationDialogContext) {
                        return AlertDialog(
                          title: const Text('确认删除'),
                          content: Text(
                            '您确定要删除以下计划吗？该操作无法撤销！\n【 ${item.content} 】',
                          ),
                          actions: [
                            TextButton(
                              child: const Text('取消'),
                              onPressed:
                                  () => Navigator.of(
                                    confirmationDialogContext,
                                  ).pop(false),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('删除'),
                              onPressed:
                                  () => Navigator.of(
                                    confirmationDialogContext,
                                  ).pop(true),
                            ),
                          ],
                        );
                      },
                    );
                    if (confirmDelete == true) {
                      try {
                        await DB().deleteSchedule(item.id);
                        if (context.mounted) {
                          dialogNavigator.pop();
                          showNoticeSnackBar(context, '计划已删除');
                          onDataRefreshed();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showNoticeSnackBar(context, '删除失败: $e');
                        }
                      }
                    }
                  },
                ),
                TextButton(
                  child: const Text('关闭'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showStatusUpdateDialog(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd');
    DateTime selectedDate =
        item.lastCompletedDate != null
            ? (DateTime.tryParse(item.lastCompletedDate!) ?? DateTime.now())
            : DateTime.now();
    ScheduleStatus selectedStatus = item.status;
    final dateController = TextEditingController(
      text: formatter.format(selectedDate),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('状态'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<ScheduleStatus>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: '状态',
                      icon: Icon(Icons.flag_outlined),
                    ),
                    items:
                        ScheduleStatus.values.map((ScheduleStatus status) {
                          return DropdownMenuItem<ScheduleStatus>(
                            value: status,
                            child: Text(status.label),
                          );
                        }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setDialogState(() {
                          selectedStatus = newValue;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: dateController,
                    decoration: const InputDecoration(
                      labelText: '日期',
                      icon: Icon(Icons.calendar_today),
                    ),
                    readOnly: true,
                    onTap: () {
                      DatePicker.showDatePicker(
                        context,
                        showTitleActions: true,
                        onConfirm: (date) {
                          selectedDate = date;
                          dateController.text = formatter.format(selectedDate);
                        },
                        currentTime: selectedDate,
                        locale: LocaleType.zh,
                      );
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('取消'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton(
                  child: const Text('保存'),
                  onPressed: () async {
                    final String finishedDate = dateController.text;
                    final dialogNavigator = Navigator.of(dialogContext);
                    try {
                      await DB().updateSchedule(
                        selectedStatus.dbValue,
                        finishedDate,
                        item.id,
                      );
                      if (context.mounted) {
                        dialogNavigator.pop();
                        showNoticeSnackBar(context, '更新成功!');
                        onDataRefreshed();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showNoticeSnackBar(context, '更新失败: $e');
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showHandleDialog(BuildContext context) {
    final commentController = TextEditingController();
    final dateController = TextEditingController();
    final formatter = DateFormat('yyyy-MM-dd');
    DateTime selectedDate = DateTime.now();

    dateController.text = formatter.format(selectedDate);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('任务'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: '日期',
                  icon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () {
                  DatePicker.showDatePicker(
                    context,
                    showTitleActions: true,
                    minTime: DateTime(2000),
                    maxTime: DateTime(2101),
                    onConfirm: (date) {
                      selectedDate = date;
                      dateController.text = formatter.format(selectedDate);
                    },
                    currentTime: selectedDate,
                    locale: LocaleType.zh,
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '请输入备注信息',
                  icon: Icon(Icons.comment_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              child: const Text('保存'),
              onPressed: () async {
                final String comment = commentController.text;
                final String finishedDate = dateController.text;
                final dialogNavigator = Navigator.of(dialogContext);
                try {
                  await DB().handleSchedule(item.id, finishedDate, comment);
                  if (context.mounted) {
                    dialogNavigator.pop();
                    showNoticeSnackBar(context, '保存成功!');
                    onDataRefreshed();
                  }
                } catch (e) {
                  if (context.mounted) {
                    showNoticeSnackBar(context, '保存失败: $e');
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  DateTime _subtractMonths(DateTime from, int months) {
    int targetYear = from.year;
    int targetMonth = from.month - months;

    while (targetMonth <= 0) {
      targetMonth += 12;
      targetYear -= 1;
    }
    final lastDayOfTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
    final day =
        from.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : from.day;
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

  DateTime? _getPreviousDueDate(DateTime currentDueDate, ScheduleItem item) {
    if (item.cycleValue == ScheduleCycle.once) return null;

    switch (item.cycleValue) {
      case ScheduleCycle.day:
        return currentDueDate.subtract(const Duration(days: 1));
      case ScheduleCycle.week:
        return currentDueDate.subtract(const Duration(days: 7));

      case ScheduleCycle.custom:
        final days = int.tryParse(item.dateSign);
        if (days == null || days <= 0) return null;
        return currentDueDate.subtract(Duration(days: days));

      case ScheduleCycle.month:
        return _subtractMonths(currentDueDate, 1);

      case ScheduleCycle.year:
        return _subtractMonths(currentDueDate, 12);
      default:
        return null;
    }
  }

  Widget _buildMissedTaskWarning() {
    if (item.status != ScheduleStatus.continuing) {
      return const SizedBox.shrink();
    }

    if (item.cycleValue == ScheduleCycle.once) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<dynamic>(
      future: DB().getHandleInfo(item.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final history = snapshot.data as List<dynamic>;

        final currentDueDate = DateTime.tryParse(item.date);
        if (currentDueDate == null) return const SizedBox.shrink();

        final previousDueDate = _getPreviousDueDate(currentDueDate, item);
        if (previousDueDate == null) return const SizedBox.shrink();

        final previousPreviousDueDate = _getPreviousDueDate(
          previousDueDate,
          item,
        );
        if (previousPreviousDueDate == null) return const SizedBox.shrink();

        final createdDate = DateTime.parse(item.created);
        if (!createdDate.isBefore(previousPreviousDueDate)) {
          return const SizedBox.shrink();
        }

        final normalizedHandledDates =
            history
                .map(
                  (e) => DateTime.tryParse(e['handledate']?.toString() ?? ''),
                )
                .whereType<DateTime>()
                .map((d) => DateTime.utc(d.year, d.month, d.day))
                .toList();

        final normalizedPrevDate = DateTime.utc(
          previousDueDate.year,
          previousDueDate.month,
          previousDueDate.day,
        );
        final normalizedPrevPrevDate = DateTime.utc(
          previousPreviousDueDate.year,
          previousPreviousDueDate.month,
          previousPreviousDueDate.day,
        );

        final bool wasCompletedInPeriod = normalizedHandledDates.any(
          (d) =>
              d.isAfter(normalizedPrevPrevDate) &&
              !d.isAfter(normalizedPrevDate),
        );

        if (!wasCompletedInPeriod) {
          final formatter = DateFormat('yyyy-MM-dd');
          final warningText = '提示: ${formatter.format(previousDueDate)}日任务未完成';
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: Colors.orange.shade800,
            ),
            title: Text(
              warningText,
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      elevation: 2.0,
      child: ListTile(
        title: Text(
          item.content,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 13,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '下次: ${item.date}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (item.lastCompletedDate != null &&
                  item.lastCompletedDate!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 13,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '上次: ${item.lastCompletedDate}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Icon(
                    Icons.repeat_rounded,
                    size: 13,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    item.cycleValue.label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => _showHandleDialog(context),
              child: const Text('任务'),
            ),
            const SizedBox(width: 6),
            if (item.status == ScheduleStatus.finished)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.done),
                tooltip: '详情',
                onPressed: () => _showDetailsDialog(context),
              )
            else if (item.status == ScheduleStatus.giveup)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.help_outline),
                tooltip: '详情',
                onPressed: () => _showDetailsDialog(context),
              )
            else
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _showDetailsDialog(context),
                child: const Text('详情'),
              ),
          ],
        ),
      ),
    );
  }
}
