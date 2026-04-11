import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';

import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/tools.dart';
import 'selector_sheets.dart';

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

  Future<void> _openCategorySelector() async {
    await _clearTextFieldFocus();
    if (!mounted) return;

    final groups = buildCategorySelectorGroups(
      widget.categories,
      widget.categoryIndex,
    );

    if (groups.isEmpty) {
      showNoticeSnackBar(context, "暂无类目数据");
      return;
    }

    final result = await showCascadeSelectorSheet<int?>(
      context: context,
      groups: groups,
      initialSelected: selectedCategory,
      title: "选择类目",
    );

    if (!mounted || result == null) return;

    setState(() {
      selectedCategory = [result.parentIndex, result.childIndex];
      showCategory = result.text;
      categoryId = result.option.value;
    });

    widget.onCategoryConfirm?.call(
      result.toMap(
        selectedKey: "selected",
        textKey: "text",
        valueKey: "categoryId",
      ),
    );
  }

  Future<void> _openAccountSelector() async {
    await _clearTextFieldFocus();
    if (!mounted) return;

    final options = buildAccountSelectorOptions(
      widget.accountNames,
      widget.accountIndexs,
    );

    if (options.isEmpty) {
      showNoticeSnackBar(context, "暂无账户数据");
      return;
    }

    int? initialIndex;
    if (showAccount.isNotEmpty) {
      final idx = options.indexWhere((e) => e.label == showAccount);
      if (idx >= 0) {
        initialIndex = idx;
      }
    }

    final result = await showGridSelectorSheet<int?>(
      context: context,
      options: options,
      title: "选择账户",
      initialSelectedIndex: initialIndex,
    );

    if (!mounted || result == null) return;

    setState(() {
      showAccount = result.option.label;
      accountId = result.option.value;
    });

    widget.onAccountConfirm?.call({
      "text": result.option.label,
      "accountId": result.option.value,
    });
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
