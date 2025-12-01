import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:simple_account/tools/entity.dart';

import 'native_method_channel.dart';

class BillListenerService {
  // 单例实例
  static final BillListenerService _instance = BillListenerService._internal();

  // 私有构造函数
  BillListenerService._internal();

  // 提供静态的实例获取方法
  factory BillListenerService() {
    return _instance;
  }

  static final RegExp regExp = RegExp(r"(\d+\.\d{2})");

  static final RegExp jdRegExp = RegExp(r'\d+(?:\.\d{1,2})?');

  List<String> billString = [];
  List billsList = [];

  Future<void> clearBillListenerBox() async {
    await NativeMethodChannel.instance.clearBills();
  }

  Future<void> delBill(String id) async {
    await NativeMethodChannel.instance.delBill(id);
  }

  Future<List> getBills() async {
    List bills = await NativeMethodChannel.instance.getBills();
    if (listEquals(bills, billString)) {
      return billsList;
    }
    billString = List.from(bills);
    billsList = [];
    for (var bill in bills) {
      billsList.add(await handlerBillString(bill));
    }
    return billsList;
  }

  Future<Bill> handlerBillString(String notificationString) async {
    Map<String, dynamic> notification = jsonDecode(notificationString);
    final String id = notification['id'] as String? ?? '';
    final String packageName = notification['packageName'];
    final String content = notification['content'] as String? ?? 'empty';
    final String title = notification['title'];
    final int postTime = notification['postTime'];
    final String payment = notification['payment'] as String? ?? 'empty';
    final String appName = notification['appName'] as String? ?? 'Unknown';
    return await convertToBill(
      id,
      packageName,
      content,
      title,
      postTime,
      payment,
      appName,
    );
  }

  Future<Bill> convertToBill(
    String id,
    String packageName,
    String content,
    String title,
    int postTime,
    String payment,
    String appName,
  ) async {
    RegExpMatch? match;
    // 京东
    if (packageName == "com.jingdong.app.mall") {
      match = jdRegExp.firstMatch(content);
    } else {
      match = regExp.firstMatch(content);
    }

    final bill = Bill(
      id: id,
      detailed: match?.group(0),
      time: DateTime.fromMillisecondsSinceEpoch(postTime),
      source: appName,
    );
    return bill;
  }
}
