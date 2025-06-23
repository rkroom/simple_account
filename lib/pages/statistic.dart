import 'package:flutter/material.dart';
import 'package:simple_account/tools/db.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../widgets/statement.dart';

class StatisticWidget extends StatefulWidget {
  const StatisticWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return StatisticWidgetState();
  }
}

class StatisticWidgetState extends State<StatisticWidget> {
  final Map<DateTime, List<double>> _events = {};

  final DateTime _focusedDay = DateTime.now();
  late DateTime _firstDayOfMonth;
  late DateTime _lastDayOfMonth;
  bool _isLoading = true;
  String? _error;
  bool _isListView = false;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    _lastDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    _loadMonthlyTransactions();
  }

  void _loadMonthlyTransactions() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    DB()
        .getMonthlyTransactions()
        .then((value) {
          if (!mounted) return;
          final newEvents = <DateTime, List<double>>{};
          for (var item in value) {
            final date = DateTime.parse(item['date'] as String);
            final utcDate = DateTime.utc(date.year, date.month, date.day);
            final amount = item['amount'] as double;

            if (newEvents[utcDate] == null) {
              newEvents[utcDate] = [];
            }
            newEvents[utcDate]!.add(amount);
          }

          setState(() {
            _events.clear();
            _events.addAll(newEvents);
            _isLoading = false;
          });
        })
        .catchError((e) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _error = "数据加载失败: $e";
          });
        });
  }

  List<double> _getEventsForDay(DateTime day) {
    final utcDay = DateTime.utc(day.year, day.month, day.day);
    return _events[utcDay] ?? [];
  }

  void _showStatementDialog(DateTime date) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final startTime = DateTime.utc(date.year, date.month, date.day);
        final endTime = startTime.add(const Duration(days: 1));
        final title = '${date.month}月${date.day}日';

        return AlertDialog(
          title: Text(title),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20.0,
            vertical: 10.0,
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: StatementWidget(startTime: startTime, endTime: endTime),
          ),
          actions: [
            TextButton(
              child: const Text('关闭'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildListView() {
    final sortedEvents =
        _events.entries.toList()..sort((a, b) => b.key.compareTo(a.key));

    final List<Map<String, String>> tableData =
        sortedEvents.map((event) {
          final day = event.key;
          final totalExpense = event.value.reduce((sum, item) => sum + item);
          final formattedDate = DateFormat('MM-dd (E)', 'zh_CN').format(day);

          return {'日期': formattedDate, '支出': totalExpense.toStringAsFixed(2)};
        }).toList();

    return TableWidget(
      data: tableData,
      onRowTap: (rowData) {
        final tappedEntry = sortedEvents.firstWhere((element) {
          final formattedDate = DateFormat(
            'MM-dd (E)',
            'zh_CN',
          ).format(element.key);
          return formattedDate == rowData['日期'];
        });

        _showStatementDialog(tappedEntry.key);
      },
    );
  }

  Widget _buildLineChart() {
    final spots = <FlSpot>[];
    double maxAmount = 0;

    final now = DateTime.now();
    int endDay;

    if (now.year == _focusedDay.year && now.month == _focusedDay.month) {
      endDay = now.day;
    } else {
      endDay = _lastDayOfMonth.day;
    }

    final double interval = endDay > 1 ? endDay / 6.0 : 1;

    for (int i = 1; i <= endDay; i++) {
      final day = DateTime.utc(_focusedDay.year, _focusedDay.month, i);
      final events = _getEventsForDay(day);
      double totalForDay = 0;
      if (events.isNotEmpty) {
        totalForDay = events.reduce((a, b) => a + b);
      }
      if (totalForDay > maxAmount) {
        maxAmount = totalForDay;
      }
      spots.add(FlSpot(i.toDouble(), totalForDay));
    }

    if (maxAmount == 0) {
      return const SizedBox.shrink();
    }

    return AspectRatio(
      aspectRatio: 1.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                fitInsideHorizontally: true,
                getTooltipColor: (LineBarSpot touchedSpot) {
                  return const Color.fromRGBO(68, 138, 255, 0.8);
                },
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    return LineTooltipItem(
                      '${spot.x.toInt()}日\n¥${spot.y.toStringAsFixed(2)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: interval,
                  getTitlesWidget: (value, meta) {
                    if (value == 0 || value > endDay) {
                      return Container();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      space: 10,
                      child: Text(value.toInt().toString()),
                    );
                  },
                ),
              ),
            ),
            minY: 0,
            minX: 1,
            maxX: endDay.toDouble(),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                gradient: const LinearGradient(
                  colors: [Colors.blue, Colors.blue],
                ),
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      const Color.fromRGBO(33, 150, 239, 0.3),
                      const Color.fromRGBO(33, 150, 239, 0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatementForSelectedDay() {
    if (_selectedDay == null) {
      return const SizedBox.shrink();
    }

    final startTime = DateTime.utc(
      _selectedDay!.year,
      _selectedDay!.month,
      _selectedDay!.day,
    );
    final endTime = startTime.add(const Duration(days: 1));

    return SizedBox(
      height: 380,
      child: StatementWidget(startTime: startTime, endTime: endTime),
    );
  }

  Widget _buildCalendarView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          TableCalendar<double>(
            daysOfWeekHeight: 20.0,
            firstDay: _firstDayOfMonth,
            lastDay: _lastDayOfMonth,
            focusedDay: _focusedDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            locale: 'zh_CN',
            availableGestures: AvailableGestures.none,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              leftChevronVisible: false,
              rightChevronVisible: false,
              titleCentered: true,
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(fontSize: 13),
              weekendStyle: TextStyle(fontSize: 13),
            ),
            calendarStyle: CalendarStyle(
              weekendTextStyle: const TextStyle(),
              todayDecoration: const BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.rectangle,
              ),
              todayTextStyle: const TextStyle(color: Colors.black87),
              selectedDecoration: BoxDecoration(
                color: Colors.blue.shade400,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(color: Colors.white),
            ),
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: (selectedDay, focusedDay) {
              if (_getEventsForDay(selectedDay).isEmpty) {
                if (_selectedDay != null) {
                  setState(() {
                    _selectedDay = null;
                  });
                }
                return;
              }
              setState(() {
                if (isSameDay(_selectedDay, selectedDay)) {
                  _selectedDay = null;
                } else {
                  _selectedDay = selectedDay;
                }
              });
            },
            calendarBuilders: CalendarBuilders(
              dowBuilder: (context, day) {
                const dowText = {
                  1: '一',
                  2: '二',
                  3: '三',
                  4: '四',
                  5: '五',
                  6: '六',
                  7: '日',
                };
                return Center(
                  child: Text(
                    dowText[day.weekday]!,
                    style: const TextStyle(fontSize: 12.0),
                  ),
                );
              },
              markerBuilder: (context, date, events) {
                if (events.isNotEmpty) {
                  final totalExpense = events.reduce((sum, item) => sum + item);
                  return Positioned(
                    bottom: 3,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '¥${totalExpense.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                isSameDay(_selectedDay, date)
                                    ? Colors.white
                                    : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return null;
              },
            ),
            eventLoader: _getEventsForDay,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child:
                _selectedDay == null
                    ? _buildLineChart()
                    : _buildStatementForSelectedDay(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (_events.isEmpty) {
      return const Center(
        child: Text(
          '暂无可展示记录',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return _isListView ? _buildListView() : _buildCalendarView();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本月支出'),
        actions: [
          IconButton(
            icon: Icon(_isListView ? Icons.calendar_today : Icons.view_list),
            tooltip: _isListView ? '切换到日历视图' : '切换到列表视图',
            onPressed: () {
              setState(() {
                _isListView = !_isListView;
              });
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class TableWidget extends StatelessWidget {
  final List<Map<String, String>> data;
  final Function(Map<String, String>)? onRowTap;

  const TableWidget({super.key, required this.data, this.onRowTap});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container();
    }

    final headers = data[0].keys.toList();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade400, width: 1),
          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.5)},
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade200),
              children:
                  headers.map((header) {
                    return Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Center(
                        child: Text(
                          header,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            ...data.map((row) {
              return TableRow(
                children:
                    headers.map((header) {
                      return GestureDetector(
                        onTap: () => onRowTap?.call(row),
                        child: Container(
                          color: Colors.transparent,
                          padding: const EdgeInsets.all(10.0),
                          child: Center(child: Text(row[header] ?? '')),
                        ),
                      );
                    }).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }
}
