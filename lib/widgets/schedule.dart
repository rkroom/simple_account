import 'package:flutter/material.dart';
import 'package:simple_account/widgets/schedule_calendar_view.dart';
import 'package:table_calendar/table_calendar.dart';

import '../tools/config_enum.dart';
import '../tools/db.dart';
import '../tools/entity.dart';
import '../tools/schedule_rule_helper.dart';
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
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Map<DateTime, List<ScheduleItem>> _events = {};

  double _fabDx = 0;
  double _fabDy = 0;

  bool _isFabPositionInitialized = false;

  bool _hasContinuingEvents = false;

  @override
  void initState() {
    super.initState();

    _scheduleItemsFuture = _loadScheduleItems().then((items) {
      _handleSelectedAndFocusedDayAfterLoad(isInitialLoad: true);
      return items;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isFabPositionInitialized) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        setState(() {
          _fabDx = screenWidth - 72;
          _fabDy =
              screenHeight -
              kToolbarHeight -
              kBottomNavigationBarHeight -
              MediaQuery.of(context).padding.bottom -
              90;
          _isFabPositionInitialized = true;
        });
      }
    });
  }

  Future<List<ScheduleItem>> _loadScheduleItems() async {
    final List rawData = await DB().getScheduledTasks();
    final now = DateTime.now();

    List<ScheduleItem> allItems =
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

          final String statusStr = task['status'].toString();
          final ScheduleStatus status = ScheduleStatus.fromString(statusStr);

          final String date = calcNextScheduleDate(
            now: now,
            cycle: cycle,
            dateSign: dateSign,
            finalDateValue: finalDateValue,
            ruleParams: ruleParams,
          );

          final String? lastCompleted = task['handledate']?.toString();
          final String? finishedDate = task['finishedf']?.toString();

          return ScheduleItem(
            id: taskId,
            content: task['content']?.toString() ?? '无内容',
            date: date,
            lastCompletedDate: lastCompleted,
            finished: finishedDate,
            cycleValue: cycle,
            created: task['created'] ?? '',
            status: status,
            dateSign: dateSign,
            finalDate: finalDateValue,
            ruleParams: ruleParams,
          );
        }).toList();

    _events.clear();
    _hasContinuingEvents = false;
    for (var item in allItems) {
      if (item.status == ScheduleStatus.continuing) {
        _hasContinuingEvents = true;
        final date = DateTime.parse(item.date);
        final normalizedDate = DateTime(date.year, date.month, date.day);
        if (_events[normalizedDate] == null) {
          _events[normalizedDate] = [];
        }
        _events[normalizedDate]!.add(item);
      }
    }

    if (!_hasContinuingEvents && allItems.isNotEmpty) {
      _showCalendar = false;
    }

    return allItems;
  }

  void _handleSelectedAndFocusedDayAfterLoad({bool isInitialLoad = false}) {
    final now = DateTime.now();
    final normalizedToday = DateTime(now.year, now.month, now.day);
    DateTime? newSelectedDay = _selectedDay;
    if (newSelectedDay == null) {
      if (_events.containsKey(normalizedToday) &&
          _events[normalizedToday]!.isNotEmpty) {
        newSelectedDay = normalizedToday;
      }
    }

    setState(() {
      _selectedDay = newSelectedDay;
      _focusedDay = _selectedDay ?? normalizedToday;
    });
  }

  void _refreshData() {
    setState(() {
      _scheduleItemsFuture = _loadScheduleItems().then((items) {
        _handleSelectedAndFocusedDayAfterLoad();
        return items;
      });
    });
  }

  List<ScheduleItem> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
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
                    events: _events,
                    getEventsForDay: _getEventsForDay,
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    onFormatChanged: (format) {
                      setState(() {
                        _calendarFormat = format;
                      });
                    },
                    onDataRefreshed: _refreshData,
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
                      if (_showCalendar) {
                        _refreshData();
                      }
                    });
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
