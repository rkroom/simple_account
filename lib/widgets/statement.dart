import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:simple_account/tools/tools.dart';

import '../tools/db.dart';
import '../tools/event_bus.dart';

class StatementWidget extends StatefulWidget {
  final DateTime? startTime;
  final DateTime? endTime;
  final String? accountParam;
  final String? categoryParam;
  final String? firstLevelCategoryParam;
  final String? flowParam;
  final bool isShrinkWrapped;

  const StatementWidget({
    super.key,
    this.startTime,
    this.endTime,
    this.accountParam,
    this.categoryParam,
    this.firstLevelCategoryParam,
    this.flowParam,
    this.isShrinkWrapped = false,
  });

  @override
  State<StatefulWidget> createState() {
    return StatementWidgetState();
  }
}

class StatementWidgetState extends State<StatementWidget> {
  static const _pageSize = 13;

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

  @override
  void initState() {
    super.initState();
    bus.on("add_bill_success", (arg) {
      _pagingController.refresh();
    });
  }

  @override
  void didUpdateWidget(StatementWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startTime != oldWidget.startTime ||
        widget.endTime != oldWidget.endTime ||
        widget.accountParam != oldWidget.accountParam ||
        widget.categoryParam != oldWidget.categoryParam ||
        widget.firstLevelCategoryParam != oldWidget.firstLevelCategoryParam ||
        widget.flowParam != oldWidget.flowParam) {
      _pagingController.refresh();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int pageKey) async {
    return DB().getBillDetails(
      _pageSize,
      pageKey + 1,
      startTime: widget.startTime,
      endTime: widget.endTime,
      accountID: widget.accountParam,
      categoryID: widget.categoryParam,
      firstLevelCategoryID: widget.firstLevelCategoryParam,
      flowParam: widget.flowParam,
    );
  }

  void onItemPressed(Map<String, dynamic> item) {
    setState(() {
      selectedId = selectedId == item['id'] ? null : item['id'];
    });
  }

  void _showConfirmationDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认'),
          content: Text('是否确认删除金额为: ${item['detailed']} 的记录?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // 取消
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                try {
                  DB().deleteBill(item['id']);
                  _pagingController.value = _pagingController.value.filterItems(
                    (current) => current['id'] != item['id'],
                  );
                } catch (error) {
                  showNoticeSnackBar(context, "$error");
                }
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
    return PagingListener<int, Map<String, dynamic>>(
      controller: _pagingController,
      builder: (context, state, fetchNextPage) {
        return PagedListView<int, Map<String, dynamic>>(
          shrinkWrap: widget.isShrinkWrapped,
          physics:
              widget.isShrinkWrapped
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),

          state: state,
          fetchNextPage: fetchNextPage,
          builderDelegate: PagedChildBuilderDelegate<Map<String, dynamic>>(
            itemBuilder: (context, item, index) {
              final bool isExpanded = selectedId == item['id'];
              return Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(width: 1, color: Color(0xffe5e5e5)),
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(flex: 3, child: Text(item['account'])),
                          Expanded(
                            flex: 3,
                            child: Text(
                              "${item['flow'] == '支出' ? '-' : ''}${item['detailed'].toString()}",
                            ),
                          ),
                          //Expanded(flex: 2, child: Text(item['flow'])),
                          if (item['aim_account'] != null)
                            Expanded(flex: 3, child: Text(item['aim_account'])),
                          if (item['category'] != null)
                            Expanded(flex: 3, child: Text(item['category'])),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            "${item['flow'] == '转账' ? item['flow'] + '\n' : ''}${item['date'].substring(5)}",
                          ),
                          const Text(" "),
                          if (item['comment'] != null && item['comment'] != '')
                            Flexible(
                              child: Text(
                                '${item['flow'] == '转账' ? '\n' : ''}备注: ${item['comment']}',
                                maxLines: isExpanded ? null : 1,
                                overflow:
                                    isExpanded ? null : TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        onItemPressed(item);
                      },
                    ),
                    if (selectedId == item['id'])
                      ElevatedButton(
                        onPressed: () {
                          _showConfirmationDialog(item);
                        },
                        child: const Text('删除'),
                      ),
                  ],
                ),
              );
            },
            noItemsFoundIndicatorBuilder: (context) {
              return const Center(child: Text("尚无记录，添加一笔记录吧！"));
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
    bus.off("add_bill_success");
  }
}
