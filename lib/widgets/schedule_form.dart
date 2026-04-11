import 'package:flutter/material.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';
import 'package:intl/intl.dart';

import '../tools/config_enum.dart';
import '../tools/entity.dart';
import '../tools/schedule_rule_helper.dart';

typedef OnSaveCallback =
    Future<bool> Function({
      required BuildContext context,
      required ScheduleCycle cycle,
      required String content,
      DateTime? createDate,
      DateTime? expectDate,
      int? selectedDay,

      int? quarterMonthOfQuarter,
      int? quarterDayOfMonth,
      int? quarterDayOfQuarter,
      int? monthAfterAnchorDay,
      int? monthAfterOffsetDays,

      int? customInterval,
      CustomIntervalUnit? customUnit,
      int? customOffsetDays,
    });

class ScheduleForm extends StatefulWidget {
  final String appBarTitle;
  final String submitButtonText;
  final ScheduleItem? initialItem;
  final OnSaveCallback onSave;

  const ScheduleForm({
    super.key,
    required this.appBarTitle,
    required this.submitButtonText,
    required this.onSave,
    this.initialItem,
  });

  @override
  State<ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<ScheduleForm> {
  static const String _dateTimeFormat = 'yyyy-MM-dd HH:mm';
  static const String _dateFormat = 'yyyy-MM-dd';

  final _formKey = GlobalKey<FormState>();

  late DateTime _createDate;
  late ScheduleCycle? _selectedRound;
  late int? _selectedDay;
  late DateTime? _expectDate;

  late TextEditingController _projectController;
  late TextEditingController _createDateController;
  late TextEditingController _expectDateController;

  late int? _quarterMonthOfQuarter;
  late int? _quarterDayOfMonth;
  late TextEditingController _quarterDayOfQuarterController;
  late int? _monthAfterAnchorDay;
  late TextEditingController _monthAfterOffsetController;

  late TextEditingController _customIntervalController;
  late TextEditingController _customOffsetDaysController;
  late CustomIntervalUnit _customUnit;

  bool _showRoundDays = false;
  bool _showExpectDate = false;
  bool _showCustomRuleFields = false;

  bool _showQuarterMonthDayFields = false;
  bool _showQuarterDayFields = false;
  bool _showMonthAfterDayFields = false;

  String _expectDateLabel = "预计日期";
  List<int> _daysOptions = [];

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    final item = widget.initialItem;

    _createDate = item != null ? DateTime.parse(item.created) : DateTime.now();
    _projectController = TextEditingController(text: item?.content ?? '');
    _selectedRound = item?.cycleValue;
    _selectedDay = null;
    _expectDate = null;

    _quarterMonthOfQuarter = null;
    _quarterDayOfMonth = null;
    _monthAfterAnchorDay = null;

    _customUnit = CustomIntervalUnit.day;

    String initialQuarterDayOfQuarter = '';
    String initialMonthAfterOffset = '';
    String initialCustomInterval = '';
    String initialCustomOffsetDays = '';

    if (item != null) {
      switch (item.cycleValue) {
        case ScheduleCycle.week:
        case ScheduleCycle.month:
          if (item.dateSign.isNotEmpty) {
            _selectedDay = int.tryParse(item.dateSign);
          }
          break;

        case ScheduleCycle.custom:
          if (item.finalDate != null && item.finalDate!.isNotEmpty) {
            _expectDate = DateTime.tryParse(item.finalDate!);
          }

          final interval = readRuleInt(item.ruleParams, 'interval');
          final unitStr = readRuleString(item.ruleParams, 'unit');
          final offsetDays = readRuleInt(item.ruleParams, 'offsetDays');

          if (interval != null && interval > 0) {
            initialCustomInterval = interval.toString();
            _customUnit = CustomIntervalUnit.fromString(unitStr);
            if (offsetDays != null && offsetDays > 0) {
              initialCustomOffsetDays = offsetDays.toString();
            }
          } else {
            // 兼容旧数据：custom = 起始日期 + 每 N 天
            final legacyDays = int.tryParse(item.dateSign);
            if (legacyDays != null && legacyDays > 0) {
              initialCustomInterval = legacyDays.toString();
              _customUnit = CustomIntervalUnit.day;
            }
          }
          break;

        case ScheduleCycle.year:
        case ScheduleCycle.once:
          if (item.finalDate != null && item.finalDate!.isNotEmpty) {
            _expectDate = DateTime.tryParse(item.finalDate!);
          }
          break;

        case ScheduleCycle.quarterMonthDay:
          _quarterMonthOfQuarter = readRuleInt(
            item.ruleParams,
            'monthOfQuarter',
          );
          _quarterDayOfMonth = readRuleInt(item.ruleParams, 'dayOfMonth');
          break;

        case ScheduleCycle.quarterDay:
          final qd = readRuleInt(item.ruleParams, 'dayOfQuarter');
          initialQuarterDayOfQuarter = qd?.toString() ?? '';
          break;

        case ScheduleCycle.monthAfterDay:
          _monthAfterAnchorDay = readRuleInt(item.ruleParams, 'anchorDay');
          final od = readRuleInt(item.ruleParams, 'offsetDays');
          initialMonthAfterOffset = od?.toString() ?? '';
          break;

        case ScheduleCycle.day:
          break;
      }
    }

    _quarterDayOfQuarterController = TextEditingController(
      text: initialQuarterDayOfQuarter,
    );
    _monthAfterOffsetController = TextEditingController(
      text: initialMonthAfterOffset,
    );

    _customIntervalController = TextEditingController(
      text: initialCustomInterval,
    );
    _customOffsetDaysController = TextEditingController(
      text: initialCustomOffsetDays,
    );

    _createDateController = TextEditingController(
      text: DateFormat(_dateTimeFormat).format(_createDate),
    );
    _expectDateController = TextEditingController(
      text:
          _expectDate == null
              ? ''
              : DateFormat(_dateFormat).format(_expectDate!),
    );

    if (_selectedRound != null) {
      _updateFormUI(_selectedRound);
    }
  }

  @override
  void dispose() {
    _projectController.dispose();
    _createDateController.dispose();
    _expectDateController.dispose();
    _quarterDayOfQuarterController.dispose();
    _monthAfterOffsetController.dispose();
    _customIntervalController.dispose();
    _customOffsetDaysController.dispose();
    super.dispose();
  }

  void _onRoundChanged(ScheduleCycle? newValue) {
    if (newValue == null) return;
    setState(() {
      _selectedRound = newValue;
      _selectedDay = null;
      _expectDate = null;

      _quarterMonthOfQuarter = null;
      _quarterDayOfMonth = null;
      _monthAfterAnchorDay = null;

      _customUnit = CustomIntervalUnit.day;

      _expectDateController.clear();
      _quarterDayOfQuarterController.clear();
      _monthAfterOffsetController.clear();
      _customIntervalController.clear();
      _customOffsetDaysController.clear();

      _updateFormUI(newValue);
    });
  }

  void _updateFormUI(ScheduleCycle? cycle) {
    _expectDateLabel = (cycle == ScheduleCycle.custom) ? "起始日期（周期起点）" : "预计日期";
    _daysOptions = [];

    _showRoundDays =
        cycle == ScheduleCycle.week || cycle == ScheduleCycle.month;
    _showExpectDate =
        cycle == ScheduleCycle.year ||
        cycle == ScheduleCycle.once ||
        cycle == ScheduleCycle.custom;
    _showCustomRuleFields = cycle == ScheduleCycle.custom;

    _showQuarterMonthDayFields = cycle == ScheduleCycle.quarterMonthDay;
    _showQuarterDayFields = cycle == ScheduleCycle.quarterDay;
    _showMonthAfterDayFields = cycle == ScheduleCycle.monthAfterDay;

    if (cycle == ScheduleCycle.week) {
      _daysOptions = List.generate(7, (i) => i + 1);
    }
    if (cycle == ScheduleCycle.month) {
      _daysOptions = List.generate(31, (i) => i + 1);
    }
  }

  Future<void> _selectDate({
    required BuildContext context,
    required DateTime initialDate,
    required Function(DateTime) onConfirm,
    bool showTime = false,
  }) {
    if (showTime) {
      return DatePicker.showDateTimePicker(
        context,
        showTitleActions: true,
        onConfirm: onConfirm,
        currentTime: initialDate,
        locale: LocaleType.zh,
      );
    } else {
      return DatePicker.showDatePicker(
        context,
        showTitleActions: true,
        onConfirm: onConfirm,
        currentTime: initialDate,
        locale: LocaleType.zh,
      );
    }
  }

  void _showStartDateHelpDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('什么是起始日期？'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('起始日期是这条自定义周期规则的基准日，后续所有周期都会从这一天开始往后推算。'),
                SizedBox(height: 16),
                Text('示例：', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('1. 起始日期：1970-01-01，规则：每5天'),
                Text('   结果：1970-01-01、1970-01-06、1970-01-11'),
                SizedBox(height: 8),
                Text('2. 起始日期：1970-01-01，规则：每2周'),
                Text('   结果：1970-01-01、1970-01-15、1970-01-29'),
                SizedBox(height: 8),
                Text('3. 起始日期：1970-01-01，规则：每1月后5日'),
                Text('   结果：1970-01-06、1970-02-06、1970-03-06'),
                SizedBox(height: 16),
                Text('注意：起始日期不是创建日期，而是周期计算的起点。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final bool success = await widget.onSave(
        context: context,
        cycle: _selectedRound!,
        content: _projectController.text,
        createDate: _createDate,
        expectDate: _expectDate,
        selectedDay: _selectedDay,
        quarterMonthOfQuarter: _quarterMonthOfQuarter,
        quarterDayOfMonth: _quarterDayOfMonth,
        quarterDayOfQuarter: int.tryParse(_quarterDayOfQuarterController.text),
        monthAfterAnchorDay: _monthAfterAnchorDay,
        monthAfterOffsetDays: int.tryParse(_monthAfterOffsetController.text),
        customInterval: int.tryParse(_customIntervalController.text),
        customUnit: _customUnit,
        customOffsetDays:
            _customOffsetDaysController.text.trim().isEmpty
                ? 0
                : int.tryParse(_customOffsetDaysController.text),
      );

      if (success && mounted) {
        setState(() {
          _projectController.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthDays = List.generate(31, (i) => i + 1);

    return Scaffold(
      appBar: AppBar(title: Text(widget.appBarTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: <Widget>[
            TextFormField(
              controller: _createDateController,
              decoration: const InputDecoration(
                labelText: '创建日期',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              readOnly: true,
              onTap:
                  widget.initialItem == null
                      ? () {
                        _selectDate(
                          context: context,
                          initialDate: _createDate,
                          showTime: true,
                          onConfirm: (date) {
                            setState(() {
                              _createDate = date;
                              _createDateController.text = DateFormat(
                                _dateTimeFormat,
                              ).format(date);
                            });
                          },
                        );
                      }
                      : null,
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<ScheduleCycle>(
              initialValue: _selectedRound,
              decoration: const InputDecoration(
                labelText: '周期',
                border: OutlineInputBorder(),
              ),
              hint: const Text('请选择周期'),
              items:
                  ScheduleCycle.values.map((cycle) {
                    return DropdownMenuItem<ScheduleCycle>(
                      value: cycle,
                      child: Text(cycle.label),
                    );
                  }).toList(),
              onChanged: _onRoundChanged,
              validator: (value) => value == null ? '请选择一个周期' : null,
            ),
            const SizedBox(height: 16),

            if (_showRoundDays)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedDay,
                  decoration: const InputDecoration(
                    labelText: '日期',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('请选择日期'),
                  items:
                      _daysOptions.map((day) {
                        final String text =
                            _selectedRound == ScheduleCycle.week
                                ? const {
                                  1: '周一',
                                  2: '周二',
                                  3: '周三',
                                  4: '周四',
                                  5: '周五',
                                  6: '周六',
                                  7: '周日',
                                }[day]!
                                : day.toString();

                        return DropdownMenuItem<int>(
                          value: day,
                          child: Text(text),
                        );
                      }).toList(),
                  onChanged: (value) => setState(() => _selectedDay = value),
                  validator: (value) => value == null ? '请选择一个日期' : null,
                ),
              ),

            if (_showExpectDate)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: TextFormField(
                  controller: _expectDateController,
                  decoration: InputDecoration(
                    labelText: _expectDateLabel,
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedRound == ScheduleCycle.custom)
                          IconButton(
                            tooltip: '查看说明',
                            icon: const Icon(Icons.help_outline),
                            onPressed: _showStartDateHelpDialog,
                          ),
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(Icons.calendar_today),
                        ),
                      ],
                    ),
                  ),
                  readOnly: true,
                  onTap: () {
                    _selectDate(
                      context: context,
                      initialDate: _expectDate ?? DateTime.now(),
                      onConfirm: (date) {
                        setState(() {
                          _expectDate = date;
                          _expectDateController.text = DateFormat(
                            _dateFormat,
                          ).format(date);
                        });
                      },
                    );
                  },
                  validator:
                      (value) =>
                          value == null || value.isEmpty ? '请选择一个日期' : null,
                ),
              ),

            if (_showCustomRuleFields) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _customIntervalController,
                        decoration: const InputDecoration(
                          labelText: '每',
                          hintText: '间隔值',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入间隔值';
                          }
                          final v = int.tryParse(value);
                          if (v == null || v <= 0) {
                            return '请输入大于 0 的整数';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<CustomIntervalUnit>(
                        initialValue: _customUnit,
                        decoration: const InputDecoration(
                          labelText: '单位',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            CustomIntervalUnit.values.map((unit) {
                              return DropdownMenuItem<CustomIntervalUnit>(
                                value: unit,
                                child: Text(unit.label),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _customUnit = value;
                          });
                        },
                        validator: (value) => value == null ? '请选择单位' : null,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: TextFormField(
                  controller: _customOffsetDaysController,
                  decoration: const InputDecoration(
                    labelText: '延迟天数（可选）',
                    hintText: '默认 0，例如 3 表示“延迟 3 日”',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final v = int.tryParse(value);
                    if (v == null || v < 0) {
                      return '请输入大于等于 0 的整数';
                    }
                    return null;
                  },
                ),
              ),
            ],

            if (_showQuarterMonthDayFields) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: DropdownButtonFormField<int>(
                  initialValue: _quarterMonthOfQuarter,
                  decoration: const InputDecoration(
                    labelText: '季度内月份',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('第1个月')),
                    DropdownMenuItem(value: 2, child: Text('第2个月')),
                    DropdownMenuItem(value: 3, child: Text('第3个月')),
                  ],
                  onChanged:
                      (value) => setState(() => _quarterMonthOfQuarter = value),
                  validator: (value) => value == null ? '请选择季度内月份' : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: DropdownButtonFormField<int>(
                  initialValue: _quarterDayOfMonth,
                  decoration: const InputDecoration(
                    labelText: '该月内日期',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      monthDays.map((day) {
                        return DropdownMenuItem(
                          value: day,
                          child: Text(day.toString()),
                        );
                      }).toList(),
                  onChanged:
                      (value) => setState(() => _quarterDayOfMonth = value),
                  validator: (value) => value == null ? '请选择日期' : null,
                ),
              ),
            ],

            if (_showQuarterDayFields)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: TextFormField(
                  controller: _quarterDayOfQuarterController,
                  decoration: const InputDecoration(
                    labelText: '季度内日期',
                    hintText: '请输入 1~92',
                    helperText: '该季度自首日起算的第几天',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入季度内日期';
                    final v = int.tryParse(value);
                    if (v == null || v <= 0 || v > 92) {
                      return '请输入 1~92 的整数';
                    }
                    return null;
                  },
                ),
              ),

            if (_showMonthAfterDayFields) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: DropdownButtonFormField<int>(
                  initialValue: _monthAfterAnchorDay,
                  decoration: const InputDecoration(
                    labelText: '月内基准日期',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      monthDays.map((day) {
                        return DropdownMenuItem(
                          value: day,
                          child: Text(day.toString()),
                        );
                      }).toList(),
                  onChanged:
                      (value) => setState(() => _monthAfterAnchorDay = value),
                  validator: (value) => value == null ? '请选择基准日期' : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: TextFormField(
                  controller: _monthAfterOffsetController,
                  decoration: const InputDecoration(
                    labelText: '顺延天数',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入天数';
                    final v = int.tryParse(value);
                    if (v == null || v < 0) {
                      return '请输入大于等于 0 的整数';
                    }
                    return null;
                  },
                ),
              ),
            ],

            TextFormField(
              controller: _projectController,
              decoration: const InputDecoration(
                labelText: '计划',
                border: OutlineInputBorder(),
                hintText: '请输入内容',
              ),
              maxLines: 3,
              validator:
                  (value) => value == null || value.isEmpty ? '请输入计划内容' : null,
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
              child: Text(widget.submitButtonText),
            ),
          ],
        ),
      ),
    );
  }
}
