import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';
import 'package:simple_account/tools/config.dart';

import '../tools/bill_listener_service.dart';
import '../tools/db.dart';
import '../tools/event_bus.dart';
import '../tools/native_method_channel.dart';
import '../tools/tools.dart';
import '../tools/config_enum.dart';
import 'quick_select.dart';
import 'transactions.dart';

class AddWidget extends StatefulWidget {
  const AddWidget({super.key});
  @override
  State<StatefulWidget> createState() {
    return AddWidgetState();
  }
}

class AddWidgetState extends State<AddWidget>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const TextScaler customTextScaler = TextScaler.linear(1.2);
  bool _hasPermission = false;
  int _billCount = 0; // 账单数量

  @override
  bool get wantKeepAlive => true;

  // 标签
  final tabs = ["支出", "收入", "转账"];

  // 记录时间
  DateTime whenTime = DateTime.now();
  // 支出功能变量
  String showConsumeAccount = "请选择";
  int? consumeAccountId;
  List consumeCategory = [];
  List<int>? selectedConsumeCategory;
  String showConsumeCategory = "请选择";
  Map consumeCategoryIndex = {};
  int? consumeCategoryId;

  // 收入功能变量
  String showIncomeAccount = "请选择";
  int? incomeAccountId;
  List incomeCategory = [];
  String showIncomeCategory = "请选择";
  Map incomeCategoryIndex = {};
  int? incomeCategoryId;

  // 转账功能变量
  String showTransferAccount = "请选择";
  int? transferAccountId;
  String showTransferAimAccount = "请选择";
  int? transferAimAccountId;
  final TextEditingController _transferAmountController =
      TextEditingController();
  final TextEditingController _transferCommentController =
      TextEditingController();
  // 账户信息功能
  List accountName = [];
  Map accountIndex = {};

  //添加标志变量，当whenTime修改后一定时间内，应用从后台恢复到前台不修改whenTime
  DateTime timeSign = DateTime.now();

  void initData() async {
    // 使用 Future.wait 并行执行所有异步任务
    var results = await Future.wait([
      getCategory("consume"), // 获取消费分类
      getCategory("income"), // 获取收入分类
      getAccount(), // 获取账户信息
    ]);
    if (!mounted) return;
    // 在所有异步任务完成后，统一更新状态
    setState(() {
      // 消费分类
      consumeCategory = results[0][0];
      consumeCategoryIndex = results[0][1];

      // 收入分类
      incomeCategory = results[1][0];
      incomeCategoryIndex = results[1][1];

      // 账户信息
      accountName = results[2][0];
      accountIndex = results[2][1];
    });
  }

  List<String> _parseAccountData(List source) {
    return source.map((e) => e.toString()).toList();
  }

  Future<void> _openTransferAccountSelector() async {
    final accounts = _parseAccountData(accountName);

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
            accountIndex: accountIndex,
            selectedOutText:
                showTransferAccount == "请选择" ? null : showTransferAccount,
            selectedInText:
                showTransferAimAccount == "请选择" ? null : showTransferAimAccount,
          ),
    );

    if (!mounted || result == null) return;

    setState(() {
      showTransferAccount = result["outText"] as String;
      transferAccountId = result["outId"] as int?;
      showTransferAimAccount = result["inText"] as String;
      transferAimAccountId = result["inId"] as int?;
    });
  }

  Future<void> _checkPermissionsAndFetchBills() async {
    try {
      final results = await Future.wait([
        NativeMethodChannel.instance.checkAccessibilityPermission(),
        NativeMethodChannel.instance.checkNotificationListenerPermission(),
      ]);

      final accessibilityPermission = results[0];
      final notificationListenerPermission = results[1];

      if (mounted) {
        setState(() {
          _hasPermission =
              accessibilityPermission || notificationListenerPermission;
        });
        if (_hasPermission) {
          final bills = await BillListenerService().getBills();
          if (mounted) {
            setState(() {
              _billCount = bills.length;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _billCount = 0;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _billCount = 0;
        });
      }
    }
  }

  Future<void> _updateAccount(arg) async {
    final list = await getAccount();
    if (!mounted) return;
    setState(() {
      accountName = list[0];
      accountIndex = list[1];
    });
  }

  @override
  void initState() {
    super.initState();
    initData();
    bus.on("update_category", (arg) {
      getCategory("consume").then((list) {
        setState(() {
          consumeCategory = list[0];
          consumeCategoryIndex = list[1];
        });
      });
      getCategory("income").then((list) {
        setState(() {
          incomeCategory = list[0];
          incomeCategoryIndex = list[1];
        });
      });
    });

    bus.on("update_account", _updateAccount);
    _checkPermissionsAndFetchBills(); // 初始调用
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 仅处理 resumed 状态
    if (state != AppLifecycleState.resumed) {
      return;
    }
    if (Global.isReturningFromSettings) {
      _checkPermissionsAndFetchBills();
      Global.isReturningFromSettings = false;
    }

    // 获取当前时间
    final DateTime now = DateTime.now();

    // 如果时间差在3分钟以上，则更新 whenTime
    if (now.difference(timeSign).inMinutes >= 3) {
      setState(() {
        whenTime = now;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    bus.off("update_category");
    bus.off("update_account", _updateAccount);
    _transferAmountController.dispose();
    _transferCommentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 通过DefaultTabController将tabBar和tabBarView联系
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        // 将标签显示在appbar处
        appBar: PreferredSize(
          // 该appbar的高度，你可以自行设置一个值
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            // 背景颜色
            color: Theme.of(context).primaryColor,
            child: Column(
              children: <Widget>[
                // 获取标签
                getTabBar(),
              ],
            ),
          ),
        ),
        body: getTabBarPages(),
      ),
    );
  }

  // 获取标签
  Widget getTabBar() {
    // 返回TabBar
    return TabBar(
      tabs:
          tabs.map((t) {
            return Tab(child: Text(t));
          }).toList(),
    );
  }

  accountQuickSelect(item) {
    setState(() {
      showConsumeAccount = item["name"];
      consumeAccountId = item["id"];
    });
  }

  categoryQuickSelect(item) {
    setState(() {
      showConsumeCategory = item["category"];
      selectedConsumeCategory = findElementIndexes(
        consumeCategory,
        item["category"],
      );
      consumeCategoryId = item["id"];
    });
  }

  //支出，收入，转账分别的页面。
  //支出
  Widget consume() {
    return Column(
      children: [
        Expanded(
          child: QuickSelect(
            accountQuickSelect: accountQuickSelect,
            categoryQuickSelect: categoryQuickSelect,
          ),
        ),
        Stack(
          children: [
            Transactions(
              flow: Transaction.consume,
              accountNames: accountName,
              accountIndexs: accountIndex,
              categoryIndex: consumeCategoryIndex,
              categories: consumeCategory,
              time: whenTime,
              accountText: showConsumeAccount,
              accountId: consumeAccountId,
              categoryText: showConsumeCategory,
              categoryId: consumeCategoryId,
              selectedCategory: selectedConsumeCategory,
              onTimeChanged: (time) {
                timeSign = DateTime.now();
              },
            ),
            if (defaultTargetPlatform == TargetPlatform.android) ...[
              if (_hasPermission)
                Positioned(
                  bottom: 5.0,
                  right: 12.0,
                  child: Stack(
                    children: [
                      IconButton(
                        icon: Icon(
                          size: 35.0,
                          Icons.article,
                          color: Colors.blue[600],
                        ),
                        onPressed: () async {
                          await Navigator.of(
                            context,
                          ).pushNamed('/billListener');
                          _checkPermissionsAndFetchBills();
                        },
                      ),
                      if (_billCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$_billCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }

  //收入
  Widget income() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: 20,
          child: Transactions(
            flow: Transaction.income,
            accountNames: accountName,
            accountIndexs: accountIndex,
            categoryIndex: incomeCategoryIndex,
            categories: incomeCategory,
            time: whenTime,
            accountText: showIncomeAccount,
            accountId: incomeAccountId,
            categoryText: showIncomeCategory,
            categoryId: incomeCategoryId,
            onTimeChanged: (time) {
              timeSign = DateTime.now();
            },
          ),
        ),
      ],
    );
  }

  // 转账
  Widget transfer() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: 20,
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
                      controller: _transferAmountController,
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
                    "账户：$showTransferAccount → $showTransferAimAccount",
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
                          whenTime = date;
                        });
                        timeSign = DateTime.now();
                      },
                      currentTime: whenTime,
                      locale: LocaleType.zh,
                    );
                  },
                  child: Text(
                    "时间：${whenTime.year.toString()}-${whenTime.month.toString().padLeft(2, '0')}-${whenTime.day.toString().padLeft(2, '0')} ${whenTime.hour.toString().padLeft(2, '0')}:${whenTime.minute.toString().padLeft(2, '0')}",
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
                    child: TextField(controller: _transferCommentController),
                  ),
                ],
              ),
              ElevatedButton(
                child: const Text("添加"),
                onPressed: () async {
                  if (_transferAmountController.text.isEmpty) {
                    showNoticeSnackBar(context, "金额不能为空");
                    return;
                  }

                  if (transferAccountId == null) {
                    showNoticeSnackBar(context, "请选择转出账户");
                    return;
                  }

                  if (transferAimAccountId == null) {
                    showNoticeSnackBar(context, "请选择转入账户");
                    return;
                  }

                  if (transferAccountId == transferAimAccountId) {
                    showNoticeSnackBar(context, "转出账户和转入账户不能相同");
                    return;
                  }

                  try {
                    await DB().addTransfer(
                      _transferAmountController.text,
                      transferAccountId!,
                      transferAimAccountId!,
                      _transferCommentController.text,
                      whenTime.toString(),
                    );

                    _transferAmountController.clear();
                    _transferCommentController.clear();
                  } catch (error) {
                    if (!mounted) return;
                    showNoticeSnackBar(context, "添加失败，请检查输入");
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 将支出，收入，转账页面添加到一个list
  listPages() {
    List<Widget> tabPages = [];
    return tabPages
      ..add(consume())
      ..add(income())
      ..add(transfer());
  }

  // 返回页面
  Widget getTabBarPages() {
    return TabBarView(children: listPages());
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
