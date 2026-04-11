import 'package:flutter/material.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';

import '../tools/db.dart';
import '../tools/tools.dart';
import 'selector_sheets.dart';

class StatementFlowQuery {
  static const String consume = 'consume';
  static const String income = 'income';
  static const String transfer = 'transfer';

  const StatementFlowQuery._();
}

class StatementFilterValue {
  final DateTime? startTime;
  final DateTime? endTime;

  /// 查询参数值：consume / income / transfer
  final String? flowQuery;

  final String? categoryId;
  final String? accountId;

  const StatementFilterValue({
    this.startTime,
    this.endTime,
    this.flowQuery,
    this.categoryId,
    this.accountId,
  });

  bool get hasValue =>
      startTime != null ||
      endTime != null ||
      (flowQuery?.isNotEmpty ?? false) ||
      (categoryId?.isNotEmpty ?? false) ||
      (accountId?.isNotEmpty ?? false);
}

/// 可直接嵌入 Dialog 的内容组件
class StatementFilterDialogContent extends StatefulWidget {
  final StatementFilterValue initialValue;

  const StatementFilterDialogContent({super.key, required this.initialValue});

  @override
  State<StatementFilterDialogContent> createState() =>
      _StatementFilterDialogContentState();
}

class _StatementFilterDialogContentState
    extends State<StatementFilterDialogContent> {
  DateTime? _startTime;
  DateTime? _endTime;
  String? _flowQuery;
  String? _categoryId;
  String? _accountId;

  bool _loading = true;

  List<SelectorOption<String?>> _accounts = [];
  List<SelectorGroup<String?>> _categories = [];

  static const List<SelectorOption<String?>> _flowQueryOptions = [
    SelectorOption<String?>(label: '支出', value: StatementFlowQuery.consume),
    SelectorOption<String?>(label: '收入', value: StatementFlowQuery.income),
    SelectorOption<String?>(label: '转账', value: StatementFlowQuery.transfer),
  ];

  @override
  void initState() {
    super.initState();
    _startTime = widget.initialValue.startTime;
    _endTime = widget.initialValue.endTime;
    _flowQuery = widget.initialValue.flowQuery;
    _categoryId = widget.initialValue.categoryId;
    _accountId = widget.initialValue.accountId;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final results = await Future.wait<dynamic>([
      DB().getAccounts(),
      _loadCategoryGroupsByFlow(_flowQuery),
    ]);

    final accountRows = results[0] as List;
    final categories = results[1] as List<SelectorGroup<String?>>;

    final accounts = _buildAccountOptions(accountRows);

    if (!mounted) return;

    setState(() {
      _accounts = accounts;
      _categories = categories;
      _loading = false;
    });

    if (_categoryId != null && !_containsCategoryId(_categoryId)) {
      setState(() {
        _categoryId = null;
      });
    }
  }

  List<SelectorOption<String?>> _buildAccountOptions(List rows) {
    return rows
        .map(
          (row) => SelectorOption<String?>(
            label: row['name']?.toString() ?? '',
            value: row['id']?.toString(),
          ),
        )
        .toList();
  }

  Future<List<SelectorGroup<String?>>> _loadCategoryGroupsByFlow(
    String? flowQuery,
  ) async {
    List rows = [];

    if (flowQuery == null || flowQuery.isEmpty) {
      final List consumeRows = await DB().getCategorys(
        StatementFlowQuery.consume,
      );
      final List incomeRows = await DB().getCategorys(
        StatementFlowQuery.income,
      );
      rows = [...consumeRows, ...incomeRows];
    } else if (flowQuery == StatementFlowQuery.transfer) {
      rows = [];
    } else {
      rows = await DB().getCategorys(flowQuery);
    }

    return _buildCategoryGroups(rows);
  }

  List<SelectorGroup<String?>> _buildCategoryGroups(List rows) {
    final Map<String, List<SelectorOption<String?>>> grouped = {};

    for (final row in rows) {
      final String parent = row['name']?.toString() ?? '';
      final String child = row['specific_category']?.toString() ?? '';
      final String? id = row['id']?.toString();

      if (parent.isEmpty || child.isEmpty) continue;

      grouped.putIfAbsent(parent, () => []);
      grouped[parent]!.add(SelectorOption<String?>(label: child, value: id));
    }

    return grouped.entries
        .map(
          (entry) =>
              SelectorGroup<String?>(label: entry.key, children: entry.value),
        )
        .toList();
  }

  bool _containsCategoryId(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return false;

    for (final group in _categories) {
      for (final child in group.children) {
        if (child.value == categoryId) {
          return true;
        }
      }
    }
    return false;
  }

  List<int>? _findSelectedCategoryIndexes() {
    if (_categoryId == null || _categoryId!.isEmpty) return null;

    for (int i = 0; i < _categories.length; i++) {
      final children = _categories[i].children;
      for (int j = 0; j < children.length; j++) {
        if (children[j].value == _categoryId) {
          return [i, j];
        }
      }
    }
    return null;
  }

  int? _findSelectedFlowQueryIndex() {
    if (_flowQuery == null || _flowQuery!.isEmpty) return null;
    final index = _flowQueryOptions.indexWhere(
      (item) => item.value == _flowQuery,
    );
    return index >= 0 ? index : null;
  }

  int? _findSelectedAccountIndex() {
    final index = _accounts.indexWhere((item) => item.value == _accountId);
    return index >= 0 ? index : null;
  }

  Future<void> _openFlowSelector() async {
    final result = await showGridSelectorSheet<String?>(
      context: context,
      options: _flowQueryOptions,
      title: '选择收支',
      initialSelectedIndex: _findSelectedFlowQueryIndex(),
    );

    if (!mounted || result == null) return;
    if (_flowQuery == result.option.value) return;

    setState(() {
      _loading = true;
    });

    final newFlowQuery = result.option.value;
    final newCategories = await _loadCategoryGroupsByFlow(newFlowQuery);

    if (!mounted) return;

    setState(() {
      _flowQuery = newFlowQuery;
      _categoryId = null;
      _categories = newCategories;
      _loading = false;
    });
  }

  Future<void> _openCategorySelector() async {
    if (_flowQuery == StatementFlowQuery.transfer) {
      showNoticeSnackBar(context, '转账类型无需选择类目');
      return;
    }

    if (_categories.isEmpty) {
      showNoticeSnackBar(context, '暂无类目数据');
      return;
    }

    final result = await showCascadeSelectorSheet<String?>(
      context: context,
      groups: _categories,
      title: '选择类目',
      initialSelected: _findSelectedCategoryIndexes(),
    );

    if (!mounted || result == null) return;

    setState(() {
      _categoryId = result.option.value;
    });
  }

  Future<void> _openAccountSelector() async {
    if (_accounts.isEmpty) {
      showNoticeSnackBar(context, '暂无账户数据');
      return;
    }

    final result = await showGridSelectorSheet<String?>(
      context: context,
      options: _accounts,
      title: '选择账户',
      initialSelectedIndex: _findSelectedAccountIndex(),
    );

    if (!mounted || result == null) return;

    setState(() {
      _accountId = result.option.value;
    });
  }

  Future<void> _clearFlow() async {
    setState(() {
      _loading = true;
    });

    final categories = await _loadCategoryGroupsByFlow(null);

    if (!mounted) return;

    setState(() {
      _flowQuery = null;
      _categoryId = null;
      _categories = categories;
      _loading = false;
    });
  }

  void _clearCategory() {
    setState(() {
      _categoryId = null;
    });
  }

  void _clearAccount() {
    setState(() {
      _accountId = null;
    });
  }

  void _pickStartDate() {
    DatePicker.showDatePicker(
      context,
      showTitleActions: true,
      currentTime: _startTime ?? DateTime.now(),
      locale: LocaleType.zh,
      onConfirm: (date) {
        if (!mounted) return;
        setState(() {
          _startTime = DateTime(date.year, date.month, date.day);
        });
      },
    );
  }

  void _pickEndDate() {
    DatePicker.showDatePicker(
      context,
      showTitleActions: true,
      currentTime: _endTime ?? _startTime ?? DateTime.now(),
      locale: LocaleType.zh,
      onConfirm: (date) {
        if (!mounted) return;
        setState(() {
          _endTime = DateTime(date.year, date.month, date.day, 23, 59, 59);
        });
      },
    );
  }

  void _reset() {
    Navigator.of(context).pop(const StatementFilterValue());
  }

  void _apply() {
    if (_startTime != null &&
        _endTime != null &&
        _startTime!.isAfter(_endTime!)) {
      showNoticeSnackBar(context, '开始时间不能晚于结束时间');
      return;
    }

    Navigator.of(context).pop(
      StatementFilterValue(
        startTime: _startTime,
        endTime: _endTime,
        flowQuery: _flowQuery,
        categoryId: _categoryId,
        accountId: _accountId,
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '未选择';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _flowLabel(String? value) {
    final item = _flowQueryOptions.where((e) => e.value == value).firstOrNull;
    return item?.label ?? '全部';
  }

  String _accountLabel(String? value) {
    if (value == null || value.isEmpty) return '全部';
    final item = _accounts.where((e) => e.value == value).firstOrNull;
    return item?.label ?? '全部';
  }

  String _categoryLabel(String? value) {
    if (value == null || value.isEmpty) return '全部';

    for (final group in _categories) {
      for (final child in group.children) {
        if (child.value == value) {
          return '${group.label} / ${child.label}';
        }
      }
    }
    return '全部';
  }

  Widget _buildSelectorTile({
    required String title,
    required String value,
    required VoidCallback? onTap,
    VoidCallback? onClear,
    bool enabled = true,
    Widget? trailing,
  }) {
    Widget finalTrailing;

    if (trailing != null) {
      finalTrailing = trailing;
    } else {
      finalTrailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.clear),
              tooltip: '清除',
            ),
          Icon(enabled ? Icons.chevron_right : Icons.block, size: 20),
        ],
      );
    }

    return ListTile(
      enabled: enabled,
      title: Text(title),
      subtitle: Text(value),
      trailing: finalTrailing,
      onTap: enabled ? onTap : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryText =
        _flowQuery == StatementFlowQuery.transfer
            ? '转账无需类目'
            : _categoryLabel(_categoryId);

    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.82;

    return Material(
      color: Theme.of(context).dialogTheme.backgroundColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: maxHeight,
          minWidth: mathMin(media.size.width - 32, 320),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '筛选',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            child: Column(
                              children: [
                                _buildSelectorTile(
                                  title: '开始时间',
                                  value: _formatDate(_startTime),
                                  onTap: _pickStartDate,
                                  trailing:
                                      _startTime == null
                                          ? const Icon(Icons.calendar_month)
                                          : IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _startTime = null;
                                              });
                                            },
                                            icon: const Icon(Icons.clear),
                                            tooltip: '清除',
                                          ),
                                ),
                                const Divider(height: 1),
                                _buildSelectorTile(
                                  title: '结束时间',
                                  value: _formatDate(_endTime),
                                  onTap: _pickEndDate,
                                  trailing:
                                      _endTime == null
                                          ? const Icon(Icons.calendar_month)
                                          : IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _endTime = null;
                                              });
                                            },
                                            icon: const Icon(Icons.clear),
                                            tooltip: '清除',
                                          ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Column(
                              children: [
                                _buildSelectorTile(
                                  title: '收支',
                                  value: _flowLabel(_flowQuery),
                                  onTap: _openFlowSelector,
                                  onClear:
                                      _flowQuery != null ? _clearFlow : null,
                                ),
                                const Divider(height: 1),
                                _buildSelectorTile(
                                  title: '类目',
                                  value: categoryText,
                                  enabled:
                                      _flowQuery != StatementFlowQuery.transfer,
                                  onTap:
                                      _flowQuery == StatementFlowQuery.transfer
                                          ? null
                                          : _openCategorySelector,
                                  onClear:
                                      (_flowQuery !=
                                                  StatementFlowQuery.transfer &&
                                              _categoryId != null)
                                          ? _clearCategory
                                          : null,
                                  trailing:
                                      _flowQuery == StatementFlowQuery.transfer
                                          ? const Icon(Icons.block, size: 20)
                                          : null,
                                ),
                                const Divider(height: 1),
                                _buildSelectorTile(
                                  title: '账户',
                                  value: _accountLabel(_accountId),
                                  onTap: _openAccountSelector,
                                  onClear:
                                      _accountId != null ? _clearAccount : null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reset,
                      child: const Text('重置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _apply,
                      child: const Text('应用'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double mathMin(double a, double b) => a < b ? a : b;

extension _IterableFirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
