import 'package:flutter/material.dart';

import '../tools/bill_listener_service.dart';
import '../tools/db.dart';
import '../tools/event_bus.dart';
import '../tools/tools.dart';
import '../tools/config_enum.dart';
import '../widgets/transactions.dart';
import '../widgets/quick_select.dart';
import '../widgets/transfer_form.dart';

class BillListenerWidget extends StatefulWidget {
  const BillListenerWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return BillListenerWidgetState();
  }
}

class BillListenerWidgetState extends State<BillListenerWidget>
    with WidgetsBindingObserver {
  static const double _topQuickSelectHeight = 255;
  static const double _topQuickSelectTopGap = 8;
  static const double _topQuickSelectBottomGap = 0;

  final Map<dynamic, GlobalKey<_BillListenerEditorCardState>> _cardKeys = {};
  int _initDataToken = 0;
  int _loadToken = 0;

  List notifications = [];

  List accountNames = [];
  Map accountIndexs = {};

  List consumeCategories = [];
  Map consumeCategoryIndex = {};

  List incomeCategories = [];
  Map incomeCategoryIndex = {};

  _BillListenerFlow _firstFlow = _BillListenerFlow.consume;

  GlobalKey<_BillListenerEditorCardState> _getCardKey(dynamic id) {
    return _cardKeys.putIfAbsent(
      id,
      () => GlobalKey<_BillListenerEditorCardState>(),
    );
  }

  bool _isSameNotificationList(List oldList, List newList) {
    if (oldList.length != newList.length) return false;

    for (int i = 0; i < oldList.length; i++) {
      if (oldList[i].id != newList[i].id) {
        return false;
      }
    }

    return true;
  }

  _BillListenerFlow _flowOfFirstInList(List list) {
    if (list.isEmpty) {
      return _BillListenerFlow.consume;
    }

    final firstId = list.first.id;
    return _cardKeys[firstId]?.currentState?.currentFlow ??
        _BillListenerFlow.consume;
  }

  void _removeUnusedKeys(List currentNotifications) {
    final ids = currentNotifications.map((item) => item.id).toSet();
    _cardKeys.removeWhere((id, _) => !ids.contains(id));
  }

  Future<void> initData() async {
    final initToken = ++_initDataToken;
    final billToken = ++_loadToken;

    final results = await Future.wait([
      getAccount(),
      getCategory(Transaction.consume.value),
      getCategory(Transaction.income.value),
      BillListenerService().getBills(),
    ]);

    if (!mounted || initToken != _initDataToken) return;

    final accountResult = results[0] as List;
    final consumeResult = results[1] as List;
    final incomeResult = results[2] as List;
    final billResults = results[3] as List;

    setState(() {
      accountNames = accountResult[0];
      accountIndexs = accountResult[1];

      consumeCategories = consumeResult[0];
      consumeCategoryIndex = consumeResult[1];

      incomeCategories = incomeResult[0];
      incomeCategoryIndex = incomeResult[1];

      if (billToken == _loadToken) {
        notifications = billResults;
        _removeUnusedKeys(notifications);
        _firstFlow = _flowOfFirstInList(notifications);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cardKeys.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    if (state != AppLifecycleState.resumed) return;

    final token = ++_loadToken;
    final value = await BillListenerService().getBills();

    if (!mounted || token != _loadToken) return;

    if (_isSameNotificationList(notifications, value)) {
      return;
    }

    setState(() {
      notifications = value;
      _removeUnusedKeys(notifications);
      _firstFlow = _flowOfFirstInList(notifications);
    });
  }

  Future<void> _clearNotifications() async {
    ++_loadToken;

    await BillListenerService().clearBillListenerBox();

    if (!mounted) return;

    ++_loadToken;

    setState(() {
      notifications = [];
      _cardKeys.clear();
      _firstFlow = _BillListenerFlow.consume;
    });
  }

  Future<void> _deleteNotification(dynamic billItem) async {
    ++_loadToken;

    await BillListenerService().delBill(billItem.id);

    if (!mounted) return;

    ++_loadToken;

    final nextNotifications = notifications
        .where((item) => item.id != billItem.id)
        .toList(growable: false);

    final nextFirstFlow = _flowOfFirstInList(nextNotifications);

    setState(() {
      notifications = nextNotifications;
      _cardKeys.remove(billItem.id);
      _firstFlow = nextFirstFlow;
    });
  }

  Future<void> _handleSaved(dynamic billItem) async {
    ++_loadToken;

    await BillListenerService().delBill(billItem.id);
    bus.emit("add_bill_success");

    if (!mounted) return;

    ++_loadToken;

    final nextNotifications = notifications
        .where((item) => item.id != billItem.id)
        .toList(growable: false);

    final nextFirstFlow = _flowOfFirstInList(nextNotifications);

    setState(() {
      notifications = nextNotifications;
      _cardKeys.remove(billItem.id);
      _firstFlow = nextFirstFlow;
    });
  }

  void _showClearConfirmDialog() {
    if (notifications.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('确认操作'),
          content: const Text('确定要清空所有记录吗？'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('确定'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _clearNotifications();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Text('暂无监听到账单', style: TextStyle(color: Colors.black45)),
    );
  }

  Widget _buildTopQuickSelect({required bool keyboardVisible}) {
    if (notifications.isEmpty) {
      return const SizedBox.shrink();
    }

    const double fullHeight =
        _topQuickSelectHeight +
        _topQuickSelectTopGap +
        _topQuickSelectBottomGap;

    final bool isTransfer = _firstFlow == _BillListenerFlow.transfer;

    return ClipRect(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,

        // 只在键盘弹出时收起
        // 支出 / 收入 / 转账之间切换时，始终保留顶部高度，避免列表跳动
        height: keyboardVisible ? 0 : fullHeight,

        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(
              top: _topQuickSelectTopGap,
              bottom: _topQuickSelectBottomGap,
            ),
            child: SizedBox(
              height: _topQuickSelectHeight,
              child:
                  isTransfer
                      // 转账模式下保留同样高度的空白区域
                      // 避免从支出/收入切换到转账时 ListView 上下跳动
                      ? const SizedBox.expand()
                      : QuickSelect(
                        flow: _firstFlow.value,
                        accountQuickSelect: (item) {
                          if (notifications.isEmpty) return;

                          final firstId = notifications.first.id;
                          _cardKeys[firstId]?.currentState?.applyQuickAccount(
                            item,
                          );
                        },
                        categoryQuickSelect: (item) {
                          if (notifications.isEmpty) return;

                          final firstId = notifications.first.id;
                          _cardKeys[firstId]?.currentState?.applyQuickCategory(
                            item,
                          );
                        },
                      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final double keyboardBottom = MediaQuery.of(context).viewInsets.bottom;
    final bool keyboardVisible = keyboardBottom > 0;

    if (notifications.isEmpty) {
      return _buildEmptyView();
    }

    return Column(
      children: [
        _buildTopQuickSelect(keyboardVisible: keyboardVisible),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              bottom: keyboardVisible ? keyboardBottom + 24 : 12,
            ),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final billItem = notifications[index];
              final cardKey = _getCardKey(billItem.id);

              return _BillListenerEditorCard(
                key: cardKey,
                billItem: billItem,
                accountNames: accountNames,
                accountIndexs: accountIndexs,
                consumeCategories: consumeCategories,
                consumeCategoryIndex: consumeCategoryIndex,
                incomeCategories: incomeCategories,
                incomeCategoryIndex: incomeCategoryIndex,
                onFlowChanged: (flow) {
                  if (notifications.isNotEmpty &&
                      notifications.first.id == billItem.id) {
                    setState(() {
                      _firstFlow = flow;
                    });
                  }
                },
                onDeleted: () => _deleteNotification(billItem),
                onSaved: () => _handleSaved(billItem),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('账单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _showClearConfirmDialog,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

enum _BillListenerFlow { consume, income, transfer }

extension _BillListenerFlowText on _BillListenerFlow {
  String get value {
    switch (this) {
      case _BillListenerFlow.consume:
        return Transaction.consume.value;
      case _BillListenerFlow.income:
        return Transaction.income.value;
      case _BillListenerFlow.transfer:
        return 'transfer';
    }
  }

  Transaction get transaction {
    switch (this) {
      case _BillListenerFlow.consume:
        return Transaction.consume;
      case _BillListenerFlow.income:
        return Transaction.income;
      case _BillListenerFlow.transfer:
        return Transaction.consume;
    }
  }
}

class _BillListenerEditorCard extends StatefulWidget {
  final dynamic billItem;

  final List accountNames;
  final Map accountIndexs;

  final List consumeCategories;
  final Map consumeCategoryIndex;

  final List incomeCategories;
  final Map incomeCategoryIndex;

  final ValueChanged<_BillListenerFlow>? onFlowChanged;

  final Future<void> Function() onDeleted;
  final Future<void> Function() onSaved;

  const _BillListenerEditorCard({
    super.key,
    required this.billItem,
    required this.accountNames,
    required this.accountIndexs,
    required this.consumeCategories,
    required this.consumeCategoryIndex,
    required this.incomeCategories,
    required this.incomeCategoryIndex,
    this.onFlowChanged,
    required this.onDeleted,
    required this.onSaved,
  });

  @override
  State<_BillListenerEditorCard> createState() =>
      _BillListenerEditorCardState();
}

class _BillListenerEditorCardState extends State<_BillListenerEditorCard> {
  static const double _billItemHeight = 350;

  _BillListenerFlow _flow = _BillListenerFlow.consume;

  Offset? _pointerDownPosition;
  Offset? _pointerUpPosition;

  String _amount = '';
  String _comment = '';

  DateTime _time = DateTime.now();

  String _accountText = '请选择';
  int? _accountId;

  String _categoryText = '请选择';
  int? _categoryId;
  List<int>? _selectedCategory;

  String _transferOutText = '请选择';
  int? _transferOutId;

  String _transferInText = '请选择';
  int? _transferInId;

  _BillListenerFlow get currentFlow => _flow;

  @override
  void initState() {
    super.initState();
    _resetFromBillItem();
  }

  @override
  void didUpdateWidget(covariant _BillListenerEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.billItem.id != widget.billItem.id) {
      _resetFromBillItem();
    }
  }

  void _resetFromBillItem() {
    final billItem = widget.billItem;

    _flow = _BillListenerFlow.consume;

    _amount = billItem.detailed?.toString() ?? '';
    _comment = '';

    _time = billItem.time ?? DateTime.now();

    _accountText = billItem.accountText ?? '请选择';
    _accountId = billItem.account;

    _categoryText = billItem.categoryText ?? '请选择';
    _categoryId = billItem.categoryId;
    _selectedCategory = billItem.selectedCategory;

    _transferOutText = _accountText;
    _transferOutId = _accountId;

    _transferInText = '请选择';
    _transferInId = null;
  }

  List get _currentCategories {
    switch (_flow) {
      case _BillListenerFlow.income:
        return widget.incomeCategories;
      case _BillListenerFlow.consume:
      case _BillListenerFlow.transfer:
        return widget.consumeCategories;
    }
  }

  Map get _currentCategoryIndex {
    switch (_flow) {
      case _BillListenerFlow.income:
        return widget.incomeCategoryIndex;
      case _BillListenerFlow.consume:
      case _BillListenerFlow.transfer:
        return widget.consumeCategoryIndex;
    }
  }

  void applyQuickAccount(dynamic item) {
    if (_flow == _BillListenerFlow.transfer) return;

    setState(() {
      _accountText = item["name"]?.toString() ?? '请选择';
      _accountId = _toInt(item["id"]);
    });
  }

  void applyQuickCategory(dynamic item) {
    if (_flow == _BillListenerFlow.transfer) return;

    setState(() {
      _selectedCategory = findElementIndexes(
        _currentCategories,
        item['category'],
      );
      _categoryText = item['category']?.toString() ?? '请选择';
      _categoryId = _toInt(item["id"]);
    });
  }

  void _changeFlow(_BillListenerFlow flow) {
    if (_flow == flow) return;

    setState(() {
      _flow = flow;

      if (flow == _BillListenerFlow.consume) {
        _categoryText = widget.billItem.categoryText ?? '请选择';
        _categoryId = widget.billItem.categoryId;
        _selectedCategory = widget.billItem.selectedCategory;
      }

      if (flow == _BillListenerFlow.income) {
        _categoryText = '请选择';
        _categoryId = null;
        _selectedCategory = null;
      }

      if (flow == _BillListenerFlow.transfer) {
        _transferOutText = _accountText;
        _transferOutId = _accountId;
      }
    });

    widget.onFlowChanged?.call(flow);
  }

  void _switchFlowBySwipe(bool toNext) {
    const flows = [
      _BillListenerFlow.consume,
      _BillListenerFlow.income,
      _BillListenerFlow.transfer,
    ];

    final currentIndex = flows.indexOf(_flow);

    int nextIndex;

    if (toNext) {
      nextIndex = currentIndex + 1;
      if (nextIndex >= flows.length) nextIndex = 0;
    } else {
      nextIndex = currentIndex - 1;
      if (nextIndex < 0) nextIndex = flows.length - 1;
    }

    _changeFlow(flows[nextIndex]);
  }

  Widget _buildSwipeableForm() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerDownPosition = event.position;
        _pointerUpPosition = event.position;
      },
      onPointerMove: (event) {
        _pointerUpPosition = event.position;
      },
      onPointerUp: (event) {
        final start = _pointerDownPosition;
        _pointerUpPosition = event.position;
        final end = _pointerUpPosition;

        _pointerDownPosition = null;
        _pointerUpPosition = null;

        if (start == null || end == null) return;

        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;

        // 横向距离太短，不切换，避免误触
        if (dx.abs() < 80) return;

        // 必须明显是横向滑动，避免影响 ListView 上下滚动
        if (dx.abs() < dy.abs() * 1.5) return;

        if (dx < 0) {
          // 左滑：支出 -> 收入 -> 转账
          _switchFlowBySwipe(true);
        } else {
          // 右滑：转账 -> 收入 -> 支出
          _switchFlowBySwipe(false);
        }
      },
      onPointerCancel: (event) {
        _pointerDownPosition = null;
        _pointerUpPosition = null;
      },
      child: _buildFormByFlow(),
    );
  }

  Widget _buildHeader() {
    final source = widget.billItem.source?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 48, 4),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, size: 16, color: Colors.black45),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              source.isEmpty ? '来源：未知' : '来源：$source',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: SegmentedButton<_BillListenerFlow>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _BillListenerFlow.consume, label: Text('支出')),
          ButtonSegment(value: _BillListenerFlow.income, label: Text('收入')),
          ButtonSegment(value: _BillListenerFlow.transfer, label: Text('转账')),
        ],
        selected: {_flow},
        onSelectionChanged: (values) {
          _changeFlow(values.first);
        },
      ),
    );
  }

  Widget _buildTransactionForm() {
    return Transactions(
      key: ValueKey('${widget.billItem.id}_${_flow.name}'),
      amount: _amount,
      flow: _flow.transaction,
      accountNames: widget.accountNames,
      accountIndexs: widget.accountIndexs,
      categories: _currentCategories,
      categoryIndex: _currentCategoryIndex,
      time: _time,
      accountId: _accountId,
      accountText: _accountText,
      selectedCategory: _selectedCategory,
      categoryText: _categoryText,
      categoryId: _categoryId,
      initialComment: _comment,
      addSuccess: (success) async {
        if (success) {
          await widget.onSaved();
        }
      },
      onAmountChanged: (value) {
        _amount = value;
      },
      onCommentChanged: (value) {
        _comment = value;
      },
      onCategoryConfirm: (category) {
        _selectedCategory = category["selected"];
        _categoryText = category["text"];
        _categoryId = category["categoryId"];
      },
      onAccountConfirm: (account) {
        _accountId = account["accountId"];
        _accountText = account["text"];
      },
      onTimeChanged: (time) {
        _time = time;
      },
    );
  }

  Widget _buildTransferForm() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: TransferForm(
        key: ValueKey('${widget.billItem.id}_${_flow.name}'),
        amount: _amount,
        initialComment: _comment,
        accountNames: widget.accountNames,
        accountIndexs: widget.accountIndexs,
        time: _time,
        outAccountText: _transferOutText,
        outAccountId: _transferOutId,
        inAccountText: _transferInText,
        inAccountId: _transferInId,
        clearAfterSubmit: false,
        submitButtonText: '添加',
        onAmountChanged: (value) {
          _amount = value;
        },
        onCommentChanged: (value) {
          _comment = value;
        },
        onTimeChanged: (time) {
          _time = time;
        },
        onAccountChanged: (selection) {
          _transferOutText = selection.outText;
          _transferOutId = selection.outId;
          _transferInText = selection.inText;
          _transferInId = selection.inId;
        },
        onSubmit: (formData) async {
          await DB().addTransfer(
            formData.amount,
            formData.outAccountId,
            formData.inAccountId,
            formData.comment,
            formData.time,
          );
        },
        submitSuccess: (success) async {
          if (success) {
            await widget.onSaved();
          }
        },
      ),
    );
  }

  Widget _buildFormByFlow() {
    switch (_flow) {
      case _BillListenerFlow.consume:
      case _BillListenerFlow.income:
        return _buildTransactionForm();
      case _BillListenerFlow.transfer:
        return _buildTransferForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _billItemHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                _buildHeader(),
                _buildFlowSelector(),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _buildSwipeableForm(),
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          ),
          Positioned(
            top: 0.0,
            right: 8.0,
            child: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: widget.onDeleted,
            ),
          ),
        ],
      ),
    );
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
