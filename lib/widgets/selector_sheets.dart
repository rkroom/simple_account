import 'dart:math' as math;

import 'package:flutter/material.dart';

class SelectorOption<T> {
  final String label;
  final T value;

  const SelectorOption({required this.label, required this.value});
}

class SelectorGroup<T> {
  final String label;
  final List<SelectorOption<T>> children;

  const SelectorGroup({required this.label, required this.children});
}

class GridSelectorResult<T> {
  final int index;
  final SelectorOption<T> option;

  const GridSelectorResult({required this.index, required this.option});

  Map<String, dynamic> toMap({
    String textKey = "text",
    String valueKey = "value",
  }) {
    return {textKey: option.label, valueKey: option.value};
  }
}

class CascadeSelectorResult<T> {
  final int parentIndex;
  final int childIndex;
  final String parentLabel;
  final SelectorOption<T> option;

  const CascadeSelectorResult({
    required this.parentIndex,
    required this.childIndex,
    required this.parentLabel,
    required this.option,
  });

  String get text => "$parentLabel / ${option.label}";

  Map<String, dynamic> toMap({
    String selectedKey = "selected",
    String textKey = "text",
    String valueKey = "value",
  }) {
    return {
      selectedKey: [parentIndex, childIndex],
      textKey: text,
      valueKey: option.value,
    };
  }
}

/// 兼容你当前 categories + categoryIndex 的结构
List<SelectorGroup<int?>> buildCategorySelectorGroups(
  List source,
  Map categoryIndex,
) {
  final List<SelectorGroup<int?>> groups = [];

  for (final item in source) {
    if (item is Map && item.isNotEmpty) {
      final entry = item.entries.first;
      final parentName = entry.key.toString();
      final value = entry.value;

      final children = <SelectorOption<int?>>[];

      if (value is List) {
        for (final child in value) {
          final childName = child.toString();
          children.add(
            SelectorOption<int?>(
              label: childName,
              value: categoryIndex[childName] as int?,
            ),
          );
        }
      }

      groups.add(SelectorGroup<int?>(label: parentName, children: children));
    }
  }

  return groups;
}

/// 兼容你当前 accountNames + accountIndexs 的结构
List<SelectorOption<int?>> buildAccountSelectorOptions(
  List source,
  Map accountIndex,
) {
  return source
      .map(
        (e) => SelectorOption<int?>(
          label: e.toString(),
          value: accountIndex[e.toString()] as int?,
        ),
      )
      .toList();
}

Future<GridSelectorResult<T>?> showGridSelectorSheet<T>({
  required BuildContext context,
  required List<SelectorOption<T>> options,
  String title = "请选择",
  int? initialSelectedIndex,
}) {
  return showModalBottomSheet<GridSelectorResult<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return GridSelectorSheet<T>(
        title: title,
        options: options,
        initialSelectedIndex: initialSelectedIndex,
      );
    },
  );
}

Future<CascadeSelectorResult<T>?> showCascadeSelectorSheet<T>({
  required BuildContext context,
  required List<SelectorGroup<T>> groups,
  String title = "请选择",
  List<int>? initialSelected,
}) {
  return showModalBottomSheet<CascadeSelectorResult<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return CascadeSelectorSheet<T>(
        title: title,
        groups: groups,
        selected: initialSelected,
      );
    },
  );
}

/// 选择器按钮文字：根据可用宽度动态缩小字号。
///
/// 最大字号采用当前 DefaultTextStyle / Theme 的默认字号，不固定写死。
/// 文字过长时自动缩小到 _minFontSize。
/// 如果缩小到 _minFontSize 后仍然放不下，才显示省略号。
class AdaptiveSelectorLabel extends StatelessWidget {
  static const double _minFontSize = 10;

  final String text;
  final bool selected;

  const AdaptiveSelectorLabel({
    super.key,
    required this.text,
    required this.selected,
  });

  double _measureTextWidth({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required double fontSize,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: double.infinity);

    return painter.width;
  }

  double _calculateFontSize({
    required BuildContext context,
    required double maxWidth,
    required TextStyle style,
    required double maxFontSize,
  }) {
    if (maxWidth <= 0 || maxWidth.isInfinite) {
      return maxFontSize;
    }

    final maxTextWidth = _measureTextWidth(
      context: context,
      text: text,
      style: style,
      fontSize: maxFontSize,
    );

    if (maxTextWidth <= maxWidth) {
      return maxFontSize;
    }

    double low = _minFontSize;
    double high = maxFontSize;

    for (int i = 0; i < 8; i++) {
      final mid = (low + high) / 2;
      final width = _measureTextWidth(
        context: context,
        text: text,
        style: style,
        fontSize: mid,
      );

      if (width <= maxWidth) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return low;
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;

    final maxFontSize =
        defaultStyle.fontSize ??
        Theme.of(context).textTheme.bodyMedium?.fontSize ??
        14;

    final baseStyle = defaultStyle.copyWith(
      color: selected ? Colors.white : Colors.black87,
      fontWeight: FontWeight.w500,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = _calculateFontSize(
          context: context,
          maxWidth: constraints.maxWidth,
          style: baseStyle,
          maxFontSize: maxFontSize,
        );

        return Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: baseStyle.copyWith(fontSize: fontSize),
        );
      },
    );
  }
}

class GridSelectorSheet<T> extends StatefulWidget {
  final String title;
  final List<SelectorOption<T>> options;
  final int? initialSelectedIndex;

  const GridSelectorSheet({
    super.key,
    required this.title,
    required this.options,
    this.initialSelectedIndex,
  });

  @override
  State<GridSelectorSheet<T>> createState() => _GridSelectorSheetState<T>();
}

class _GridSelectorSheetState<T> extends State<GridSelectorSheet<T>> {
  static const Duration _heightAnimDuration = Duration(milliseconds: 220);
  static const Curve _heightAnimCurve = Curves.easeOut;

  static const int _crossAxisCount = 3;
  static const double _mainAxisSpacing = 12;
  static const double _crossAxisSpacing = 12;
  static const double _childAspectRatio = 2.5;

  static const double _horizontalPadding = 16;
  static const double _verticalPadding = 16;
  static const double _scrollbarReservedWidth = 12;

  static const double _headerHeight = 58;
  static const double _dividerHeight = 1;
  static const double _sheetMaxHeightRatio = 0.70;

  late int selectedIndex;
  final ScrollController _gridScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    if (widget.options.isEmpty) {
      selectedIndex = 0;
      return;
    }

    final initIndex = widget.initialSelectedIndex ?? 0;
    selectedIndex =
        (initIndex >= 0 && initIndex < widget.options.length) ? initIndex : 0;
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  void _confirmCurrent() {
    if (widget.options.isEmpty) return;

    Navigator.pop(
      context,
      GridSelectorResult<T>(
        index: selectedIndex,
        option: widget.options[selectedIndex],
      ),
    );
  }

  void _confirmSelection(int index) {
    if (index < 0 || index >= widget.options.length) return;

    selectedIndex = index;
    _confirmCurrent();
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

  _GridSheetLayout _measureLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height * _sheetMaxHeightRatio;
    final gridWidth = media.size.width - (_horizontalPadding * 2);

    final gridHeight = _calculateGridHeight(
      availableWidth: gridWidth,
      itemCount: widget.options.length,
    );

    final bodyDesiredHeight = _verticalPadding + gridHeight + _verticalPadding;

    final sheetDesiredHeight =
        _headerHeight +
        _dividerHeight +
        bodyDesiredHeight +
        media.padding.bottom;

    if (sheetDesiredHeight <= maxSheetHeight) {
      return _GridSheetLayout(
        sheetHeight: sheetDesiredHeight,
        bodyHeight: bodyDesiredHeight,
        gridScrollable: false,
      );
    }

    final sheetHeight = maxSheetHeight;
    final bodyHeight = math.max(
      0.0,
      sheetHeight - _headerHeight - _dividerHeight - media.padding.bottom,
    );

    return _GridSheetLayout(
      sheetHeight: sheetHeight,
      bodyHeight: bodyHeight,
      gridScrollable: bodyDesiredHeight > bodyHeight + 0.5,
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
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          widget.options.isEmpty ? null : _confirmCurrent,
                      child: const Text("确认"),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: _dividerHeight, thickness: _dividerHeight),
            AnimatedContainer(
              duration: _heightAnimDuration,
              curve: _heightAnimCurve,
              height: layout.bodyHeight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child:
                    widget.options.isEmpty
                        ? const Center(child: Text("暂无数据"))
                        : Scrollbar(
                          controller: _gridScrollController,
                          thumbVisibility: layout.gridScrollable,
                          trackVisibility: layout.gridScrollable,
                          interactive: true,
                          radius: const Radius.circular(8),
                          child: GridView.builder(
                            controller: _gridScrollController,
                            padding:
                                layout.gridScrollable
                                    ? const EdgeInsets.only(
                                      right: _scrollbarReservedWidth,
                                    )
                                    : EdgeInsets.zero,
                            shrinkWrap: !layout.gridScrollable,
                            physics:
                                layout.gridScrollable
                                    ? const BouncingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                            itemCount: widget.options.length,
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
                                onTap: () {
                                  setState(() {
                                    selectedIndex = index;
                                  });
                                  _confirmSelection(index);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color:
                                        selected
                                            ? Colors.blue
                                            : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          selected
                                              ? Colors.blue
                                              : Colors.grey.shade300,
                                      width: 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: AdaptiveSelectorLabel(
                                      text: widget.options[index].label,
                                      selected: selected,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CascadeSelectorSheet<T> extends StatefulWidget {
  final String title;
  final List<SelectorGroup<T>> groups;
  final List<int>? selected;

  const CascadeSelectorSheet({
    super.key,
    required this.title,
    required this.groups,
    this.selected,
  });

  @override
  State<CascadeSelectorSheet<T>> createState() =>
      _CascadeSelectorSheetState<T>();
}

class _CascadeSelectorSheetState<T> extends State<CascadeSelectorSheet<T>> {
  static const Duration _heightAnimDuration = Duration(milliseconds: 220);
  static const Curve _heightAnimCurve = Curves.easeOut;

  static const int _crossAxisCount = 3;
  static const double _mainAxisSpacing = 12;
  static const double _crossAxisSpacing = 12;
  static const double _childAspectRatio = 2.5;

  static const double _horizontalPadding = 16;
  static const double _parentTopPadding = 16;
  static const double _parentBottomPadding = 8;
  static const double _childVerticalPadding = 16;
  static const double _scrollbarReservedWidth = 12;

  static const double _headerHeight = 58;
  static const double _dividerHeight = 1;
  static const double _sheetMaxHeightRatio = 0.75;

  static const double _maxParentWhenOverflowRatio = 0.38;
  static const double _minVisibleSectionHeight = 96;

  late int parentIndex;
  late int childIndex;

  final ScrollController _parentScrollController = ScrollController();
  final ScrollController _childScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    parentIndex = 0;
    childIndex = 0;

    if (widget.selected != null && widget.selected!.length >= 2) {
      final p = widget.selected![0];
      final c = widget.selected![1];

      if (p >= 0 && p < widget.groups.length) {
        parentIndex = p;

        if (c >= 0 && c < widget.groups[parentIndex].children.length) {
          childIndex = c;
        }
      }
    }
  }

  @override
  void dispose() {
    _parentScrollController.dispose();
    _childScrollController.dispose();
    super.dispose();
  }

  List<SelectorOption<T>> get currentChildren =>
      widget.groups.isEmpty ? const [] : widget.groups[parentIndex].children;

  void _confirmCurrentChild() {
    if (currentChildren.isEmpty) return;

    Navigator.pop(
      context,
      CascadeSelectorResult<T>(
        parentIndex: parentIndex,
        childIndex: childIndex,
        parentLabel: widget.groups[parentIndex].label,
        option: currentChildren[childIndex],
      ),
    );
  }

  void _confirmChildSelection(int index) {
    if (index < 0 || index >= currentChildren.length) return;

    childIndex = index;
    _confirmCurrentChild();
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

  _CascadeSheetLayout _measureLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height * _sheetMaxHeightRatio;
    final gridWidth = media.size.width - (_horizontalPadding * 2);

    final parentGridHeight = _calculateGridHeight(
      availableWidth: gridWidth,
      itemCount: widget.groups.length,
    );

    final childGridHeight =
        currentChildren.isEmpty
            ? 28
            : _calculateGridHeight(
              availableWidth: gridWidth,
              itemCount: currentChildren.length,
            );

    final parentDesiredHeight =
        _parentTopPadding + parentGridHeight + _parentBottomPadding;

    final childDesiredHeight =
        _childVerticalPadding + childGridHeight + _childVerticalPadding;

    final baseHeight =
        _headerHeight + _dividerHeight + _dividerHeight + media.padding.bottom;

    final desiredSheetHeight =
        baseHeight + parentDesiredHeight + childDesiredHeight;

    if (desiredSheetHeight <= maxSheetHeight) {
      return _CascadeSheetLayout(
        sheetHeight: desiredSheetHeight,
        parentHeight: parentDesiredHeight,
        childHeight: childDesiredHeight,
        parentScrollable: false,
        childScrollable: false,
      );
    }

    final sheetHeight = maxSheetHeight;
    final contentHeight = sheetHeight - baseHeight;

    double parentHeight =
        math
            .min(parentDesiredHeight, sheetHeight * _maxParentWhenOverflowRatio)
            .toDouble();

    double childHeight = math.max(0.0, contentHeight - parentHeight);

    if (childHeight < _minVisibleSectionHeight) {
      final lack = _minVisibleSectionHeight - childHeight;
      parentHeight = math.max(0.0, parentHeight - lack);
      childHeight = math.max(0.0, contentHeight - parentHeight);
    }

    return _CascadeSheetLayout(
      sheetHeight: sheetHeight,
      parentHeight: parentHeight,
      childHeight: childHeight,
      parentScrollable: parentDesiredHeight > parentHeight + 0.5,
      childScrollable: childDesiredHeight > childHeight + 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return Container(
        height: 220,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const SafeArea(top: false, child: Center(child: Text("暂无数据"))),
      );
    }

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
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          currentChildren.isEmpty ? null : _confirmCurrentChild,
                      child: const Text("确认"),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: _dividerHeight, thickness: _dividerHeight),
            AnimatedContainer(
              duration: _heightAnimDuration,
              curve: _heightAnimCurve,
              height: layout.parentHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  _horizontalPadding,
                  _parentTopPadding,
                  _horizontalPadding,
                  _parentBottomPadding,
                ),
                child: Scrollbar(
                  controller: _parentScrollController,
                  thumbVisibility: layout.parentScrollable,
                  trackVisibility: layout.parentScrollable,
                  interactive: true,
                  radius: const Radius.circular(8),
                  child: GridView.builder(
                    controller: _parentScrollController,
                    padding:
                        layout.parentScrollable
                            ? const EdgeInsets.only(
                              right: _scrollbarReservedWidth,
                            )
                            : EdgeInsets.zero,
                    shrinkWrap: !layout.parentScrollable,
                    physics:
                        layout.parentScrollable
                            ? const BouncingScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                    itemCount: widget.groups.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _crossAxisCount,
                          mainAxisSpacing: _mainAxisSpacing,
                          crossAxisSpacing: _crossAxisSpacing,
                          childAspectRatio: _childAspectRatio,
                        ),
                    itemBuilder: (context, index) {
                      final isSelected = index == parentIndex;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            parentIndex = index;
                            childIndex = 0;
                          });

                          if (_childScrollController.hasClients) {
                            _childScrollController.jumpTo(0);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                isSelected ? Colors.blue : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  isSelected
                                      ? Colors.blue
                                      : Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: AdaptiveSelectorLabel(
                              text: widget.groups[index].label,
                              selected: isSelected,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(height: 1, color: Colors.grey.shade300),
            ),
            AnimatedContainer(
              duration: _heightAnimDuration,
              curve: _heightAnimCurve,
              height: layout.childHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  _horizontalPadding,
                  _childVerticalPadding,
                  _horizontalPadding,
                  _childVerticalPadding,
                ),
                child:
                    currentChildren.isEmpty
                        ? const Center(child: Text("暂无子类目"))
                        : Scrollbar(
                          controller: _childScrollController,
                          thumbVisibility: layout.childScrollable,
                          trackVisibility: layout.childScrollable,
                          interactive: true,
                          radius: const Radius.circular(8),
                          child: GridView.builder(
                            controller: _childScrollController,
                            padding:
                                layout.childScrollable
                                    ? const EdgeInsets.only(
                                      right: _scrollbarReservedWidth,
                                    )
                                    : EdgeInsets.zero,
                            shrinkWrap: !layout.childScrollable,
                            physics:
                                layout.childScrollable
                                    ? const BouncingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                            itemCount: currentChildren.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _crossAxisCount,
                                  mainAxisSpacing: _mainAxisSpacing,
                                  crossAxisSpacing: _crossAxisSpacing,
                                  childAspectRatio: _childAspectRatio,
                                ),
                            itemBuilder: (context, index) {
                              final isSelected = index == childIndex;

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    childIndex = index;
                                  });
                                  _confirmChildSelection(index);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? Colors.blue
                                            : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? Colors.blue
                                              : Colors.grey.shade300,
                                      width: 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: AdaptiveSelectorLabel(
                                      text: currentChildren[index].label,
                                      selected: isSelected,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridSheetLayout {
  final double sheetHeight;
  final double bodyHeight;
  final bool gridScrollable;

  const _GridSheetLayout({
    required this.sheetHeight,
    required this.bodyHeight,
    required this.gridScrollable,
  });
}

class _CascadeSheetLayout {
  final double sheetHeight;
  final double parentHeight;
  final double childHeight;
  final bool parentScrollable;
  final bool childScrollable;

  const _CascadeSheetLayout({
    required this.sheetHeight,
    required this.parentHeight,
    required this.childHeight,
    required this.parentScrollable,
    required this.childScrollable,
  });
}
