import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';

import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/tools.dart';

class Transactions extends StatefulWidget {
  final String? amount;
  final Transaction flow;
  final List accountNames;
  final Map accountIndexs;
  final List<int>? selectedCategory;
  final Map categoryIndex;
  final List categories;
  final DateTime time;
  final String accountText;
  final int? accountId;
  final String categoryText;
  final int? categoryId;
  final void Function(bool success)? addSuccess;
  final void Function(String value)? onAmountChanged;
  final void Function(Map category)? onCategoryConfirm;
  final void Function(Map account)? onAccountConfirm;
  final void Function(DateTime time)? onTimeChanged;

  const Transactions({
    super.key,
    this.amount,
    required this.flow,
    required this.accountNames,
    required this.accountIndexs,
    this.selectedCategory,
    required this.categoryIndex,
    required this.categories,
    required this.time,
    required this.accountText,
    required this.accountId,
    required this.categoryText,
    required this.categoryId,
    this.addSuccess,
    this.onAmountChanged,
    this.onCategoryConfirm,
    this.onAccountConfirm,
    this.onTimeChanged,
  });

  @override
  State<StatefulWidget> createState() {
    return TransactionsState();
  }
}

class TransactionsState extends State<Transactions> {
  static const TextScaler customTextScaler = TextScaler.linear(1.2);

  late TextEditingController _amountController;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _blankFocusNode = FocusNode();
  bool _isSubmitting = false;

  List<int>? selectedCategory;
  late DateTime whenTime;
  late String showAccount;
  late String showCategory;
  int? categoryId;
  int? accountId;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.amount);
    selectedCategory = widget.selectedCategory;
    whenTime = widget.time;
    showAccount = widget.accountText;
    accountId = widget.accountId;
    showCategory = widget.categoryText;
    categoryId = widget.categoryId;
  }

  @override
  void didUpdateWidget(covariant Transactions oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.amount != widget.amount) {
      final newAmount = widget.amount ?? '';
      if (_amountController.text != newAmount) {
        _amountController.text = newAmount;
      }
    }

    if (oldWidget.accountText != widget.accountText) {
      showAccount = widget.accountText;
    }
    if (oldWidget.accountId != widget.accountId) {
      accountId = widget.accountId;
    }
    if (oldWidget.selectedCategory != widget.selectedCategory) {
      selectedCategory = widget.selectedCategory;
    }
    if (oldWidget.categoryText != widget.categoryText) {
      showCategory = widget.categoryText;
    }
    if (oldWidget.categoryId != widget.categoryId) {
      categoryId = widget.categoryId;
    }
    if (oldWidget.time != widget.time) {
      whenTime = widget.time;
    }
  }

  Future<void> _clearTextFieldFocus() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _blankFocusNode.requestFocus();
    await Future.delayed(const Duration(milliseconds: 10));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    _blankFocusNode.dispose();
    super.dispose();
  }

  List<_CategoryGroup> _parseCategoryData(List source) {
    final List<_CategoryGroup> groups = [];

    for (final item in source) {
      if (item is Map && item.isNotEmpty) {
        final entry = item.entries.first;
        final parentName = entry.key.toString();

        final children = <String>[];
        final value = entry.value;

        if (value is List) {
          for (final child in value) {
            children.add(child.toString());
          }
        }

        groups.add(_CategoryGroup(parent: parentName, children: children));
      }
    }

    return groups;
  }

  List<String> _parseAccountData(List source) {
    return source.map((e) => e.toString()).toList();
  }

  Future<void> _openCategorySelector() async {
    await _clearTextFieldFocus();
    if (!mounted) return;

    final groups = _parseCategoryData(widget.categories);

    if (groups.isEmpty) {
      showNoticeSnackBar(context, "暂无类目数据");
      return;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _CategoryCascadeSheet(
            groups: groups,
            selected: selectedCategory,
            categoryIndex: widget.categoryIndex,
          ),
    );

    if (!mounted || result == null) return;

    setState(() {
      selectedCategory = (result["selected"] as List).cast<int>();
      showCategory = result["text"] as String;
      categoryId = result["categoryId"] as int?;
    });

    widget.onCategoryConfirm?.call(result);
  }

  Future<void> _openAccountSelector() async {
    await _clearTextFieldFocus();
    if (!mounted) return;

    final accounts = _parseAccountData(widget.accountNames);

    if (accounts.isEmpty) {
      showNoticeSnackBar(context, "暂无账户数据");
      return;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _AccountGridSheet(
            accounts: accounts,
            selectedText: showAccount,
            accountIndex: widget.accountIndexs,
          ),
    );

    if (!mounted || result == null) return;

    setState(() {
      showAccount = result["text"] as String;
      accountId = result["accountId"] as int?;
    });

    widget.onAccountConfirm?.call(result);
  }

  String _formatTime(DateTime time) {
    return "${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} "
        "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildSelectCell({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: Text("$label$value", textScaler: customTextScaler),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _blankFocusNode,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: Align(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text("金额："),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          inputFormatters: [
                            TextInputFormatter.withFunction((
                              oldValue,
                              newValue,
                            ) {
                              final text = newValue.text;
                              final reg = RegExp(r'^\d*\.?\d{0,2}$');
                              if (text.isEmpty || reg.hasMatch(text)) {
                                return newValue;
                              }
                              return oldValue;
                            }),
                          ],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          controller: _amountController,
                          onChanged: (value) {
                            widget.onAmountChanged?.call(value);
                          },
                        ),
                      ),
                    ],
                  ),
                  _buildSelectCell(
                    label: "类目：",
                    value: showCategory.isEmpty ? "请选择类目" : showCategory,
                    onTap: _openCategorySelector,
                  ),
                  _buildSelectCell(
                    label: "账户：",
                    value: showAccount.isEmpty ? "请选择账户" : showAccount,
                    onTap: _openAccountSelector,
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      await _clearTextFieldFocus();
                      if (!context.mounted) return;

                      DatePicker.showDateTimePicker(
                        context,
                        showTitleActions: true,
                        currentTime: whenTime,
                        locale: LocaleType.zh,
                        onConfirm: (date) {
                          setState(() {
                            whenTime = date;
                          });
                          widget.onTimeChanged?.call(date);
                        },
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 5,
                      ),
                      child: Text(
                        "时间：${_formatTime(whenTime)}",
                        textScaler: customTextScaler,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text("备注："),
                      SizedBox(
                        width: 150,
                        child: TextField(controller: _commentController),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed:
                        _isSubmitting
                            ? null
                            : () async {
                              final amountText = _amountController.text.trim();
                              final amount = double.tryParse(amountText);

                              if (amountText.isEmpty) {
                                showNoticeSnackBar(context, "金额不能为空");
                                widget.addSuccess?.call(false);
                                return;
                              }

                              if (amount == null || amount < 0) {
                                showNoticeSnackBar(context, "请输入正确的金额");
                                widget.addSuccess?.call(false);
                                return;
                              }

                              if (categoryId == null) {
                                showNoticeSnackBar(context, "请选择类目");
                                widget.addSuccess?.call(false);
                                return;
                              }

                              if (accountId == null) {
                                showNoticeSnackBar(context, "请选择账户");
                                widget.addSuccess?.call(false);
                                return;
                              }

                              setState(() {
                                _isSubmitting = true;
                              });

                              try {
                                await DB().addBill(
                                  categoryId!,
                                  widget.flow.value,
                                  amountText,
                                  accountId!,
                                  _commentController.text,
                                  whenTime.toString(),
                                );

                                if (!mounted) return;

                                _amountController.clear();
                                _commentController.clear();
                                widget.onAmountChanged?.call('');
                                widget.addSuccess?.call(true);
                              } catch (error) {
                                if (!context.mounted) return;

                                debugPrint(error.toString());
                                showNoticeSnackBar(context, "添加失败，请检查输入");
                                widget.addSuccess?.call(false);
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isSubmitting = false;
                                  });
                                }
                              }
                            },
                    child:
                        _isSubmitting ? const Text("添加中...") : const Text("添加"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGroup {
  final String parent;
  final List<String> children;

  const _CategoryGroup({required this.parent, required this.children});
}

class _CategoryCascadeSheet extends StatefulWidget {
  final List<_CategoryGroup> groups;
  final List<int>? selected;
  final Map categoryIndex;

  const _CategoryCascadeSheet({
    required this.groups,
    required this.selected,
    required this.categoryIndex,
  });

  @override
  State<_CategoryCascadeSheet> createState() => _CategoryCascadeSheetState();
}

class _CategoryCascadeSheetState extends State<_CategoryCascadeSheet> {
  static const Duration _heightAnimDuration = Duration(milliseconds: 220);
  static const Curve _heightAnimCurve = Curves.easeOut;

  static const int _crossAxisCount = 3;
  static const double _mainAxisSpacing = 12;
  static const double _crossAxisSpacing = 12;
  static const double _childAspectRatio = 2.4;

  static const double _horizontalPadding = 16;
  static const double _parentTopPadding = 16;
  static const double _parentBottomPadding = 8;
  static const double _childVerticalPadding = 16;

  static const double _headerHeight = 58;
  static const double _dividerHeight = 1;
  static const double _sheetMaxHeightRatio = 0.75;

  static const double _maxParentWhenOverflowRatio = 0.38;
  static const double _minVisibleSectionHeight = 96;

  late int parentIndex;
  late int childIndex;

  @override
  void initState() {
    super.initState();

    parentIndex = 0;
    childIndex = 0;

    if (widget.selected != null && widget.selected!.length >= 2) {
      final p = widget.selected![0];
      final c = widget.selected![1];

      if (p >= 0 && p < widget.groups.length) {
        parentIndex = p;
        if (c >= 0 && c < widget.groups[parentIndex].children.length) {
          childIndex = c;
        }
      }
    }
  }

  List<String> get currentChildren => widget.groups[parentIndex].children;

  void _confirmCurrentChild() {
    if (currentChildren.isEmpty) return;
    final child = currentChildren[childIndex];
    Navigator.pop(context, {
      "selected": [parentIndex, childIndex],
      "text": "${widget.groups[parentIndex].parent} / $child",
      "categoryId": widget.categoryIndex[child],
    });
  }

  void _confirmChildSelection(int index) {
    if (index < 0 || index >= currentChildren.length) return;
    childIndex = index;
    _confirmCurrentChild();
  }

  double _calculateGridHeight({
    required double availableWidth,
    required int itemCount,
  }) {
    if (itemCount <= 0) return 0;

    final rowCount = (itemCount + _crossAxisCount - 1) ~/ _crossAxisCount;
    final itemWidth =
        (availableWidth - (_crossAxisCount - 1) * _crossAxisSpacing) /
        _crossAxisCount;
    final itemHeight = itemWidth / _childAspectRatio;

    return rowCount * itemHeight + (rowCount - 1) * _mainAxisSpacing;
  }

  _CategorySheetLayout _measureLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height * _sheetMaxHeightRatio;
    final gridWidth = media.size.width - (_horizontalPadding * 2);

    final parentGridHeight = _calculateGridHeight(
      availableWidth: gridWidth,
      itemCount: widget.groups.length,
    );

    final childGridHeight =
        currentChildren.isEmpty
            ? 28
            : _calculateGridHeight(
              availableWidth: gridWidth,
              itemCount: currentChildren.length,
            );

    final parentDesiredHeight =
        _parentTopPadding + parentGridHeight + _parentBottomPadding;

    final childDesiredHeight =
        _childVerticalPadding + childGridHeight + _childVerticalPadding;

    final baseHeight =
        _headerHeight +
        _dividerHeight +
        _dividerHeight +
        MediaQuery.of(context).padding.bottom;

    final desiredSheetHeight =
        baseHeight + parentDesiredHeight + childDesiredHeight;

    if (desiredSheetHeight <= maxSheetHeight) {
      return _CategorySheetLayout(
        sheetHeight: desiredSheetHeight,
        parentHeight: parentDesiredHeight,
        childHeight: childDesiredHeight,
        parentScrollable: false,
        childScrollable: false,
      );
    }

    final sheetHeight = maxSheetHeight;
    final contentHeight = sheetHeight - baseHeight;

    double parentHeight =
        math
            .min(parentDesiredHeight, sheetHeight * _maxParentWhenOverflowRatio)
            .toDouble();

    double childHeight = math.max(0.0, contentHeight - parentHeight);

    if (childHeight < _minVisibleSectionHeight) {
      final lack = _minVisibleSectionHeight - childHeight;
      parentHeight = math.max(0.0, parentHeight - lack);
      childHeight = math.max(0.0, contentHeight - parentHeight);
    }

    return _CategorySheetLayout(
      sheetHeight: sheetHeight,
      parentHeight: parentHeight,
      childHeight: childHeight,
      parentScrollable: parentDesiredHeight > parentHeight + 0.5,
      childScrollable: childDesiredHeight > childHeight + 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = _measureLayout(context);

    return AnimatedContainer(
      duration: _heightAnimDuration,
      curve: _heightAnimCurve,
      height: layout.sheetHeight,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: _headerHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("取消"),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          "选择类目",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          currentChildren.isEmpty ? null : _confirmCurrentChild,
                      child: const Text("确认"),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: _dividerHeight, thickness: _dividerHeight),
            AnimatedContainer(
              duration: _heightAnimDuration,
              curve: _heightAnimCurve,
              height: layout.parentHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  _horizontalPadding,
                  _parentTopPadding,
                  _horizontalPadding,
                  _parentBottomPadding,
                ),
                child: GridView.builder(
                  shrinkWrap: !layout.parentScrollable,
                  physics:
                      layout.parentScrollable
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                  itemCount: widget.groups.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _crossAxisCount,
                    mainAxisSpacing: _mainAxisSpacing,
                    crossAxisSpacing: _crossAxisSpacing,
                    childAspectRatio: _childAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    final isSelected = index == parentIndex;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          parentIndex = index;
                          childIndex = 0;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              isSelected ? Colors.blue : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                isSelected ? Colors.blue : Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          widget.groups[index].parent,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(height: 1, color: Colors.grey.shade300),
            ),
            AnimatedContainer(
              duration: _heightAnimDuration,
              curve: _heightAnimCurve,
              height: layout.childHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  _horizontalPadding,
                  _childVerticalPadding,
                  _horizontalPadding,
                  _childVerticalPadding,
                ),
                child:
                    currentChildren.isEmpty
                        ? const Center(child: Text("暂无子类目"))
                        : GridView.builder(
                          shrinkWrap: !layout.childScrollable,
                          physics:
                              layout.childScrollable
                                  ? const BouncingScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                          itemCount: currentChildren.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _crossAxisCount,
                                mainAxisSpacing: _mainAxisSpacing,
                                crossAxisSpacing: _crossAxisSpacing,
                                childAspectRatio: _childAspectRatio,
                              ),
                          itemBuilder: (context, index) {
                            final isSelected = index == childIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  childIndex = index;
                                });
                                _confirmChildSelection(index);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color:
                                      isSelected
                                          ? Colors.blue
                                          : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? Colors.blue
                                            : Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  currentChildren[index],
                                  style: TextStyle(
                                    color:
                                        isSelected
                                            ? Colors.white
                                            : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySheetLayout {
  final double sheetHeight;
  final double parentHeight;
  final double childHeight;
  final bool parentScrollable;
  final bool childScrollable;

  const _CategorySheetLayout({
    required this.sheetHeight,
    required this.parentHeight,
    required this.childHeight,
    required this.parentScrollable,
    required this.childScrollable,
  });
}

class _AccountGridSheet extends StatefulWidget {
  final List<String> accounts;
  final String? selectedText;
  final Map accountIndex;

  const _AccountGridSheet({
    required this.accounts,
    required this.selectedText,
    required this.accountIndex,
  });

  @override
  State<_AccountGridSheet> createState() => _AccountGridSheetState();
}

class _AccountGridSheetState extends State<_AccountGridSheet> {
  static const Duration _heightAnimDuration = Duration(milliseconds: 220);
  static const Curve _heightAnimCurve = Curves.easeOut;

  static const int _crossAxisCount = 3;
  static const double _mainAxisSpacing = 12;
  static const double _crossAxisSpacing = 12;
  static const double _childAspectRatio = 2.4;

  static const double _horizontalPadding = 16;
  static const double _verticalPadding = 16;

  static const double _headerHeight = 58;
  static const double _dividerHeight = 1;
  static const double _sheetMaxHeightRatio = 0.70;

  late int selectedIndex;

  @override
  void initState() {
    super.initState();
    final index = widget.accounts.indexOf(widget.selectedText ?? '');
    selectedIndex = index >= 0 ? index : 0;
  }

  void _confirmCurrentAccount() {
    if (widget.accounts.isEmpty) return;
    final name = widget.accounts[selectedIndex];
    Navigator.pop(context, {
      "text": name,
      "accountId": widget.accountIndex[name],
    });
  }

  void _confirmAccountSelection(int index) {
    if (index < 0 || index >= widget.accounts.length) return;
    selectedIndex = index;
    _confirmCurrentAccount();
  }

  double _calculateGridHeight({
    required double availableWidth,
    required int itemCount,
  }) {
    if (itemCount <= 0) return 0;

    final rowCount = (itemCount + _crossAxisCount - 1) ~/ _crossAxisCount;
    final itemWidth =
        (availableWidth - (_crossAxisCount - 1) * _crossAxisSpacing) /
        _crossAxisCount;
    final itemHeight = itemWidth / _childAspectRatio;

    return rowCount * itemHeight + (rowCount - 1) * _mainAxisSpacing;
  }

  _AccountSheetLayout _measureLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height * _sheetMaxHeightRatio;
    final gridWidth = media.size.width - (_horizontalPadding * 2);

    final gridHeight = _calculateGridHeight(
      availableWidth: gridWidth,
      itemCount: widget.accounts.length,
    );

    final bodyDesiredHeight = _verticalPadding + gridHeight + _verticalPadding;

    final sheetDesiredHeight =
        _headerHeight +
        _dividerHeight +
        bodyDesiredHeight +
        media.padding.bottom;

    if (sheetDesiredHeight <= maxSheetHeight) {
      return _AccountSheetLayout(
        sheetHeight: sheetDesiredHeight,
        bodyHeight: bodyDesiredHeight,
        gridScrollable: false,
      );
    }

    final sheetHeight = maxSheetHeight;
    final bodyHeight = math.max(
      0.0,
      sheetHeight - _headerHeight - _dividerHeight - media.padding.bottom,
    );

    return _AccountSheetLayout(
      sheetHeight: sheetHeight,
      bodyHeight: bodyHeight,
      gridScrollable: bodyDesiredHeight > bodyHeight + 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = _measureLayout(context);

    return AnimatedContainer(
      duration: _heightAnimDuration,
      curve: _heightAnimCurve,
      height: layout.sheetHeight,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: _headerHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("取消"),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          "选择账户",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          widget.accounts.isEmpty
                              ? null
                              : _confirmCurrentAccount,
                      child: const Text("确认"),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: _dividerHeight, thickness: _dividerHeight),
            AnimatedContainer(
              duration: _heightAnimDuration,
              curve: _heightAnimCurve,
              height: layout.bodyHeight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child:
                    widget.accounts.isEmpty
                        ? const Center(child: Text("暂无账户"))
                        : GridView.builder(
                          shrinkWrap: !layout.gridScrollable,
                          physics:
                              layout.gridScrollable
                                  ? const BouncingScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                          itemCount: widget.accounts.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 2.4,
                              ),
                          itemBuilder: (context, index) {
                            final selected = index == selectedIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedIndex = index;
                                });
                                _confirmAccountSelection(index);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color:
                                      selected
                                          ? Colors.blue
                                          : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        selected
                                            ? Colors.blue
                                            : Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  widget.accounts[index],
                                  style: TextStyle(
                                    color:
                                        selected
                                            ? Colors.white
                                            : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSheetLayout {
  final double sheetHeight;
  final double bodyHeight;
  final bool gridScrollable;

  const _AccountSheetLayout({
    required this.sheetHeight,
    required this.bodyHeight,
    required this.gridScrollable,
  });
}
