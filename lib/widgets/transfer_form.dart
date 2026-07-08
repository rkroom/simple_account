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

  final ValueChanged<String>? onAmountChanged;
  final ValueChanged<String>? onCommentChanged;
  final ValueChanged<DateTime>? onTimeChanged;
  final ValueChanged<TransferAccountSelection>? onAccountChanged;

  final Future<void> Function(TransferFormData formData) onSubmit;
  final FutureOr<void> Function(bool success)? submitSuccess;

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
    this.onAmountChanged,
    this.onCommentChanged,
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

  final FocusNode _blankFocusNode = FocusNode();

  bool _isSubmitting = false;

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

    if (oldWidget.time != widget.time) {
      _whenTime = widget.time;
    }

    if (oldWidget.outAccountText != widget.outAccountText) {
      _showTransferAccount = widget.outAccountText;
    }

    if (oldWidget.outAccountId != widget.outAccountId) {
      _transferAccountId = widget.outAccountId;
    }

    if (oldWidget.inAccountText != widget.inAccountText) {
      _showTransferAimAccount = widget.inAccountText;
    }

    if (oldWidget.inAccountId != widget.inAccountId) {
      _transferAimAccountId = widget.inAccountId;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    _blankFocusNode.dispose();
    super.dispose();
  }

  Future<void> _clearTextFieldFocus() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _blankFocusNode.requestFocus();
    await Future.delayed(const Duration(milliseconds: 10));
  }

  List<String> _parseAccountData(List source) {
    return source.map((e) => e.toString()).toList();
  }

  Future<void> _openTransferAccountSelector() async {
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

  String _formatTime(DateTime time) {
    return "${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} "
        "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (amountText.isEmpty) {
      showNoticeSnackBar(context, "金额不能为空");
      await widget.submitSuccess?.call(false);
      return;
    }

    if (amount == null || amount < 0) {
      showNoticeSnackBar(context, "请输入正确的金额");
      await widget.submitSuccess?.call(false);
      return;
    }

    if (_transferAccountId == null) {
      showNoticeSnackBar(context, "请选择转出账户");
      await widget.submitSuccess?.call(false);
      return;
    }

    if (_transferAimAccountId == null) {
      showNoticeSnackBar(context, "请选择转入账户");
      await widget.submitSuccess?.call(false);
      return;
    }

    if (_transferAccountId == _transferAimAccountId) {
      showNoticeSnackBar(context, "转出账户和转入账户不能相同");
      await widget.submitSuccess?.call(false);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final payload = TransferFormData(
        amount: amountText,
        outAccountId: _transferAccountId!,
        inAccountId: _transferAimAccountId!,
        comment: _commentController.text.trim(),
        time: _whenTime,
        whenTime: _whenTime.toString(),
        outAccountText: _showTransferAccount,
        inAccountText: _showTransferAimAccount,
      );

      await widget.onSubmit(payload);

      if (!mounted) return;

      if (widget.clearAfterSubmit) {
        _amountController.clear();
        _commentController.clear();
        widget.onAmountChanged?.call('');
        widget.onCommentChanged?.call('');
      }

      await widget.submitSuccess?.call(true);
    } catch (error) {
      if (!mounted) return;

      debugPrint(error.toString());
      showNoticeSnackBar(
        context,
        widget.submitButtonText == '添加' ? "添加失败，请检查输入" : "保存失败，请检查输入",
      );
      await widget.submitSuccess?.call(false);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
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
                  onChanged: widget.onAmountChanged,
                ),
              ),
            ],
          ),
          _buildSelectCell(
            label: "账户：",
            value: "$_showTransferAccount → $_showTransferAimAccount",
            onTap: _openTransferAccountSelector,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await _clearTextFieldFocus();
              if (!context.mounted) return;

              DatePicker.showDateTimePicker(
                context,
                showTitleActions: true,
                currentTime: _whenTime,
                locale: LocaleType.zh,
                onConfirm: (date) {
                  setState(() {
                    _whenTime = date;
                  });
                  widget.onTimeChanged?.call(date);
                },
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Text(
                "时间：${_formatTime(_whenTime)}",
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
                  onChanged: widget.onCommentChanged,
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
    );
  }
}

/// 账户按钮文字：根据可用宽度动态缩小字号。
///
/// 最大字号采用当前 DefaultTextStyle / Theme 的默认字号，不固定写死。
/// 文字过长时自动缩小到 minFontSize。
/// 如果缩小到 minFontSize 后仍然放不下，才显示省略号。
class _AdaptiveAccountLabel extends StatelessWidget {
  static const double _minFontSize = 10;

  final String text;
  final bool selected;

  const _AdaptiveAccountLabel({required this.text, required this.selected});

  double _measureTextWidth({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required double fontSize,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: double.infinity);

    return painter.width;
  }

  double _calculateFontSize({
    required BuildContext context,
    required double maxWidth,
    required TextStyle style,
    required double maxFontSize,
  }) {
    if (maxWidth <= 0 || maxWidth.isInfinite) {
      return maxFontSize;
    }

    final maxTextWidth = _measureTextWidth(
      context: context,
      text: text,
      style: style,
      fontSize: maxFontSize,
    );

    if (maxTextWidth <= maxWidth) {
      return maxFontSize;
    }

    double low = _minFontSize;
    double high = maxFontSize;

    for (int i = 0; i < 8; i++) {
      final mid = (low + high) / 2;
      final width = _measureTextWidth(
        context: context,
        text: text,
        style: style,
        fontSize: mid,
      );

      if (width <= maxWidth) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return low;
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;

    final maxFontSize =
        defaultStyle.fontSize ??
        Theme.of(context).textTheme.bodyMedium?.fontSize ??
        14;

    final baseStyle = defaultStyle.copyWith(
      color: selected ? Colors.white : Colors.black87,
      fontWeight: FontWeight.w500,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = _calculateFontSize(
          context: context,
          maxWidth: constraints.maxWidth,
          style: baseStyle,
          maxFontSize: maxFontSize,
        );

        return Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: baseStyle.copyWith(fontSize: fontSize),
        );
      },
    );
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
  static const double _childAspectRatio = 2.5;

  static const double _horizontalPadding = 16;
  static const double _sectionTopPadding = 12;
  static const double _sectionBottomPadding = 16;
  static const double _titleHeight = 22;
  static const double _titleSpacing = 12;
  static const double _scrollbarReservedWidth = 12;

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

  final ScrollController _outScrollController = ScrollController();
  final ScrollController _inScrollController = ScrollController();

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

  @override
  void dispose() {
    _outScrollController.dispose();
    _inScrollController.dispose();
    super.dispose();
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
    required ScrollController controller,
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
                    : Scrollbar(
                      controller: controller,
                      thumbVisibility: scrollable,
                      trackVisibility: scrollable,
                      interactive: true,
                      radius: const Radius.circular(8),
                      child: GridView.builder(
                        controller: controller,
                        padding:
                            scrollable
                                ? const EdgeInsets.only(
                                  right: _scrollbarReservedWidth,
                                )
                                : EdgeInsets.zero,
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
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: _AdaptiveAccountLabel(
                                  text: widget.accounts[index],
                                  selected: selected,
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
                      controller: _outScrollController,
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
                      controller: _inScrollController,
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
