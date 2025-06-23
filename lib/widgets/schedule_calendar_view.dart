import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../tools/entity.dart';
import 'schedule_card.dart';

class ScheduleCalendarViewWidget extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final CalendarFormat calendarFormat;
  final Map<DateTime, List<ScheduleItem>> events;
  final List<ScheduleItem> Function(DateTime day) getEventsForDay;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final void Function(CalendarFormat format) onFormatChanged;
  final VoidCallback onDataRefreshed;

  const ScheduleCalendarViewWidget({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.calendarFormat,
    required this.events,
    required this.getEventsForDay,
    required this.onDaySelected,
    required this.onFormatChanged,
    required this.onDataRefreshed,
  });

  Widget _buildEventsMarker(DateTime date, List events) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue[400],
      ),
      width: 16.0,
      height: 16.0,
      child: Center(
        child: Text(
          '${events.length}',
          style: const TextStyle().copyWith(
            color: Colors.white,
            fontSize: 10.0,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar<ScheduleItem>(
          startingDayOfWeek: StartingDayOfWeek.monday,
          locale: Localizations.localeOf(context).toString(),
          daysOfWeekHeight: 20.0,
          firstDay: DateTime.utc(2000, 1, 1),
          lastDay: DateTime.utc(2050, 12, 31),
          focusedDay: focusedDay,
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          calendarFormat: calendarFormat,
          eventLoader: getEventsForDay,
          onDaySelected: onDaySelected,
          onFormatChanged: onFormatChanged,
          onPageChanged: (focusedDay) {
            // 父组件处理
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
                return Positioned(
                  right: 1,
                  bottom: 1,
                  child: _buildEventsMarker(date, events),
                );
              }
              return null;
            },
          ),
          availableCalendarFormats: const {
            CalendarFormat.month: '月',
            CalendarFormat.week: '周',
            CalendarFormat.twoWeeks: '两周',
          },
        ),
        const SizedBox(height: 8.0),
        Expanded(
          child:
              selectedDay != null
                  ? ListView.builder(
                    itemCount: getEventsForDay(selectedDay!).length,
                    itemBuilder: (context, index) {
                      final item = getEventsForDay(selectedDay!)[index];
                      return ScheduleCard(
                        item: item,
                        onDataRefreshed: onDataRefreshed,
                      );
                    },
                  )
                  : const Center(child: Text('选择一个日期查看任务。')),
        ),
      ],
    );
  }
}
