import 'package:flutter/material.dart';

import 'account.dart';
import 'add.dart';
import 'statement.dart';
import 'statement_filter.dart';

class AccountBookHome extends StatefulWidget {
  final ValueChanged<int>? onTabChanged;
  final StatementFilterValue filterValue;

  const AccountBookHome({
    super.key,
    this.onTabChanged,
    this.filterValue = const StatementFilterValue(),
  });

  @override
  State<AccountBookHome> createState() => AccountBookHomeState();
}

class AccountBookHomeState extends State<AccountBookHome> {
  int _currentIndex = 0;

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return const AddWidget();
      case 1:
        return StatementWidget(
          startTime: widget.filterValue.startTime,
          endTime: widget.filterValue.endTime,
          accountParam: widget.filterValue.accountId,
          categoryParam: widget.filterValue.categoryId,
          flowParam: widget.filterValue.flowQuery,
        );
      case 2:
        return const AccountWidget();
      default:
        return const SizedBox.shrink();
    }
  }

  void _onTapBottomNav(int i) {
    setState(() {
      _currentIndex = i;
    });
    widget.onTabChanged?.call(i);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onTabChanged?.call(_currentIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _buildCurrentPage()),
        BottomNavigationBar(
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.plus_one), label: '记账'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt), label: '账单'),
            BottomNavigationBarItem(icon: Icon(Icons.local_atm), label: '账户'),
          ],
          currentIndex: _currentIndex,
          onTap: _onTapBottomNav,
        ),
      ],
    );
  }
}
