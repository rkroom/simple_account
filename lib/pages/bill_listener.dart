import 'package:flutter/material.dart';

import '../tools/bill_listener_service.dart';
import '../tools/event_bus.dart';
import '../tools/tools.dart';
import '../tools/config_enum.dart';
import '../widgets/transactions.dart';
import '../widgets/quick_select.dart';

class BillListenerWidget extends StatefulWidget {
  const BillListenerWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return BillListenerWidgetState();
  }
}

class BillListenerWidgetState extends State<BillListenerWidget>
    with WidgetsBindingObserver {
  List notifications = [];
  List accounts = [];
  List categories = [];

  void initData() async {
    // 初始化账户信息
    final results = await Future.wait([
      getAccount(),
      getCategory(Transaction.consume.value),
    ]);
    accounts = results[0];
    categories = results[1];
    notifications = await BillListenerService().getBills();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initData();
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    // 重新回到应用时检测
    // 仅处理 resumed 状态
    if (state == AppLifecycleState.resumed) {
      BillListenerService().getBills().then((value) {
        if (notifications != value) {
          setState(() {
            notifications = value;
          });
        }
      });
    }
  }

  void _clearNotifications() async {
    await BillListenerService().clearBillListenerBox();
    setState(() {
      notifications = [];
    });
  }

  void _accountQuickSelect(dynamic item) {
    if (notifications.isEmpty) return;
    setState(() {
      notifications[0].accountText = item["name"];
      notifications[0].account = item["id"];
    });
  }

  void _categoryQuickSelect(dynamic item) {
    if (notifications.isEmpty) return;
    setState(() {
      notifications[0].selectedCategory = findElementIndexes(
        categories[0],
        item['category'],
      );
      notifications[0].categoryText = item['category'];
      notifications[0].categoryId = item["id"];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              if (notifications.isEmpty) return;
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('确认操作'),
                    content: const Text('确定要清空所有记录吗？'),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('取消'),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                      TextButton(
                        child: const Text('确定'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _clearNotifications();
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: QuickSelect(
              accountQuickSelect: _accountQuickSelect,
              categoryQuickSelect: _categoryQuickSelect,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final billItem = notifications[index];
                return Stack(
                  children: [
                    Transactions(
                      key: ValueKey(billItem.id),
                      amount: billItem.detailed,
                      flow: Transaction.consume,
                      accountNames: accounts[0],
                      accountIndexs: accounts[1],
                      categories: categories[0],
                      categoryIndex: categories[1],
                      time: billItem.time,
                      accountId: billItem.account,
                      accountText: billItem.accountText,
                      selectedCategory: billItem.selectedCategory,
                      categoryText: billItem.categoryText,
                      categoryId: billItem.categoryId,
                      addSuccess: (success) async {
                        if (success) {
                          await BillListenerService().delBill(billItem.id);
                          bus.emit("add_bill_success");
                          setState(() {
                            notifications.removeAt(index);
                          });
                        }
                      },
                      onAmountChanged: (value) {
                        billItem.detailed = value;
                      },
                      onCategoryConfirm: (category) {
                        billItem.selectedCategory = category["selected"];
                        billItem.categoryText = category["text"];
                        billItem.categoryId = category["categoryId"];
                      },
                      onAccountConfirm: (account) {
                        billItem.account = account["accountId"];
                        billItem.accountText = account["text"];
                      },
                      onTimeChanged: (time) {
                        billItem.time = time;
                      },
                    ),
                    Positioned(
                      top: 0.0, // 调整按钮与顶部的距离
                      right: 8.0, // 调整按钮与右侧的距离
                      child: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          await BillListenerService().delBill(billItem.id);
                          setState(() {
                            notifications.removeAt(index);
                          });
                        },
                      ),
                    ),
                    Positioned(
                      bottom: 30.0,
                      right: 12.0,
                      child: Text(
                        billItem.source ?? '',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12.0,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
