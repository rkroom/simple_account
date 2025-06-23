import 'package:flutter/material.dart';
import '../tools/entity.dart';
import 'schedule_card.dart';

class ScheduleListView extends StatelessWidget {
  final List<ScheduleItem> items;
  final VoidCallback onDataRefreshed;

  const ScheduleListView({
    super.key,
    required this.items,
    required this.onDataRefreshed,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ScheduleCard(item: item, onDataRefreshed: onDataRefreshed);
      },
    );
  }
}
