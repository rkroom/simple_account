import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:simple_account/tools/config_service.dart';
import 'package:simple_account/tools/notification_service.dart';
import 'package:simple_account/tools/workmanager_tool.dart';

import 'config_enum.dart';
import 'db.dart';

void showNoticeSnackBar(BuildContext context, String message) {
  final snackBar = SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 2),
  );

  // 使用全局 ScaffoldMessenger 来显示 SnackBar
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}

// 日期格式化函数
String formatDateTime(DateTime dateTime) {
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
}

// 获取当前月份
List<String> currentlyMonthDays() {
  DateTime now = DateTime.now();
  DateTime firstDay = DateTime(now.year, now.month, 1);
  DateTime lastDay = DateTime(now.year, now.month + 1, 0);
  return [
    formatDateTime(firstDay),
    formatDateTime(
      DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59),
    ),
  ];
}

List<String> previousMonthDays() {
  DateTime now = DateTime.now();
  int month = now.month == 1 ? 12 : now.month - 1;
  int year = now.month == 1 ? now.year - 1 : now.year;
  DateTime firstDay = DateTime(year, month, 1);
  DateTime lastDay = DateTime(year, month + 1, 0);
  return [
    formatDateTime(firstDay),
    formatDateTime(
      DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59),
    ),
  ];
}

String generateRandomString(int length) {
  final random = Random();
  const availableChars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz';
  //const availableChars =
  //   'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  final randomString =
      List.generate(
        length,
        (index) => availableChars[random.nextInt(availableChars.length)],
      ).join();

  return randomString;
}

// 查找元素索引的函数
List<int> findElementIndexes(List<dynamic> data, String targetElement) {
  for (int i = 0; i < data.length; i++) {
    for (var entry in data[i].entries) {
      int j = entry.value.indexOf(targetElement);
      if (j != -1) {
        return [i, j];
      }
    }
  }
  return [];
}

// 获取账户信息
Future getAccount() async {
  List list = (await DB().getAccounts()).toList();
  List accountName = [];
  Map accountIndex = {};
  Map accountType = {};
  for (var l in list) {
    accountName.add(l["name"]);
    accountIndex[l["name"]] = l["id"];
    accountType[l["id"]] = l["type"];
  }
  // 返回LIST，包含，账户名，账户ID，账户类型
  return [accountName, accountIndex, accountType];
}

// 获取分类
Future getCategory(String flow) async {
  /*
    查询数据库，并将结果转换为LIST，采用遍历将其转换LIST<MAP>形式的结构
     */
  // 查询数据库，并将结果转换为LIST
  List list = (await DB().getCategorys(flow)).toList();
  // category与对应Id的MAP
  Map categoryIndex = {};

  Map<String, List<String>> categoryMap = {};
  // 遍历结果
  for (var l in list) {
    String specificCategory = l['specific_category']!;
    String name = l['name']!;
    if (!categoryMap.containsKey(name)) {
      categoryMap[name] = [];
    }
    categoryMap[name]!.add(specificCategory);
    categoryIndex[l["specific_category"]] = l["id"];
  }
  //分类List
  List<Map<String, List<String>>> category =
      categoryMap.entries.map((entry) {
        return {entry.key: entry.value};
      }).toList();
  // LIST，包含分类和分类的ID
  return [category, categoryIndex];
}

/*
  void showCustomSnackBar(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  final overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      bottom: 50.0, // 距离底部的位置
      left: 20.0,   // 可以根据需要调整位置
      right: 20.0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );

  // 将 OverlayEntry 插入 Overlay
  overlay.insert(overlayEntry);

  // 自动移除自定义的 SnackBar
  Future.delayed(const Duration(seconds: 3), () {
    overlayEntry.remove();
  });
}*/

// 获取指定日期范围
List<String> getDateRange(DateTime date) {
  return [
    formatDateTime(DateTime(date.year, date.month, date.day, 0, 0, 0)),
    formatDateTime(DateTime(date.year, date.month, date.day, 23, 59, 59)),
  ];
}

List<String> getPreviousDayRange() =>
    getDateRange(DateTime.now().subtract(const Duration(days: 1)));

List<String> getTodayRange() => getDateRange(DateTime.now());

double checkDBResult(double? value) {
  return (value == null || value.isNaN) ? 0 : value;
}

Future<Map> periodicStatistics() async {
  var cmd = currentlyMonthDays();
  var today = getTodayRange();
  var previousDay = getPreviousDayRange();

  // 使用 Future.wait 并行执行多个数据库查询
  var results = await Future.wait([
    DB().timeStatistics(Transaction.consume.value, cmd[0], cmd[1]),
    DB().timeStatistics(Transaction.consume.value, today[0], today[1]),
    DB().timeStatistics(
      Transaction.consume.value,
      previousDay[0],
      previousDay[1],
    ),
  ]);

  // 处理查询结果
  var currentlyMonthConsumption = checkDBResult(results[0][0]["amount"]);
  var todayConsumption = checkDBResult(results[1][0]["amount"]);
  var previousDayConsumption = checkDBResult(results[2][0]["amount"]);

  return {
    "currentlyMonthConsumption": currentlyMonthConsumption,
    "todayConsumption": todayConsumption,
    "previousDayConsumption": previousDayConsumption,
  };
}

Future<void> performInitialSetup() async {
  await NotificationService().initNotification();
  await WorkmanagerTool.setupAndScheduleTasks();
  ConfigService().setNotificationRegistered(true);
}

Future<void> registerNotification() async {
  bool succeeded = await ConfigService().getNotificationRegistered();
  if (!succeeded) {
    await NotificationService().initNotification();
    ConfigService().setNotificationRegistered(true);
    return;
  }
}

List<String> getMonthDateRange(DateTime date) {
  DateTime firstDay = DateTime(date.year, date.month, 1);
  DateTime lastDay = DateTime(date.year, date.month + 1, 0);
  return [
    formatDateTime(firstDay),
    formatDateTime(
      DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59),
    ),
  ];
}
