import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:simple_account/tools/tools.dart';

import '../tools/db.dart';
import '../tools/event_bus.dart';

class StatementWidget extends StatefulWidget {
  final DateTime? startTime;
  final DateTime? endTime;
  final String? accountParam;
  final String? categoryParam;
  final String? firstLevelCategoryParam;
  final String? flowParam;
  final bool isShrinkWrapped;

  /// false: 使用 getBillDetails，保持普通模式
  /// true: 使用 gettabledataWithBalance，并显示余额样式
  final bool showBalance;

  const StatementWidget({
    super.key,
    this.startTime,
    this.endTime,
    this.accountParam,
    this.categoryParam,
    this.firstLevelCategoryParam,
    this.flowParam,
    this.isShrinkWrapped = false,
    this.showBalance = false,
  });

  @override
  State<StatementWidget> createState() => StatementWidgetState();
}

class StatementWidgetState extends State<StatementWidget> {
  static const int _pageSize = 13;

  int? _selectedId;
  late _StatementTypography _typography;

  late final PagingController<int, StatementItem> _pagingController =
      PagingController<int, StatementItem>(
        getNextPageKey: (state) {
          if (!state.hasNextPage) return null;

          final pages = state.pages;
          if (pages == null || pages.isEmpty) return 0;
          if (pages.last.length < _pageSize) return null;

          final keys = state.keys ?? const <int>[];
          return keys.isEmpty ? 0 : keys.last + 1;
        },
        fetchPage: _fetchPage,
      );

  bool get _isBalanceMode => widget.showBalance;

  @override
  void initState() {
    super.initState();
    bus.on("add_bill_success", _handleBillAdded);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _typography = _StatementTypography.fromContext(context);
  }

  @override
  void didUpdateWidget(covariant StatementWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_didQueryConditionChange(oldWidget)) {
      _refreshList();
    }
  }

  bool _didQueryConditionChange(StatementWidget oldWidget) {
    return widget.startTime != oldWidget.startTime ||
        widget.endTime != oldWidget.endTime ||
        widget.accountParam != oldWidget.accountParam ||
        widget.categoryParam != oldWidget.categoryParam ||
        widget.firstLevelCategoryParam != oldWidget.firstLevelCategoryParam ||
        widget.flowParam != oldWidget.flowParam ||
        widget.showBalance != oldWidget.showBalance;
  }

  void _handleBillAdded(dynamic _) {
    _refreshList();
  }

  void _refreshList() {
    if (!mounted) return;

    if (_selectedId != null) {
      setState(() {
        _selectedId = null;
      });
    }
    _pagingController.refresh();
  }

  Future<List<StatementItem>> _fetchPage(int pageKey) async {
    final rows =
        _isBalanceMode
            ? await DB().gettabledataWithBalance(
              _pageSize,
              pageKey + 1,
              startTime: widget.startTime,
              endTime: widget.endTime,
              accountID: widget.accountParam,
              categoryID: widget.categoryParam,
              firstLevelCategoryID: widget.firstLevelCategoryParam,
              flowParam: widget.flowParam,
            )
            : await DB().getBillDetails(
              _pageSize,
              pageKey + 1,
              startTime: widget.startTime,
              endTime: widget.endTime,
              accountID: widget.accountParam,
              categoryID: widget.categoryParam,
              firstLevelCategoryID: widget.firstLevelCategoryParam,
              flowParam: widget.flowParam,
            );

    return rows.map(StatementItem.fromMap).toList(growable: false);
  }

  void _toggleExpanded(int? id) {
    setState(() {
      _selectedId = (_selectedId == id) ? null : id;
    });
  }

  Future<void> _deleteItem(StatementItem item) async {
    if (item.id == null) {
      if (mounted) {
        showNoticeSnackBar(context, '无法删除：记录 id 为空');
      }
      return;
    }

    try {
      await DB().deleteBill(item.id);

      if (!mounted) return;

      if (_isBalanceMode) {
        _refreshList();
        return;
      }

      _pagingController.value = _pagingController.value.filterItems(
        (current) => current.id != item.id,
      );

      if (_selectedId == item.id) {
        setState(() {
          _selectedId = null;
        });
      }
    } catch (error) {
      if (mounted) {
        showNoticeSnackBar(context, '$error');
      }
    }
  }

  void _showConfirmationDialog(StatementItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认'),
          content: Text('是否确认删除金额为: ${item.amount} 的记录?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await _deleteItem(item);

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PagingListener<int, StatementItem>(
      controller: _pagingController,
      builder: (context, state, fetchNextPage) {
        return PagedListView<int, StatementItem>(
          shrinkWrap: widget.isShrinkWrapped,
          physics:
              widget.isShrinkWrapped
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
          state: state,
          fetchNextPage: fetchNextPage,
          builderDelegate: PagedChildBuilderDelegate<StatementItem>(
            itemBuilder: (context, item, index) {
              final isExpanded = _selectedId == item.id;

              return Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(width: 1, color: Color(0xffe5e5e5)),
                  ),
                ),
                child: Column(
                  children: [
                    _StatementTile(
                      item: item,
                      showBalance: _isBalanceMode,
                      isExpanded: isExpanded,
                      typography: _typography,
                      onTap: () => _toggleExpanded(item.id),
                    ),
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ElevatedButton(
                          onPressed: () => _showConfirmationDialog(item),
                          child: const Text('删除'),
                        ),
                      ),
                  ],
                ),
              );
            },
            noItemsFoundIndicatorBuilder: (context) {
              return const Center(child: Text("尚无记录，添加一笔记录吧！"));
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    bus.off("add_bill_success");
    _pagingController.dispose();
    super.dispose();
  }
}

class StatementItem {
  final int? id;
  final String date;
  final String account;
  final String aimAccount;
  final String category;
  final String flow;
  final String amount;
  final String balance;
  final String comment;

  const StatementItem({
    required this.id,
    required this.date,
    required this.account,
    required this.aimAccount,
    required this.category,
    required this.flow,
    required this.amount,
    required this.balance,
    required this.comment,
  });

  factory StatementItem.fromMap(Map<String, dynamic> map) {
    return StatementItem(
      id: _toInt(map['id']),
      date: map['date']?.toString() ?? '',
      account: map['account']?.toString() ?? '',
      aimAccount: map['aim_account']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      flow: map['flow']?.toString() ?? '',
      amount: map['detailed']?.toString() ?? '',
      balance: map['balance']?.toString() ?? '',
      comment: map['comment']?.toString() ?? '',
    );
  }

  String get tailText => aimAccount.isNotEmpty ? aimAccount : category;

  String get shortDate => date.length > 5 ? date.substring(5) : date;

  bool get isExpense => flow == '支出';

  bool get isTransfer => flow == '转账';

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

class _StatementTile extends StatelessWidget {
  final StatementItem item;
  final bool showBalance;
  final bool isExpanded;
  final _StatementTypography typography;
  final VoidCallback onTap;

  const _StatementTile({
    required this.item,
    required this.showBalance,
    required this.isExpanded,
    required this.typography,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMainInfoRow(),
            const SizedBox(height: 2),
            showBalance ? _buildBalanceSubtitle() : _buildDefaultSubtitle(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainInfoRow() {
    return _buildThreeColumnRow(
      col1: _buildLeadingCell(
        item.account,
        style: typography.main,
        maxLines: isExpanded ? null : 1,
        overflow: isExpanded ? null : TextOverflow.ellipsis,
        softWrap: isExpanded,
      ),
      col2: _buildAmountCell(),
      col3: _buildLeadingCell(
        item.tailText,
        style: typography.main,
        maxLines: isExpanded ? null : 1,
        overflow: isExpanded ? null : TextOverflow.ellipsis,
        softWrap: isExpanded,
      ),
    );
  }

  Widget _buildDefaultSubtitle() {
    final hasComment = item.comment.isNotEmpty;
    final safeBaseline =
        typography.subBaseline > 0
            ? typography.subBaseline
            : (typography.sub.fontSize ?? 12);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Baseline(
          baseline: safeBaseline,
          baselineType: TextBaseline.alphabetic,
          child: Text(item.shortDate, style: typography.sub),
        ),
        if (hasComment) const SizedBox(width: 8),
        if (hasComment)
          Expanded(
            child: Baseline(
              baseline: safeBaseline,
              baselineType: TextBaseline.alphabetic,
              child: Text(
                '备注: ${item.comment}',
                style: typography.sub,
                softWrap: true,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBalanceSubtitle() {
    final hasComment = item.comment.isNotEmpty;
    final safeBaseline =
        typography.subBaseline > 0
            ? typography.subBaseline
            : (typography.sub.fontSize ?? 12);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildThreeColumnRow(
          col1: Baseline(
            baseline: safeBaseline,
            baselineType: TextBaseline.alphabetic,
            child: _buildLeadingCell(
              item.shortDate,
              style: typography.sub,
              maxLines: isExpanded ? null : 1,
              overflow: isExpanded ? null : TextOverflow.ellipsis,
              softWrap: isExpanded,
            ),
          ),
          col2: _buildBalanceCell(),
          col3: const SizedBox.shrink(),
        ),
        if (item.isTransfer || hasComment)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isTransfer) Text('转账', style: typography.comment),
                if (item.isTransfer && hasComment) const SizedBox(width: 8),
                if (hasComment)
                  Expanded(
                    child: Text(
                      '备注: ${item.comment}',
                      maxLines: isExpanded ? null : 1,
                      overflow: isExpanded ? null : null,
                      softWrap: isExpanded,
                      style: typography.comment,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAmountCell() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '-',
              style: typography.main.copyWith(
                color:
                    item.isExpense ? typography.main.color : Colors.transparent,
              ),
            ),
            TextSpan(text: item.amount, style: typography.main),
          ],
        ),
        maxLines: isExpanded ? null : 1,
        overflow: isExpanded ? null : TextOverflow.visible,
        softWrap: isExpanded,
      ),
    );
  }

  Widget _buildBalanceCell() {
    if (item.balance.isEmpty) {
      return const SizedBox.shrink();
    }

    final safeBaseline =
        typography.subBaseline > 0
            ? typography.subBaseline
            : (typography.sub.fontSize ?? 12);

    return Baseline(
      baseline: safeBaseline,
      baselineType: TextBaseline.alphabetic,
      child: Padding(
        padding: EdgeInsets.only(left: typography.minusWidth),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '余额: ${item.balance}',
            maxLines: isExpanded ? null : 1,
            overflow: isExpanded ? null : TextOverflow.visible,
            softWrap: isExpanded,
            style: typography.sub,
          ),
        ),
      ),
    );
  }

  Widget _buildThreeColumnRow({
    required Widget col1,
    required Widget col2,
    required Widget col3,
  }) {
    return Row(
      crossAxisAlignment:
          isExpanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Expanded(flex: 3, child: col1),
        Expanded(flex: 3, child: col2),
        Expanded(flex: 2, child: col3),
      ],
    );
  }

  Widget _buildLeadingCell(
    String text, {
    required TextStyle style,
    int? maxLines = 1,
    TextOverflow? overflow = TextOverflow.ellipsis,
    bool softWrap = false,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        style: style,
      ),
    );
  }
}

class _StatementTypography {
  final TextStyle main;
  final TextStyle sub;
  final TextStyle comment;
  final double minusWidth;
  final double subBaseline;

  const _StatementTypography({
    required this.main,
    required this.sub,
    required this.comment,
    required this.minusWidth,
    required this.subBaseline,
  });

  factory _StatementTypography.fromContext(BuildContext context) {
    final main = Theme.of(context).textTheme.titleMedium ?? const TextStyle();
    final sub = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
    final comment = sub.copyWith(
      height: 0.98,
      fontSize: (sub.fontSize ?? 12) - 0.5,
    );
    final textScaler = MediaQuery.textScalerOf(context);

    return _StatementTypography(
      main: main,
      sub: sub,
      comment: comment,
      minusWidth: _measureTextWidth('-', main, textScaler),
      subBaseline: _measureAlphabeticBaseline(sub, textScaler),
    );
  }

  static double _measureTextWidth(
    String text,
    TextStyle style,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();

    return painter.width;
  }

  static double _measureAlphabeticBaseline(
    TextStyle style,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: '测', style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();

    return painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }
}
