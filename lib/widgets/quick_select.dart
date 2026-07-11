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

  double _gridVisibleContentHeight({
    required double width,
    required int itemCount,
  }) {
    if (itemCount <= 0) return 0;

    const double hPad = 6.0;
    const double crossAxisSpacing = 8.0;
    const double mainAxisSpacing = 8.0;
    const int crossAxisCount = 3;
    const double childAspectRatio = 2.0;

    final int visibleCount = itemCount.clamp(0, _fixedItemCount);
    final int rows = (visibleCount / crossAxisCount).ceil();

    final double itemWidth =
        (width - 2 * hPad - (crossAxisCount - 1) * crossAxisSpacing) /
        crossAxisCount;

    final double itemHeight = itemWidth / childAspectRatio;

    return rows * itemHeight + (rows - 1) * mainAxisSpacing;
  }

  @override
  Widget build(BuildContext context) {
    final bool showDivider =
        categoryArray.isNotEmpty && accountArray.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;

        const double dividerHeight = 1.0;

        final double topAreaHeight = height / 2;

        final double categoryContentHeight = _gridVisibleContentHeight(
          width: width,
          itemCount: categoryArray.length,
        );

        final double topContentBottom = categoryContentHeight;
        final double bottomContentTop = topAreaHeight;

        final double gap = bottomContentTop - topContentBottom;

        final double dividerTop = topContentBottom + (gap - dividerHeight) / 2;

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

            if (showDivider && gap >= dividerHeight)
              Positioned(
                left: 6,
                right: 6,
                top: dividerTop,
                child: const IgnorePointer(
                  child: Divider(
                    height: dividerHeight,
                    thickness: dividerHeight,
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
