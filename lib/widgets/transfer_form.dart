import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';

import '../tools/tools.dart';

class TransferFormData {
  final String amount;
  final int outAccountId;
  final int inAccountId;
  final String comment;
  final DateTime time;
  final String whenTime;
  final String outAccountText;
  final String inAccountText;

  const TransferFormData({
    required this.amount,
    required this.outAccountId,
    required this.inAccountId,
    required this.comment,
    required this.time,
    required this.whenTime,
    required this.outAccountText,
    required this.inAccountText,
  });
}

class TransferAccountSelection {
  final String outText;
  final int? outId;
  final String inText;
  final int? inId;

  const TransferAccountSelection({
    required this.outText,
    required this.outId,
    required this.inText,
    required this.inId,
  });
}

class TransferForm extends StatefulWidget {
  final List accountNames;
  final Map accountIndexs;

  final DateTime time;

  final String? amount;
  final String initialComment;

  final String outAccountText;
  final int? outAccountId;
  final String inAccountText;
  final int? inAccountId;

  final String submitButtonText;
  final bool clearAfterSubmit;

  final ValueChanged<DateTime>? onTimeChanged;
  final ValueChanged<TransferAccountSelection>? onAccountChanged;

  final Future<void> Function(TransferFormData formData) onSubmit;
  final ValueChanged<bool>? submitSuccess;

  const TransferForm({
    super.key,
    required this.accountNames,
    required this.accountIndexs,
    required this.time,
    required this.onSubmit,
    this.amount,
    this.initialComment = '',
    this.outAccountText = '请选择',
    this.outAccountId,
    this.inAccountText = '请选择',
    this.inAccountId,
    this.submitButtonText = '添加',
    this.clearAfterSubmit = false,
    this.onTimeChanged,
    this.onAccountChanged,
    this.submitSuccess,
  });

  @override
  State<TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<TransferForm> {
  static const TextScaler customTextScaler = TextScaler.linear(1.2);

  late DateTime _whenTime;

  late String _showTransferAccount;
  late int? _transferAccountId;

  late String _showTransferAimAccount;
  late int? _transferAimAccountId;

  late final TextEditingController _amountController;
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();

    _whenTime = widget.time;

    _showTransferAccount = widget.outAccountText;
    _transferAccountId = widget.outAccountId;

    _showTransferAimAccount = widget.inAccountText;
    _transferAimAccountId = widget.inAccountId;

    _amountController = TextEditingController(text: widget.amount ?? '');
    _commentController = TextEditingController(text: widget.initialComment);
  }

  @override
  void didUpdateWidget(covariant TransferForm oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.time != widget.time) {
      _whenTime = widget.time;
    }

    if (oldWidget.outAccountText != widget.outAccountText ||
        oldWidget.outAccountId != widget.outAccountId ||
        oldWidget.inAccountText != widget.inAccountText ||
        oldWidget.inAccountId != widget.inAccountId) {
      _showTransferAccount = widget.outAccountText;
      _transferAccountId = widget.outAccountId;
      _showTransferAimAccount = widget.inAccountText;
      _transferAimAccountId = widget.inAccountId;
    }
  }

  List<String> _parseAccountData(List source) {
    return source.map((e) => e.toString()).toList();
  }

  Future<void> _openTransferAccountSelector() async {
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
          (_) => _TransferAccountSheet(
            accounts: accounts,
            accountIndex: widget.accountIndexs,
            selectedOutText:
                _showTransferAccount == "请选择" ? null : _showTransferAccount,
            selectedInText:
                _showTransferAimAccount == "请选择"
                    ? null
                    : _showTransferAimAccount,
          ),
    );

    if (!mounted || result == null) return;

    final selection = TransferAccountSelection(
      outText: result["outText"] as String,
      outId: result["outId"] as int?,
      inText: result["inText"] as String,
      inId: result["inId"] as int?,
    );

    setState(() {
      _showTransferAccount = selection.outText;
      _transferAccountId = selection.outId;
      _showTransferAimAccount = selection.inText;
      _transferAimAccountId = selection.inId;
    });

    widget.onAccountChanged?.call(selection);
  }

  Future<void> _handleSubmit() async {
    if (_amountController.text.isEmpty) {
      showNoticeSnackBar(context, "金额不能为空");
      return;
    }

    if (_transferAccountId == null) {
      showNoticeSnackBar(context, "请选择转出账户");
      return;
    }

    if (_transferAimAccountId == null) {
      showNoticeSnackBar(context, "请选择转入账户");
      return;
    }

    if (_transferAccountId == _transferAimAccountId) {
      showNoticeSnackBar(context, "转出账户和转入账户不能相同");
      return;
    }

    try {
      await widget.onSubmit(
        TransferFormData(
          amount: _amountController.text,
          outAccountId: _transferAccountId!,
          inAccountId: _transferAimAccountId!,
          comment: _commentController.text,
          time: _whenTime,
          whenTime: _whenTime.toString(),
          outAccountText: _showTransferAccount,
          inAccountText: _showTransferAimAccount,
        ),
      );

      if (!mounted) return;

      if (widget.clearAfterSubmit) {
        _amountController.clear();
        _commentController.clear();
      }

      widget.submitSuccess?.call(true);
    } catch (_) {
      if (!mounted) return;
      showNoticeSnackBar(context, "保存失败，请检查输入");
      widget.submitSuccess?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final text = newValue.text;
                    if (text.isEmpty ||
                        RegExp(r'^\d*\.?\d{0,2}$').hasMatch(text)) {
                      return newValue;
                    }
                    return oldValue;
                  }),
                ],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                controller: _amountController,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(5),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openTransferAccountSelector,
            child: Text(
              "账户：$_showTransferAccount → $_showTransferAimAccount",
              textScaler: customTextScaler,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(5),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              DatePicker.showDateTimePicker(
                context,
                showTitleActions: true,
                onConfirm: (date) {
                  setState(() {
                    _whenTime = date;
                  });
                  widget.onTimeChanged?.call(date);
                },
                currentTime: _whenTime,
                locale: LocaleType.zh,
              );
            },
            child: Text(
              "时间：${_whenTime.year.toString()}-${_whenTime.month.toString().padLeft(2, '0')}-${_whenTime.day.toString().padLeft(2, '0')} ${_whenTime.hour.toString().padLeft(2, '0')}:${_whenTime.minute.toString().padLeft(2, '0')}",
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
          onPressed: _handleSubmit,
          child: Text(widget.submitButtonText),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }
}

class _TransferAccountSheet extends StatefulWidget {
  final List<String> accounts;
  final Map accountIndex;
  final String? selectedOutText;
  final String? selectedInText;

  const _TransferAccountSheet({
    required this.accounts,
    required this.accountIndex,
    this.selectedOutText,
    this.selectedInText,
  });

  @override
  State<_TransferAccountSheet> createState() => _TransferAccountSheetState();
}

class _TransferAccountSheetState extends State<_TransferAccountSheet> {
  static const Duration _heightAnimDuration = Duration(milliseconds: 220);
  static const Curve _heightAnimCurve = Curves.easeOut;

  static const int _crossAxisCount = 3;
  static const double _mainAxisSpacing = 12;
  static const double _crossAxisSpacing = 12;
  static const double _childAspectRatio = 2.4;

  static const double _horizontalPadding = 16;
  static const double _sectionTopPadding = 12;
  static const double _sectionBottomPadding = 16;
  static const double _titleHeight = 22;
  static const double _titleSpacing = 12;

  static const double _headerHeight = 58;
  static const double _dividerHeight = 1;
  static const double _sheetMaxHeightRatio = 0.81;

  int selectedOutIndex = -1;
  int selectedInIndex = -1;

  late final int _initialOutIndex;
  late final int _initialInIndex;

  bool _outTouched = false;
  bool _inTouched = false;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();

    selectedOutIndex =
        widget.selectedOutText == null
            ? -1
            : widget.accounts.indexOf(widget.selectedOutText!);
    selectedInIndex =
        widget.selectedInText == null
            ? -1
            : widget.accounts.indexOf(widget.selectedInText!);

    _initialOutIndex = selectedOutIndex;
    _initialInIndex = selectedInIndex;
  }

  bool get _hasBothSelected => selectedOutIndex >= 0 && selectedInIndex >= 0;

  void _tryAutoConfirm({required bool changedThisTap}) {
    if (!changedThisTap || _isConfirming || !_hasBothSelected) {
      return;
    }

    final changedFromInitial =
        selectedOutIndex != _initialOutIndex ||
        selectedInIndex != _initialInIndex;

    final touchedBothThisSession = _outTouched && _inTouched;

    if (touchedBothThisSession || changedFromInitial) {
      _confirm();
    }
  }

  void _confirm() {
    if (_isConfirming) return;

    if (selectedOutIndex < 0) {
      showSheetTopNotice(context, "请选择转出账户");
      return;
    }

    if (selectedInIndex < 0) {
      showSheetTopNotice(context, "请选择转入账户");
      return;
    }

    if (selectedOutIndex == selectedInIndex) {
      showSheetTopNotice(context, "转出账户和转入账户不能相同");
      return;
    }

    _isConfirming = true;

    final outName = widget.accounts[selectedOutIndex];
    final inName = widget.accounts[selectedInIndex];

    Navigator.pop(context, {
      "outText": outName,
      "outId": widget.accountIndex[outName],
      "inText": inName,
      "inId": widget.accountIndex[inName],
    });
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

  _TransferSheetLayout _measureLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height * _sheetMaxHeightRatio;
    final gridWidth = media.size.width - (_horizontalPadding * 2);

    final gridHeight = _calculateGridHeight(
      availableWidth: gridWidth,
      itemCount: widget.accounts.length,
    );

    final sectionDesiredHeight =
        _sectionTopPadding +
        _titleHeight +
        _titleSpacing +
        gridHeight +
        _sectionBottomPadding;

    final sheetDesiredHeight =
        _headerHeight +
        _dividerHeight +
        sectionDesiredHeight +
        _dividerHeight +
        sectionDesiredHeight +
        media.padding.bottom;

    if (sheetDesiredHeight <= maxSheetHeight) {
      return _TransferSheetLayout(
        sheetHeight: sheetDesiredHeight,
        outHeight: sectionDesiredHeight,
        inHeight: sectionDesiredHeight,
        outScrollable: false,
        inScrollable: false,
      );
    }

    final sheetHeight = maxSheetHeight;
    final availableBodyHeight =
        sheetHeight - _headerHeight - _dividerHeight - media.padding.bottom;
    final sectionHeight =
        availableBodyHeight > 0
            ? (availableBodyHeight - _dividerHeight) / 2
            : 0.0;

    return _TransferSheetLayout(
      sheetHeight: sheetHeight,
      outHeight: sectionHeight,
      inHeight: sectionHeight,
      outScrollable: sectionDesiredHeight > sectionHeight + 0.5,
      inScrollable: sectionDesiredHeight > sectionHeight + 0.5,
    );
  }

  Widget _buildGrid({
    required String title,
    required int selectedIndex,
    required ValueChanged<int> onTap,
    required bool scrollable,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _horizontalPadding,
        _sectionTopPadding,
        _horizontalPadding,
        _sectionBottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _titleHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: _titleSpacing),
          Expanded(
            child:
                widget.accounts.isEmpty
                    ? const Center(child: Text("暂无账户"))
                    : GridView.builder(
                      physics:
                          scrollable
                              ? const BouncingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                      itemCount: widget.accounts.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _crossAxisCount,
                            mainAxisSpacing: _mainAxisSpacing,
                            crossAxisSpacing: _crossAxisSpacing,
                            childAspectRatio: _childAspectRatio,
                          ),
                      itemBuilder: (context, index) {
                        final selected = index == selectedIndex;
                        return GestureDetector(
                          onTap: () => onTap(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:
                                  selected ? Colors.blue : Colors.grey.shade100,
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
                                color: selected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
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
                          "账户",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    TextButton(onPressed: _confirm, child: const Text("确认")),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: layout.outHeight,
                    child: _buildGrid(
                      title: "转出账户",
                      selectedIndex: selectedOutIndex,
                      scrollable: layout.outScrollable,
                      onTap: (index) {
                        final changed = selectedOutIndex != index;

                        setState(() {
                          selectedOutIndex = index;
                          _outTouched = true;
                        });

                        _tryAutoConfirm(changedThisTap: changed);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(height: 1, color: Colors.grey.shade300),
                  ),
                  SizedBox(
                    height: layout.inHeight,
                    child: _buildGrid(
                      title: "转入账户",
                      selectedIndex: selectedInIndex,
                      scrollable: layout.inScrollable,
                      onTap: (index) {
                        final changed = selectedInIndex != index;

                        setState(() {
                          selectedInIndex = index;
                          _inTouched = true;
                        });

                        _tryAutoConfirm(changedThisTap: changed);
                      },
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

class _TransferSheetLayout {
  final double sheetHeight;
  final double outHeight;
  final double inHeight;
  final bool outScrollable;
  final bool inScrollable;

  const _TransferSheetLayout({
    required this.sheetHeight,
    required this.outHeight,
    required this.inHeight,
    required this.outScrollable,
    required this.inScrollable,
  });
}

OverlayEntry? _topNoticeOverlayEntry;
Timer? _topNoticeTimer;

void showSheetTopNotice(BuildContext context, String message) {
  _topNoticeTimer?.cancel();
  _topNoticeOverlayEntry?.remove();
  _topNoticeOverlayEntry = null;

  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;

  _topNoticeOverlayEntry = OverlayEntry(
    builder: (overlayContext) {
      final mediaQuery = MediaQuery.of(overlayContext);
      final top = mediaQuery.padding.top + 12;

      return Positioned(
        top: top,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: IgnorePointer(
            ignoring: true,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(_topNoticeOverlayEntry!);

  _topNoticeTimer = Timer(const Duration(seconds: 2), () {
    _topNoticeOverlayEntry?.remove();
    _topNoticeOverlayEntry = null;
    _topNoticeTimer = null;
  });
}
