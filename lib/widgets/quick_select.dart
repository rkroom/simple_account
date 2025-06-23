import 'package:flutter/material.dart';

import '../tools/db.dart';

class QuickSelect extends StatefulWidget {
  final void Function(dynamic item) accountQuickSelect;
  final void Function(dynamic item) categoryQuickSelect;

  const QuickSelect({
    super.key,
    required this.accountQuickSelect,
    required this.categoryQuickSelect,
  });

  @override
  State<StatefulWidget> createState() {
    return QuickSelectState();
  }
}

class QuickSelectState extends State<QuickSelect> {
  List<Map<String, dynamic>> categoryArray = [];
  List<Map<String, dynamic>> accountArray = [];

  void initData() async {
    final results = await Future.wait([
      DB().getMostFrequentType("consume"),
      DB().getMostFrequentAccount("consume"),
    ]);
    categoryArray = results[0] as List<Map<String, dynamic>>;
    accountArray = results[1];
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    initData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GridView.count(
            crossAxisCount: 3, // 每行的按钮数量，可以调整为你需要的数量
            crossAxisSpacing: 8.0, // 横向间距
            mainAxisSpacing: 8.0, // 纵向间距
            childAspectRatio: 2, // 宽高比
            children:
                categoryArray.map((item) {
                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 3.0,
                      vertical: 5.0,
                    ), // 添加间距
                    child: ElevatedButton(
                      onPressed: () {
                        widget.categoryQuickSelect(item);
                      },
                      child: Text(' ${item['category']}'),
                    ),
                  );
                }).toList(),
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3, // 每行的按钮数量，可以调整为你需要的数量
            crossAxisSpacing: 8.0, // 横向间距
            mainAxisSpacing: 8.0, // 纵向间距
            childAspectRatio: 2, // 宽高比
            children:
                accountArray.map((item) {
                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 3.0,
                      vertical: 5.0,
                    ), // 添加间距
                    child: ElevatedButton(
                      onPressed: () {
                        widget.accountQuickSelect(item);
                      },
                      child: Text(' ${item['name']}'),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }
}
