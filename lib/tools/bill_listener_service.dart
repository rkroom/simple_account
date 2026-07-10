import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:simple_account/tools/bill_parse_rule.dart';
import 'package:simple_account/tools/config_service.dart';
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

  List<String> billString = [];
  List<Bill> billsList = [];
  String? _rulesJsonSnapshot;

  Future<void> clearBillListenerBox() async {
    await NativeMethodChannel.instance.clearBills();
  }

  Future<void> delBill(String id) async {
    await NativeMethodChannel.instance.delBill(id);
  }

  Future<List<Bill>> getBills() async {
    final List<dynamic> rawBills =
        await NativeMethodChannel.instance.getBills();
    final bills = rawBills
        .map((item) => item.toString())
        .toList(growable: false);
    final rulesJson = await ConfigService().getBillParseRulesJson();
    if (listEquals(bills, billString) && rulesJson == _rulesJsonSnapshot) {
      return billsList;
    }

    final engine = _createEngine(rulesJson);
    billString = List.from(bills);
    _rulesJsonSnapshot = rulesJson;
    billsList = [];
    for (var bill in bills) {
      billsList.add(await handlerBillString(bill, engine: engine));
    }
    return billsList;
  }

  BillParseRuleEngine _createEngine(String rulesJson) {
    try {
      return BillParseRuleEngine(
        BillParseRuleDocument.fromJsonString(rulesJson),
      );
    } on FormatException catch (error) {
      debugPrint('账单解析规则无效，已使用默认规则: ${error.message}');
      return BillParseRuleEngine(BillParseRuleDocument.defaults());
    }
  }

  Future<Bill> handlerBillString(
    String notificationString, {
    BillParseRuleEngine? engine,
  }) async {
    final decoded = jsonDecode(notificationString);
    if (decoded is! Map) {
      throw const FormatException('暂存账单数据必须是 JSON 对象');
    }
    final rawBill = RawPendingBill.fromJson(Map<String, dynamic>.from(decoded));
    final activeEngine =
        engine ?? _createEngine(await ConfigService().getBillParseRulesJson());
    return convertToBill(rawBill, activeEngine);
  }

  Bill convertToBill(RawPendingBill rawBill, BillParseRuleEngine engine) {
    final matched = engine.match(rawBill);
    final rule = matched?.rule;
    final postTime =
        rawBill.postTime > 0
            ? DateTime.fromMillisecondsSinceEpoch(rawBill.postTime)
            : DateTime.now();

    return Bill(
      id: rawBill.id,
      detailed: matched?.amount,
      time: postTime,
      source: rawBill.appName,
      flow: rule?.flow.name ?? BillRuleFlow.consume.name,
      comment: matched?.comment ?? '',
      accountText: matched?.accountName ?? '请选择',
      categoryText: rule?.categoryName ?? '请选择',
      packageName: rawBill.packageName,
      rawTitle: rawBill.title,
      rawContent: rawBill.content,
      rawPayment: rawBill.payment,
      matchedRuleId: rule?.id,
      matchedRuleName: rule?.name,
    );
  }
}
