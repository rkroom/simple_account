import 'package:flutter/material.dart';

import 'add_schedule.dart';
import 'schedule.dart';

class PlannedTaskHome extends StatefulWidget {
  final Key? refreshKey;
  const PlannedTaskHome({super.key, this.refreshKey});

  @override
  State<PlannedTaskHome> createState() => PlannedTaskHomeState();
}

class PlannedTaskHomeState extends State<PlannedTaskHome> {
  int _currentIndex = 0;
  late List<Widget> pages;
  final List<String> titles = ["当前", "添加"];

  @override
  void initState() {
    super.initState();
    _initializePages();
  }

  @override
  void didUpdateWidget(covariant PlannedTaskHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshKey != null &&
        widget.refreshKey != oldWidget.refreshKey) {
      setState(() {
        _initializePages();
      });
    }
  }

  void _initializePages() {
    pages = [ScheduleWidget(), AddScheduleWidget()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: '当前'),
          BottomNavigationBarItem(icon: Icon(Icons.plus_one), label: '添加'),
        ],
        currentIndex: _currentIndex,
        onTap: (int i) {
          setState(() {
            _currentIndex = i;
          });
        },
      ),
    );
  }
}
