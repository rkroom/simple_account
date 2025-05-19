import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';
import 'package:flutter_picker_plus/flutter_picker_plus.dart';

import '../tools/db.dart';
import '../tools/event_bus.dart';
import '../tools/native_method_channel.dart';
import '../tools/tools.dart';
import '../tools/config_enum.dart';
import '../widgets/quick_select.dart';
import '../widgets/transactions.dart';

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
  //List<int>? selectedIncomeCategory;
  String showIncomeCategory = "请选择";
  Map incomeCategoryIndex = {};
  int? incomeCategoryId;

  // 转账功能变量
  String showTransferAccount = "请选择";
  late int transferAccountId;
  String showTransferAimAccount = "请选择";
  late int transferAimAccountId;
  final TextEditingController _transferAmountController =
      TextEditingController();
  final TextEditingController _transferCommentController =
      TextEditingController();
  // 账户信息功能
  List accountName = [];
  Map accountIndex = {};
  //Map accountType = {};

  //添加标志变量，当whenTime修改后一定时间内，应用从后台恢复到前台不修改whenTime
  DateTime timeSign = DateTime.now();

  void initData() async {
    // 使用 Future.wait 并行执行所有异步任务
    var results = await Future.wait([
      getCategory("consume"), // 获取消费分类
      getCategory("income"), // 获取收入分类
      getAccount(), // 获取账户信息
    ]);

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
      // accountType = results[2][2];
    });
  }

  Future<void> _checkPermissions() async {
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasPermission = false;
        });
      }
    }
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

    bus.on("update_account", (arg) {
      getAccount().then((list) {
        setState(() {
          accountName = list[0];
          accountIndex = list[1];
          //accountType = list[2];
        });
      });
    });
    _checkPermissions();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 仅处理 resumed 状态
    if (state != AppLifecycleState.resumed) {
      return;
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
    super.dispose();
    bus.off("update_category");
    bus.off("update_account");
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
                  child: IconButton(
                    icon: Icon(
                      size: 35.0,
                      Icons.article,
                      color: Colors.blue[600],
                    ),
                    onPressed: () {
                      Navigator.of(context).pushNamed('/billListener');
                    },
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
    // todo 将其抽离为组件
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
                      // 只允许输入数字和小数
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
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
                  onTap: () {
                    // 转出账户类别
                    Picker(
                      confirmText: "确认",
                      cancelText: "取消",
                      adapter: PickerDataAdapter<String>(
                        pickerData: accountName,
                      ),
                      hideHeader: false,
                      onConfirm: (Picker picker, List value) {
                        setState(() {
                          showTransferAccount = picker.adapter.text;
                          transferAccountId =
                              accountIndex[picker.adapter
                                  .getSelectedValues()[0]];
                        });
                      },
                    ).showModal(context);
                  },
                  child: Text(
                    "转出账户：$showTransferAccount",
                    textScaler: customTextScaler,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(5),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // 转入账户类别
                    Picker(
                      confirmText: "确认",
                      cancelText: "取消",
                      adapter: PickerDataAdapter<String>(
                        pickerData: accountName,
                      ),
                      hideHeader: false,
                      onConfirm: (Picker picker, List value) {
                        setState(() {
                          showTransferAimAccount = picker.adapter.text;
                          transferAimAccountId =
                              accountIndex[picker.adapter
                                  .getSelectedValues()[0]];
                        });
                      },
                    ).showModal(context);
                  },
                  child: Text(
                    "转入账户：$showTransferAimAccount",
                    textScaler: customTextScaler,
                  ),
                ),
              ),
              // 手势检测器
              Padding(
                padding: const EdgeInsets.all(5),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // 当单击时
                  onTap: () {
                    // 日期时间选择器
                    DatePicker.showDateTimePicker(
                      context,
                      showTitleActions: true,
                      onConfirm: (date) {
                        setState(() {
                          whenTime = date;
                        });
                        timeSign = DateTime.now();
                      },
                      // 当前时间
                      currentTime: whenTime,
                      // 语言
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
                    child: TextField(
                      // 通过controller可以调用用户输入的数据
                      controller: _transferCommentController,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                child: const Text("添加"),
                // 点击按钮事件
                onPressed: () async {
                  if (_transferAmountController.text.isEmpty) {
                    showNoticeSnackBar(context, "金额不能为空");
                    return;
                  }
                  try {
                    DB().addTransfer(
                      _transferAmountController.text,
                      transferAccountId,
                      transferAimAccountId,
                      _transferCommentController.text,
                      whenTime.toString(),
                    );
                    //FocusScope.of(context).unfocus();
                    _transferAmountController.clear();
                    _transferCommentController.clear();
                  } catch (error) {
                    //print(error);
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
