import 'package:flutter/material.dart';

import '../tools/db.dart';

class QuickSelect extends StatefulWidget {
  final String flow;
  final void Function(dynamic item) accountQuickSelect;
  final void Function(dynamic item) categoryQuickSelect;

  const QuickSelect({
    super.key,
    this.flow = 'consume',
    required this.accountQuickSelect,
    required this.categoryQuickSelect,
  });

  @override
  State<StatefulWidget> createState() {
    return QuickSelectState();
  }
}

class QuickSelectState extends State<QuickSelect> {
  static const int _fixedItemCount = 6;

  List<Map<String, dynamic>> categoryArray = [];
  List<Map<String, dynamic>> accountArray = [];
  int _loadToken = 0;

  Future<void> initData() async {
    final currentFlow = widget.flow;
    final token = ++_loadToken;

    final results = await Future.wait([
      DB().getMostFrequentType(currentFlow),
      DB().getMostFrequentAccount(currentFlow),
    ]);

    if (!mounted || token != _loadToken || widget.flow != currentFlow) return;

    setState(() {
      categoryArray = List<Map<String, dynamic>>.from(results[0]);
      accountArray = List<Map<String, dynamic>>.from(results[1]);
    });
  }

  @override
  void initState() {
    super.initState();
    initData();
  }

  @override
  void didUpdateWidget(covariant QuickSelect oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.flow != widget.flow) {
      initData();
    }
  }

  Widget _buildPlaceholderButton() {
    return Visibility(
      visible: false,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(fontSize: 13),
        ),
        child: const Text(''),
      ),
    );
  }

  Widget _buildGrid({
    required List<Map<String, dynamic>> items,
    required String textKey,
    required void Function(dynamic item) onPressed,
  }) {
    return GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 8.0,
      mainAxisSpacing: 8.0,
      childAspectRatio: 2,
      children: List.generate(_fixedItemCount, (index) {
        if (index >= items.length) {
          return _buildPlaceholderButton();
        }
        final item = items[index];

        return ElevatedButton(
          onPressed: () => onPressed(item),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: Text(
            '${item[textKey] ?? ''}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _buildGrid(
            items: categoryArray,
            textKey: 'category',
            onPressed: widget.categoryQuickSelect,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          child: Divider(height: 1, thickness: 1, color: Colors.black26),
        ),
        Expanded(
          child: _buildGrid(
            items: accountArray,
            textKey: 'name',
            onPressed: widget.accountQuickSelect,
          ),
        ),
      ],
    );
  }
}
