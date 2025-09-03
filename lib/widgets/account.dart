import 'dart:math';

import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:simple_account/widgets/statement.dart';

import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/event_bus.dart';
import '../tools/tools.dart';

class AccountWidget extends StatefulWidget {
  const AccountWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return AccountWidgetState();
  }
}

class AccountWidgetState extends State<AccountWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final tabs = ["统计", "账户"];

  static const _pageSize = 15;
  final TextEditingController _newAccountNameController =
      TextEditingController();

  int? selectedId;

  late final _pagingController = PagingController<int, Map<String, dynamic>>(
    getNextPageKey: (state) {
      if (!state.hasNextPage) return null;
      final keys = state.keys ?? <int>[];
      final pages = state.pages;
      if (pages != null && pages.last.length < _pageSize) return null;
      final nextKey = keys.isEmpty ? 0 : (keys.last + 1);
      return nextKey;
    },
    fetchPage: (pageKey) => _fetchPage(pageKey),
  );

  double totalAssets = 0;
  double totalDebts = 0;
  double currentlyMonthConsume = 0;
  double currentlyMonthIncome = 0;
  double previousMonthConsume = 0;
  double previousMonthIncome = 0;
  double currentlyMonthSummed = 0;
  double previousDayConsume = 0;
  double currentlyDayConsume = 0;

  List<PieChartSectionData> pieChartSections = [];
  List<Map> colorAndName = [];

  void getStatistics() async {
    // 获取时间区间
    var cmd = currentlyMonthDays();
    var pmd = previousMonthDays();
    var today = getTodayRange();
    var previousDay = getPreviousDayRange();

    // 并行执行所有数据库操作
    var results = await Future.wait([
      DB().totalBalance('asset'),
      DB().totalBalance('debt'),
      DB().timeStatistics(Transaction.consume.value, cmd[0], cmd[1]),
      DB().timeStatistics(Transaction.income.value, cmd[0], cmd[1]),
      DB().timeStatistics(Transaction.consume.value, pmd[0], pmd[1]),
      DB().timeStatistics(Transaction.income.value, pmd[0], pmd[1]),
      DB().timeStatistics(Transaction.consume.value, today[0], today[1]),
      DB().timeStatistics(
        Transaction.consume.value,
        previousDay[0],
        previousDay[1],
      ),
    ]);

    if (!mounted) return;

    // 将结果更新到状态变量
    totalAssets = checkDBResult(results[0][0]["balance"]);
    totalDebts = checkDBResult(results[1][0]["balance"]);
    currentlyMonthConsume = checkDBResult(results[2][0]["amount"]);
    currentlyMonthIncome = checkDBResult(results[3][0]["amount"]);
    previousMonthConsume = checkDBResult(results[4][0]["amount"]);
    previousMonthIncome = checkDBResult(results[5][0]["amount"]);
    currentlyDayConsume = checkDBResult(results[6][0]["amount"]);
    previousDayConsume = checkDBResult(results[7][0]["amount"]);
    // 统一调用 setState 更新 UI
    setState(() {});
  }

  Color getRandomColor() {
    Random random = Random();
    return Color.fromARGB(
      100,
      random.nextInt(256),
      random.nextInt(256),
      random.nextInt(256),
    );
  }

  // 转换为字符串并去除尾随零
  String formatNumber(double number) {
    if (number.isInfinite || number.isNaN) return '0';
    if (number % 1 == 0) {
      return number.toInt().toString();
    }
    String s = number.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  void getFirstLevelConsume() {
    var cmd = currentlyMonthDays();
    DB().getFirstLevelConsumeAnalysis(cmd[0], cmd[1]).then((value) {
      final data = List<Map<String, dynamic>>.from(value);

      if (data.isEmpty) {
        setState(() {});
        return;
      }

      double total = data.fold(0.0, (sum, e) => sum + (e['value'] as double));
      if (total == 0) {
        pieChartSections.clear();
        colorAndName.clear();
        setState(() {});
        return;
      }

      List<Map<String, dynamic>> processedData =
          data.map((e) {
            final currentValue = e['value'] as double;
            return {
              'id': e['id'],
              'name': e['name'],
              'value': currentValue,
              'percent': currentValue / total,
            };
          }).toList();

      final largeSlices =
          processedData.where((d) => d['percent'] >= 0.05).toList();
      final smallSlices =
          processedData.where((d) => d['percent'] < 0.05).toList();

      largeSlices.sort(
        (a, b) => (b['value'] as double).compareTo(a['value'] as double),
      );
      smallSlices.sort(
        (a, b) => (b['value'] as double).compareTo(a['value'] as double),
      );

      List<Map<String, dynamic>> interleavedSlices = [];
      int i = 0, j = 0;
      while (i < largeSlices.length || j < smallSlices.length) {
        if (i < largeSlices.length) {
          interleavedSlices.add(largeSlices[i++]);
        }
        if (j < smallSlices.length) {
          interleavedSlices.add(smallSlices[j++]);
        }
      }

      pieChartSections.clear();
      colorAndName.clear();

      for (var e in interleavedSlices) {
        final color = getRandomColor();
        final currentValue = e['value'] as double;
        final percent = e['percent'] as double;

        pieChartSections.add(
          PieChartSectionData(
            color: color,
            value: currentValue,
            title:
                percent < 0.01 ? '' : '${(percent * 100).toStringAsFixed(1)}%',
            radius: 100,
            titleStyle: const TextStyle(fontSize: 12, color: Colors.black),
            titlePositionPercentageOffset: 0.7,
          ),
        );

        colorAndName.add({
          "id": e["id"],
          "color": color,
          "name": "${e["name"]}\n${formatNumber(currentValue)}",
          "amount": currentValue,
          "categoryNameOnly": e["name"],
        });
      }

      colorAndName.sort((a, b) => b['amount'].compareTo(a['amount']));

      setState(() {});
    });
  }

  void _refreshAccount(arg) {
    _pagingController.refresh();
  }

  @override
  void initState() {
    super.initState();
    bus.on("update_account", _refreshAccount);
    getStatistics();
    getFirstLevelConsume();
  }

  listPages() {
    List<Widget> tabPages = [];
    return tabPages
      ..add(statistics())
      ..add(account());
  }

  Widget getTabBarPages() {
    return TabBarView(children: listPages());
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int pageKey) async {
    final offset = pageKey * _pageSize;
    return await DB().getAccountInfo(_pageSize, offset);
  }

  void onItemPressed(Map<String, dynamic> item) {
    setState(() {
      selectedId = (selectedId == item['id']) ? null : item['id'];
    });
  }

  Future<void> _showConfirmationDialog(
    Map<String, dynamic> item,
    int index,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${item['name']}'),
          content: SizedBox(
            height: 100,
            child: Column(
              children: [
                const Text('是否修改账户名称 ?'),
                TextField(
                  controller: _newAccountNameController,
                  decoration: const InputDecoration(labelText: '输入新名称'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final newName = _newAccountNameController.text.trim();
                if (newName.isEmpty) {
                  showNoticeSnackBar(context, "账户名不能为空");
                  return;
                }
                DB().updateAccountName(newName, item['id']);
                _pagingController.mapItems((currentItem) {
                  if (currentItem['id'] == item['id']) {
                    return {...currentItem, 'name': newName};
                  }
                  return currentItem;
                });
                _newAccountNameController.clear();
                Navigator.of(context).pop();
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
            child: Column(children: <Widget>[getTabBar()]),
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

  Widget account() {
    return PagingListener<int, Map<String, dynamic>>(
      controller: _pagingController,
      builder: (context, state, fetchNextPage) {
        return PagedListView<int, Map<String, dynamic>>(
          state: state,
          fetchNextPage: fetchNextPage,
          builderDelegate: PagedChildBuilderDelegate<Map<String, dynamic>>(
            itemBuilder: (context, item, index) {
              return Column(
                children: [
                  ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(child: Text(item['name'])),
                        Expanded(child: Text(item['type'])),
                        Expanded(child: Text(item['balance'].toString())),
                      ],
                    ),
                    //subtitle: Text('ID: ${item['id']}'),
                    onTap: () {
                      onItemPressed(item);
                    },
                  ),
                  if (selectedId == item['id'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              _showConfirmationDialog(item, index);
                            },
                            child: const Text('更名'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => AccountStatementPage(
                                        accountName: item['name'],
                                        accountID: item['id'].toString(),
                                      ),
                                ),
                              );
                            },
                            child: const Text('详情'),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget statistics() {
    double deviceHeight = MediaQuery.of(context).size.height;

    bool hasData =
        totalAssets != 0.0 ||
        totalDebts != 0.0 ||
        currentlyMonthConsume != 0.0 ||
        currentlyMonthIncome != 0.0 ||
        previousMonthConsume != 0.0 ||
        previousMonthIncome != 0.0 ||
        currentlyDayConsume != 0.0 ||
        previousDayConsume != 0.0 ||
        pieChartSections.isNotEmpty;

    if (!hasData) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 50, color: Colors.grey),
            SizedBox(height: 10),
            Text("暂无可展示数据", style: TextStyle(fontSize: 18, color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Wrap(
          spacing: 5.0, // 水平方向的间距
          runSpacing: 2.0, // 垂直方向的间距
          children: [
            if (totalAssets != 0.0) Text("总资产： $totalAssets"),
            if (totalDebts != 0.0) Text("总负债： ${0 - totalDebts}"),
            if ((totalAssets + totalDebts) != 0.0)
              Text("净资产： ${(totalAssets + totalDebts).toStringAsFixed(2)}"),
            if (previousMonthConsume != 0.0)
              Text("上月支出： $previousMonthConsume"),
            if (previousMonthIncome != 0.0) Text("上月收支： $previousMonthIncome"),
            if (currentlyMonthConsume != 0.0)
              Text("本月支出： $currentlyMonthConsume"),
            if (currentlyMonthIncome != 0.0)
              Text("本月收入： $currentlyMonthIncome"),
            if ((currentlyMonthIncome - currentlyMonthConsume) != 0.0)
              Text(
                "本月总计： ${(currentlyMonthIncome - currentlyMonthConsume).toStringAsFixed(2)}",
              ),
            if (previousDayConsume != 0.0) Text("昨日支出： $previousDayConsume"),
            if (currentlyDayConsume != 0.0) Text("今日支出： $currentlyDayConsume"),
          ],
        ),
        SizedBox(
          height: deviceHeight * 0.37,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 0,
              sections: pieChartSections,
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  if (event is FlTapUpEvent) {
                    final touchedIndex =
                        pieTouchResponse?.touchedSection?.touchedSectionIndex ??
                        -1;
                    if (touchedIndex >= 0) {
                      Navigator.pushNamed(context, "/statistic");
                    }
                  }
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5.0),
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 8.0,
              mainAxisSpacing: 8.0,
              childAspectRatio: 2.5,
              children: List.generate(colorAndName.length, (index) {
                return GestureDetector(
                  onTap: () {
                    final item = colorAndName[index];
                    final categoryId = item['id'].toString();
                    final categoryName = item['categoryNameOnly'];
                    var cmd = currentlyMonthDays();
                    final DateTime startTime = DateTime.parse(cmd[0]);
                    final DateTime endTime = DateTime.parse(cmd[1]);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => CategoryDetailsPage(
                              startTime: startTime,
                              endTime: endTime,
                              categoryId: categoryId,
                              categoryName: categoryName,
                            ),
                      ),
                    );
                  },
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(1.0),
                    decoration: BoxDecoration(
                      color: colorAndName[index]["color"],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      colorAndName[index]["name"],
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    bus.off("update_account", _refreshAccount);
    _newAccountNameController.dispose();
    _pagingController.dispose();
    super.dispose();
  }
}

class CategoryDetailsPage extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;
  final String categoryId;
  final String categoryName;

  const CategoryDetailsPage({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  Widget build(BuildContext context) {
    final String appBarTitle =
        '$categoryName-${startTime.year}年${startTime.month}月';
    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: StatementWidget(
        startTime: startTime,
        endTime: endTime,
        firstLevelCategoryParam: categoryId,
        flowParam: 'consume',
      ),
    );
  }
}

class AccountStatementPage extends StatelessWidget {
  final String accountName;
  final String accountID;

  const AccountStatementPage({
    super.key,
    required this.accountName,
    required this.accountID,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("$accountName-账单")),
      body: StatementWidget(accountParam: accountID),
    );
  }
}
