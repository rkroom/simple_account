import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:simple_account/tools/config.dart';

import '../tools/bill_listener_service.dart';
import '../tools/db.dart';
import '../tools/event_bus.dart';
import '../tools/native_method_channel.dart';
import '../tools/tools.dart';
import '../tools/config_enum.dart';
import 'quick_select.dart';
import 'transactions.dart';
import 'transfer_form.dart';

class AddWidget extends StatefulWidget {
  const AddWidget({super.key});
  @override
  State<StatefulWidget> createState() {
    return AddWidgetState();
  }
}

class AddWidgetState extends State<AddWidget>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  bool _hasPermission = false;
  int _billCount = 0; // 账单数量

  int _categoryLoadToken = 0;
  int _accountLoadToken = 0;
  int _permissionCheckToken = 0;

  @override
  bool get wantKeepAlive => true;

  // 标签
  final tabs = ["支出", "收入", "转账"];

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
  List<int>? selectedIncomeCategory;
  String showIncomeCategory = "请选择";
  Map incomeCategoryIndex = {};
  int? incomeCategoryId;

  // 转账功能变量
  String showTransferAccount = "请选择";
  int? transferAccountId;
  String showTransferAimAccount = "请选择";
  int? transferAimAccountId;
  // 账户信息功能
  List accountName = [];
  Map accountIndex = {};

  // 支出记录时间
  DateTime consumeWhenTime = DateTime.now();

  // 收入记录时间
  DateTime incomeWhenTime = DateTime.now();

  // 转账记录时间
  DateTime transferWhenTime = DateTime.now();

  // 添加标志变量：当对应时间修改后，一定时间内应用从后台恢复到前台不自动更新时间
  DateTime consumeTimeSign = DateTime.now();
  DateTime incomeTimeSign = DateTime.now();
  DateTime transferTimeSign = DateTime.now();

  void initData() async {
    final categoryToken = ++_categoryLoadToken;
    final accountToken = ++_accountLoadToken;

    // 使用 Future.wait 并行执行所有异步任务
    var results = await Future.wait([
      getCategory("consume"), // 获取消费分类
      getCategory("income"), // 获取收入分类
      getAccount(), // 获取账户信息
    ]);

    if (!mounted) return;

    // 在所有异步任务完成后，统一更新状态
    setState(() {
      if (categoryToken == _categoryLoadToken) {
        // 消费分类
        consumeCategory = results[0][0];
        consumeCategoryIndex = results[0][1];

        // 收入分类
        incomeCategory = results[1][0];
        incomeCategoryIndex = results[1][1];
      }

      if (accountToken == _accountLoadToken) {
        // 账户信息
        accountName = results[2][0];
        accountIndex = results[2][1];
      }
    });
  }

  Future<void> _updateCategory(dynamic arg) async {
    final token = ++_categoryLoadToken;

    final results = await Future.wait([
      getCategory("consume"),
      getCategory("income"),
    ]);

    if (!mounted || token != _categoryLoadToken) return;

    setState(() {
      consumeCategory = results[0][0];
      consumeCategoryIndex = results[0][1];

      incomeCategory = results[1][0];
      incomeCategoryIndex = results[1][1];
    });
  }

  Future<void> _checkPermissionsAndFetchBills() async {
    final token = ++_permissionCheckToken;

    try {
      final results = await Future.wait([
        NativeMethodChannel.instance.checkAccessibilityPermission(),
        NativeMethodChannel.instance.checkNotificationListenerPermission(),
      ]);

      if (!mounted || token != _permissionCheckToken) return;

      final accessibilityPermission = results[0];
      final notificationListenerPermission = results[1];

      final hasPermission =
          accessibilityPermission || notificationListenerPermission;

      if (!hasPermission) {
        setState(() {
          _hasPermission = false;
          _billCount = 0;
        });
        return;
      }

      final bills = await BillListenerService().getBills();

      if (!mounted || token != _permissionCheckToken) return;

      setState(() {
        _hasPermission = true;
        _billCount = bills.length;
      });
    } catch (e) {
      if (!mounted || token != _permissionCheckToken) return;

      setState(() {
        _hasPermission = false;
        _billCount = 0;
      });
    }
  }

  Future<void> _updateAccount(arg) async {
    final token = ++_accountLoadToken;

    final list = await getAccount();

    if (!mounted || token != _accountLoadToken) return;

    setState(() {
      accountName = list[0];
      accountIndex = list[1];
    });
  }

  @override
  void initState() {
    super.initState();
    initData();
    bus.on("update_category", _updateCategory);

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

    setState(() {
      if (now.difference(consumeTimeSign).inMinutes >= 3) {
        consumeWhenTime = now;
      }

      if (now.difference(incomeTimeSign).inMinutes >= 3) {
        incomeWhenTime = now;
      }

      if (now.difference(transferTimeSign).inMinutes >= 3) {
        transferWhenTime = now;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    bus.off("update_category", _updateCategory);
    bus.off("update_account", _updateAccount);
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
        body: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: getTabBarPages(),
        ),
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

  incomeAccountQuickSelect(item) {
    setState(() {
      showIncomeAccount = item["name"];
      incomeAccountId = item["id"];
    });
  }

  incomeCategoryQuickSelect(item) {
    setState(() {
      showIncomeCategory = item["category"];
      selectedIncomeCategory = findElementIndexes(
        incomeCategory,
        item["category"],
      );
      incomeCategoryId = item["id"];
    });
  }

  //支出，收入，转账分别的页面。
  //支出
  Widget consume() {
    return Column(
      children: [
        Expanded(
          child: QuickSelect(
            flow: Transaction.consume.value,
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
              time: consumeWhenTime,
              accountText: showConsumeAccount,
              accountId: consumeAccountId,
              categoryText: showConsumeCategory,
              categoryId: consumeCategoryId,
              selectedCategory: selectedConsumeCategory,
              onTimeChanged: (time) {
                setState(() {
                  consumeWhenTime = time;
                });
                consumeTimeSign = DateTime.now();
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
    return Column(
      children: [
        Expanded(
          child: QuickSelect(
            flow: Transaction.income.value,
            accountQuickSelect: incomeAccountQuickSelect,
            categoryQuickSelect: incomeCategoryQuickSelect,
          ),
        ),
        Stack(
          children: [
            Transactions(
              flow: Transaction.income,
              accountNames: accountName,
              accountIndexs: accountIndex,
              categoryIndex: incomeCategoryIndex,
              categories: incomeCategory,
              time: incomeWhenTime,
              accountText: showIncomeAccount,
              accountId: incomeAccountId,
              categoryText: showIncomeCategory,
              categoryId: incomeCategoryId,
              selectedCategory: selectedIncomeCategory,
              onTimeChanged: (time) {
                setState(() {
                  incomeWhenTime = time;
                });
                incomeTimeSign = DateTime.now();
              },
            ),
          ],
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
          child: TransferForm(
            accountNames: accountName,
            accountIndexs: accountIndex,
            time: transferWhenTime,
            outAccountText: showTransferAccount,
            outAccountId: transferAccountId,
            inAccountText: showTransferAimAccount,
            inAccountId: transferAimAccountId,
            clearAfterSubmit: true,
            submitButtonText: '添加',
            onTimeChanged: (time) {
              setState(() {
                transferWhenTime = time;
              });
              transferTimeSign = DateTime.now();
            },
            onAccountChanged: (selection) {
              setState(() {
                showTransferAccount = selection.outText;
                transferAccountId = selection.outId;
                showTransferAimAccount = selection.inText;
                transferAimAccountId = selection.inId;
              });
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
