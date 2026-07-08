import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';

import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/tools.dart';
import 'selector_sheets.dart';

class TransactionFormData {
  final String amount;
  final int categoryId;
  final int accountId;
  final String comment;
  final DateTime whenTime;

  const TransactionFormData({
    required this.amount,
    required this.categoryId,
    required this.accountId,
    required this.comment,
    required this.whenTime,
  });
}

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
  final FutureOr<void> Function(bool success)? addSuccess;
  final void Function(String value)? onAmountChanged;

  /// 备注变化回调，用于父组件保存备注状态，避免表单重建时丢失备注。
  final void Function(String value)? onCommentChanged;
  final void Function(Map category)? onCategoryConfirm;
  final void Function(Map account)? onAccountConfirm;
  final void Function(DateTime time)? onTimeChanged;

  /// 编辑时用于回填备注
  final String initialComment;

  /// 按钮文案，新增时默认“添加”，编辑时可传“保存”
  final String submitButtonText;

  /// 自定义提交逻辑。
  /// 为空时走默认新增逻辑；不为空时由外部接管，例如编辑保存。
  final Future<void> Function(TransactionFormData data)? onSubmit;

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
    this.onCommentChanged,
    this.onCategoryConfirm,
    this.onAccountConfirm,
    this.onTimeChanged,
    this.initialComment = '',
    this.submitButtonText = '添加',
    this.onSubmit,
  });

  @override
  State<StatefulWidget> createState() {
    return TransactionsState();
  }
}

class TransactionsState extends State<Transactions> {
  static const TextScaler customTextScaler = TextScaler.linear(1.2);
  late TextEditingController _amountController;
  late TextEditingController _commentController;
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
    _commentController = TextEditingController(text: widget.initialComment);
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

    if (oldWidget.initialComment != widget.initialComment) {
      final newComment = widget.initialComment;
      if (_commentController.text != newComment) {
        _commentController.text = newComment;
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

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (amountText.isEmpty) {
      showNoticeSnackBar(context, "金额不能为空");
      await widget.addSuccess?.call(false);
      return;
    }

    if (amount == null || amount < 0) {
      showNoticeSnackBar(context, "请输入正确的金额");
      await widget.addSuccess?.call(false);
      return;
    }

    if (categoryId == null) {
      showNoticeSnackBar(context, "请选择类目");
      await widget.addSuccess?.call(false);
      return;
    }

    if (accountId == null) {
      showNoticeSnackBar(context, "请选择账户");
      await widget.addSuccess?.call(false);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final commentText = _commentController.text.trim();

      final payload = TransactionFormData(
        amount: amountText,
        categoryId: categoryId!,
        accountId: accountId!,
        comment: commentText,
        whenTime: whenTime,
      );

      if (widget.onSubmit != null) {
        await widget.onSubmit!(payload);
      } else {
        await DB().addBill(
          categoryId!,
          widget.flow.value,
          amountText,
          accountId!,
          commentText,
          whenTime,
        );

        if (!mounted) return;

        _amountController.clear();
        _commentController.clear();
        widget.onAmountChanged?.call('');
        widget.onCommentChanged?.call('');
      }

      await widget.addSuccess?.call(true);
    } catch (error) {
      if (!mounted) return;

      debugPrint(error.toString());
      showNoticeSnackBar(
        context,
        widget.onSubmit == null ? "添加失败，请检查输入" : "保存失败，请检查输入",
      );
      await widget.addSuccess?.call(false);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
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
                        child: TextField(
                          controller: _commentController,
                          onChanged: (value) {
                            widget.onCommentChanged?.call(value);
                          },
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    child:
                        _isSubmitting
                            ? Text("${widget.submitButtonText}中...")
                            : Text(widget.submitButtonText),
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
