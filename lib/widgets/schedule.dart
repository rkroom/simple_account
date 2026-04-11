import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/entity.dart';
import '../tools/schedule_rule_helper.dart';
import 'schedule_calendar_view.dart';
import 'schedule_list_view.dart';

class ScheduleWidget extends StatefulWidget {
  const ScheduleWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return _ScheduleWidgetState();
  }
}

class _ScheduleWidgetState extends State<ScheduleWidget> {
  late Future<List<ScheduleItem>> _scheduleItemsFuture;

  bool _showCalendar = true;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = _normalizeDay(DateTime.now());
  DateTime? _selectedDay;

  final Map<DateTime, List<ScheduleItem>> _events = {};
  List<ScheduleItem> _allItems = [];

  double _fabDx = 0;
  double _fabDy = 0;

  bool _isFabPositionInitialized = false;
  bool _hasContinuingEvents = false;

  static DateTime _normalizeDay(DateTime day) {
    return DateTime(day.year, day.month, day.day);
  }

  @override
  void initState() {
    super.initState();

    _scheduleItemsFuture = _loadAndApplyScheduleItems();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isFabPositionInitialized && mounted) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        setState(() {
          _fabDx = screenWidth - 72;
          _fabDy =
              screenHeight -
              kToolbarHeight -
              kBottomNavigationBarHeight -
              MediaQuery.of(context).padding.bottom -
              95;
          _isFabPositionInitialized = true;
        });
      }
    });
  }

  Future<List<ScheduleItem>> _loadAndApplyScheduleItems() {
    final future = _loadScheduleItems();
    future.then((items) {
      if (!mounted) return;
      setState(() {
        _applyLoadedItems(items);
      });
    });
    return future;
  }

  void _applyLoadedItems(List<ScheduleItem> allItems) {
    _allItems = allItems;
    _hasContinuingEvents = allItems.any(
      (item) => item.status == ScheduleStatus.continuing,
    );

    if (_hasContinuingEvents) {
      final newEvents = _buildEventsForMonth(_focusedDay);
      _events
        ..clear()
        ..addAll(newEvents);
      _selectedDay = _resolveSelectedDayForMonth(newEvents, _focusedDay);
    } else {
      _events.clear();
      _selectedDay = null;
      if (allItems.isNotEmpty) {
        _showCalendar = false;
      }
    }
  }

  Future<List<ScheduleItem>> _loadScheduleItems() async {
    final List rawData = await DB().getScheduledTasks();
    final now = DateTime.now();

    final List<ScheduleItem> allItems =
        rawData.map((task) {
          final int taskId = task['id'] ?? 0;

          final String ruleType =
              (task['rule_type'] ?? task['round'] ?? '').toString();
          final ScheduleCycle cycle = ScheduleCycle.fromString(ruleType);

          final Map<String, dynamic>? ruleParams = parseRuleParams(
            task['rule_params'],
          );

          final String dateSign = task['datesign']?.toString() ?? '';
          final String? finalDateValue =
              task['finaldatef']?.toString() ?? task['finaldate']?.toString();

          final String statusStr = task['status']?.toString() ?? '';
          final ScheduleStatus status = ScheduleStatus.fromString(statusStr);

          String nextDate = '';
          try {
            nextDate = calcNextScheduleDate(
              now: now,
              cycle: cycle,
              dateSign: dateSign,
              finalDateValue: finalDateValue,
              ruleParams: ruleParams,
            );
          } catch (_) {
            nextDate = '';
          }

          final String? lastCompleted = task['handledate']?.toString();
          final String? finishedDate =
              task['finishedf']?.toString() ?? task['finished']?.toString();

          return ScheduleItem(
            id: taskId,
            content: task['content']?.toString() ?? '无内容',
            date: nextDate,
            lastCompletedDate: lastCompleted,
            finished: finishedDate,
            cycleValue: cycle,
            created: (task['createdf'] ?? task['created'] ?? '').toString(),
            status: status,
            dateSign: dateSign,
            finalDate: finalDateValue,
            ruleParams: ruleParams,
          );
        }).toList();

    return allItems;
  }

  Map<DateTime, List<ScheduleItem>> _buildEventsForMonth(DateTime month) {
    final DateTime monthStart = DateTime(month.year, month.month, 1);
    final DateTime monthEnd = DateTime(month.year, month.month + 1, 0);

    // 给月视图前后各扩 7 天，避免月视图首尾显示相邻月份日期时没有 marker
    final DateTime rangeStart = monthStart.subtract(const Duration(days: 7));
    final DateTime rangeEnd = monthEnd.add(const Duration(days: 7));

    final Map<DateTime, List<ScheduleItem>> newEvents = {};

    for (final item in _allItems) {
      if (item.status != ScheduleStatus.continuing) continue;

      final List<DateTime> dates = getScheduleDatesInRange(
        item: item,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );

      for (final dueDate in dates) {
        final DateTime normalizedDate = _normalizeDay(dueDate);

        newEvents.putIfAbsent(normalizedDate, () => []);

        newEvents[normalizedDate]!.add(
          ScheduleItem(
            id: item.id,
            content: item.content,
            date:
                '${normalizedDate.year.toString().padLeft(4, '0')}-'
                '${normalizedDate.month.toString().padLeft(2, '0')}-'
                '${normalizedDate.day.toString().padLeft(2, '0')}',
            lastCompletedDate: item.lastCompletedDate,
            finished: item.finished,
            cycleValue: item.cycleValue,
            created: item.created,
            status: item.status,
            dateSign: item.dateSign,
            finalDate: item.finalDate,
            ruleParams: item.ruleParams,
          ),
        );
      }
    }

    return newEvents;
  }

  DateTime? _resolveSelectedDayForMonth(
    Map<DateTime, List<ScheduleItem>> monthEvents,
    DateTime visibleMonth,
  ) {
    final normalizedVisibleMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month,
    );
    final normalizedToday = _normalizeDay(DateTime.now());

    if (_selectedDay != null) {
      final currentSelected = _normalizeDay(_selectedDay!);
      final bool isSameMonth =
          currentSelected.year == normalizedVisibleMonth.year &&
          currentSelected.month == normalizedVisibleMonth.month;

      if (isSameMonth && (monthEvents[currentSelected]?.isNotEmpty ?? false)) {
        return currentSelected;
      }
    }

    final bool todayInVisibleMonth =
        normalizedToday.year == normalizedVisibleMonth.year &&
        normalizedToday.month == normalizedVisibleMonth.month;

    if (todayInVisibleMonth &&
        (monthEvents[normalizedToday]?.isNotEmpty ?? false)) {
      return normalizedToday;
    }

    return null;
  }

  void _refreshData() {
    setState(() {
      _scheduleItemsFuture = _loadAndApplyScheduleItems();
    });
  }

  void _handleMonthChanged(DateTime focusedDay) {
    final DateTime normalizedFocusedDay = _normalizeDay(focusedDay);
    final Map<DateTime, List<ScheduleItem>> newEvents = _buildEventsForMonth(
      normalizedFocusedDay,
    );
    final DateTime? newSelectedDay = _resolveSelectedDayForMonth(
      newEvents,
      normalizedFocusedDay,
    );

    setState(() {
      _focusedDay = normalizedFocusedDay;
      _events
        ..clear()
        ..addAll(newEvents);
      _selectedDay = newSelectedDay;
    });
  }

  List<ScheduleItem> _getEventsForDay(DateTime day) {
    return _events[_normalizeDay(day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FutureBuilder<List<ScheduleItem>>(
            future: _scheduleItemsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('发生错误: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('没有待办事项。'));
              }

              final items = snapshot.data!;

              return _showCalendar && _hasContinuingEvents
                  ? ScheduleCalendarViewWidget(
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDay,
                    calendarFormat: _calendarFormat,
                    getEventsForDay: _getEventsForDay,
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = _normalizeDay(selectedDay);
                        _focusedDay = _normalizeDay(focusedDay);
                      });
                    },
                    onFormatChanged: (format) {
                      setState(() {
                        _calendarFormat = format;
                      });
                    },
                    onPageChanged: _handleMonthChanged,
                    onDataRefreshed: _refreshData,
                    onClearSelection: () {
                      if (_selectedDay != null) {
                        setState(() {
                          _selectedDay = null;
                        });
                      }
                    },
                  )
                  : ScheduleListView(
                    items: items,
                    onDataRefreshed: _refreshData,
                  );
            },
          ),
          if (_hasContinuingEvents)
            Positioned(
              left: _fabDx,
              top: _fabDy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _fabDx += details.delta.dx;
                    _fabDy += details.delta.dy;
                  });
                },
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _showCalendar = !_showCalendar;
                    });

                    if (_showCalendar) {
                      _handleMonthChanged(_focusedDay);
                    }
                  },
                  tooltip: _showCalendar ? '列表' : '日历',
                  child: Icon(
                    _showCalendar ? Icons.view_list : Icons.calendar_month,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
