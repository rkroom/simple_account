import 'package:flutter/material.dart';

import '../tools/db.dart';

double? calculateQuickSelectDividerTop({
  required double width,
  required double height,
  required int categoryItemCount,
  required int accountItemCount,
}) {
  if (categoryItemCount <= 0 || accountItemCount <= 0) return null;

  const hPad = 6.0;
  const crossAxisSpacing = 8.0;
  const mainAxisSpacing = 8.0;
  const crossAxisCount = 3;
  const childAspectRatio = 2.0;
  const fixedItemCount = 6;
  const dividerHeight = 1.0;

  final visibleCount = categoryItemCount.clamp(0, fixedItemCount);
  final rows = (visibleCount / crossAxisCount).ceil();
  final itemWidth =
      (width - 2 * hPad - (crossAxisCount - 1) * crossAxisSpacing) /
      crossAxisCount;
  final itemHeight = itemWidth / childAspectRatio;
  final categoryContentHeight =
      rows * itemHeight + (rows - 1) * mainAxisSpacing;
  final gap = height / 2 - categoryContentHeight;
  if (gap < dividerHeight) return null;

  return categoryContentHeight + (gap - dividerHeight) / 2;
}

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final dividerTop = calculateQuickSelectDividerTop(
          width: width,
          height: height,
          categoryItemCount: categoryArray.length,
          accountItemCount: accountArray.length,
        );

        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _buildGrid(
                    items: categoryArray,
                    textKey: 'category',
                    onPressed: widget.categoryQuickSelect,
                  ),
                ),
                Expanded(
                  child: _buildGrid(
                    items: accountArray,
                    textKey: 'name',
                    onPressed: widget.accountQuickSelect,
                  ),
                ),
              ],
            ),

            if (dividerTop != null)
              Positioned(
                left: 6,
                right: 6,
                top: dividerTop,
                child: const IgnorePointer(
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.black26,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
