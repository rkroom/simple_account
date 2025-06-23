import 'package:flutter/material.dart';

import 'account.dart';
import 'add.dart';
import 'statement.dart';

class AccountBookHome extends StatefulWidget {
  const AccountBookHome({super.key});

  @override
  State<AccountBookHome> createState() => AccountBookHomeState();
}

class AccountBookHomeState extends State<AccountBookHome> {
  int _currentIndex = 0;
  late List<Widget> pages;
  final List<String> titles = ["添加", "账单", "账户"];

  @override
  void initState() {
    super.initState();
    _initializePages();
  }

  void _initializePages() {
    pages = [const AddWidget(), const StatementWidget(), const AccountWidget()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.plus_one), label: '记账'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: '账单'),
          BottomNavigationBarItem(icon: Icon(Icons.local_atm), label: '账户'),
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
