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
      String? dateSign,

      // 新增
      int? quarterMonthOfQuarter,
      int? quarterDayOfMonth,
      int? quarterDayOfQuarter,
      int? monthAfterAnchorDay,
      int? monthAfterOffsetDays,
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
  late TextEditingController _dateSignController;
  late TextEditingController _createDateController;
  late TextEditingController _expectDateController;

  // 新增
  late int? _quarterMonthOfQuarter;
  late int? _quarterDayOfMonth;
  late TextEditingController _quarterDayOfQuarterController;
  late int? _monthAfterAnchorDay;
  late TextEditingController _monthAfterOffsetController;

  bool _showRoundDays = false;
  bool _showExpectDate = false;
  bool _showCustomDays = false;

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

    String initialDateSign = '';
    String initialQuarterDayOfQuarter = '';
    String initialMonthAfterOffset = '';

    if (item != null) {
      switch (item.cycleValue) {
        case ScheduleCycle.week:
        case ScheduleCycle.month:
          if (item.dateSign.isNotEmpty) {
            _selectedDay = int.tryParse(item.dateSign);
          }
          break;

        case ScheduleCycle.custom:
          initialDateSign = item.dateSign;
          if (item.finalDate != null && item.finalDate!.isNotEmpty) {
            _expectDate = DateTime.tryParse(item.finalDate!);
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

    _dateSignController = TextEditingController(text: initialDateSign);
    _quarterDayOfQuarterController = TextEditingController(
      text: initialQuarterDayOfQuarter,
    );
    _monthAfterOffsetController = TextEditingController(
      text: initialMonthAfterOffset,
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
    _dateSignController.dispose();
    _createDateController.dispose();
    _expectDateController.dispose();
    _quarterDayOfQuarterController.dispose();
    _monthAfterOffsetController.dispose();
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

      _dateSignController.clear();
      _expectDateController.clear();
      _quarterDayOfQuarterController.clear();
      _monthAfterOffsetController.clear();

      _updateFormUI(newValue);
    });
  }

  void _updateFormUI(ScheduleCycle? cycle) {
    _expectDateLabel = (cycle == ScheduleCycle.custom) ? "起始日期" : "预计日期";
    _daysOptions = [];

    _showRoundDays =
        cycle == ScheduleCycle.week || cycle == ScheduleCycle.month;
    _showExpectDate =
        cycle == ScheduleCycle.year ||
        cycle == ScheduleCycle.once ||
        cycle == ScheduleCycle.custom;
    _showCustomDays = cycle == ScheduleCycle.custom;

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
        dateSign: _dateSignController.text,
        quarterMonthOfQuarter: _quarterMonthOfQuarter,
        quarterDayOfMonth: _quarterDayOfMonth,
        quarterDayOfQuarter: int.tryParse(_quarterDayOfQuarterController.text),
        monthAfterAnchorDay: _monthAfterAnchorDay,
        monthAfterOffsetDays: int.tryParse(_monthAfterOffsetController.text),
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
                        return DropdownMenuItem<int>(
                          value: day,
                          child: Text(day.toString()),
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
                    suffixIcon: const Icon(Icons.calendar_today),
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

            if (_showCustomDays)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: TextFormField(
                  controller: _dateSignController,
                  decoration: const InputDecoration(
                    labelText: '天数',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入天数';
                    final intValue = int.tryParse(value);
                    if (intValue == null || intValue <= 0) {
                      return '请输入一个有效的天数';
                    }
                    return null;
                  },
                ),
              ),

            if (_showQuarterMonthDayFields) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: DropdownButtonFormField<int>(
                  initialValue: _quarterMonthOfQuarter,
                  decoration: const InputDecoration(
                    labelText: '季度内第几个月',
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
                    labelText: '该月第几号',
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
                    labelText: '季度第几天',
                    hintText: '请输入 1~92',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入季度第几天';
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
                    labelText: '每月几号之后',
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
                    labelText: '之后第几天',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入天数';
                    final v = int.tryParse(value);
                    if (v == null || v <= 0) {
                      return '请输入有效天数';
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
