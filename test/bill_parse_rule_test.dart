import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/tools/bill_listener_service.dart';
import 'package:simple_account/tools/bill_parse_rule.dart';

RawPendingBill pendingBill({
  String packageName = 'example.package',
  String title = '',
  String content = '',
  String payment = '',
}) {
  return RawPendingBill(
    id: 'bill-id',
    packageName: packageName,
    appName: '测试应用',
    title: title,
    content: content,
    payment: payment,
    postTime: 1_700_000_000_000,
  );
}

BillParseRule rule({
  required String id,
  required String packageName,
  int priority = 0,
  List<String> titleContainsAny = const [],
  List<String> contentContainsAny = const [],
  List<String> paymentContainsAny = const [],
  BillRuleTextSource amountSource = BillRuleTextSource.content,
  String amountPattern = r'(\d+\.\d{2})',
  int amountGroup = 1,
  BillRuleFlow flow = BillRuleFlow.consume,
  String? accountName,
  String? categoryName,
  String? commentTemplate,
}) {
  return BillParseRule(
    id: id,
    name: id,
    packageName: packageName,
    enabled: true,
    priority: priority,
    titleContainsAny: titleContainsAny,
    contentContainsAny: contentContainsAny,
    paymentContainsAny: paymentContainsAny,
    amountSource: amountSource,
    amountPattern: amountPattern,
    amountGroup: amountGroup,
    flow: flow,
    accountName: accountName,
    categoryName: categoryName,
    commentTemplate: commentTemplate,
  );
}

void main() {
  group('默认规则', () {
    final engine = BillParseRuleEngine(BillParseRuleDocument.defaults());

    test('保留京东一到两位小数解析', () {
      final result = engine.match(
        pendingBill(
          packageName: 'com.jingdong.app.mall',
          content: '支付成功 12.3 元',
        ),
      );

      expect(result?.rule.id, 'builtin-jd-amount');
      expect(result?.amount, '12.3');
    });

    test('其它应用回退到通用两位小数规则', () {
      final result = engine.match(pendingBill(content: '本次支付金额为 28.50 元'));

      expect(result?.rule.id, 'builtin-global-two-decimals');
      expect(result?.amount, '28.50');
    });
  });

  group('可选账户规则文件', () {
    final optionalRules = BillParseRuleDocument.fromJsonString(
      File('examples/bill_account_rules.json').readAsStringSync(),
    );
    final engine = BillParseRuleEngine(
      BillParseRuleDocument(
        rules: [
          ...BillParseRuleDocument.defaults().rules,
          ...optionalRules.rules,
        ],
      ),
    );

    test('文件只包含可选账户规则', () {
      expect(optionalRules.rules, hasLength(5));
      expect(
        optionalRules.rules.every((rule) => rule.id.startsWith('optional-')),
        isTrue,
      );
    });

    test('金额规则命中后继续匹配支付账户', () {
      final raw = pendingBill(
        packageName: 'com.jingdong.app.mall',
        content: '支付成功 36.80 元',
        payment: '付款方式：花呗',
      );
      final result = engine.match(raw);
      final bill = BillListenerService().convertToBill(raw, engine);

      expect(result?.rule.id, 'builtin-jd-amount');
      expect(result?.amount, '36.80');
      expect(result?.accountName, '花呗');
      expect(bill.accountText, '花呗');
    });

    test('支持支付方式和应用包名账户映射', () {
      final ccb = engine.match(
        pendingBill(content: '消费 10.00', payment: '建设银行储蓄卡(1234)'),
      );
      final cmb = engine.match(
        pendingBill(
          packageName: 'com.cmbchina.ccd.pluto.cmbActivity',
          content: '消费金额 20.00',
        ),
      );

      expect(ccb?.accountName, '建行');
      expect(cmb?.accountName, '招行-young');
    });
  });

  group('规则选择', () {
    test('精确包名先于更高优先级的全局规则', () {
      final engine = BillParseRuleEngine(
        BillParseRuleDocument(
          rules: [
            rule(
              id: 'global',
              packageName: globalBillRulePackage,
              priority: 999,
            ),
            rule(id: 'package', packageName: 'example.package', priority: 1),
          ],
        ),
      );

      expect(
        engine.match(pendingBill(content: '金额 10.00'))?.rule.id,
        'package',
      );
    });

    test('同一包名内按优先级匹配并在条件失败时回退', () {
      final engine = BillParseRuleEngine(
        BillParseRuleDocument(
          rules: [
            rule(id: 'normal', packageName: 'example.package', priority: 10),
            rule(
              id: 'refund',
              packageName: 'example.package',
              priority: 100,
              titleContainsAny: const ['退款'],
              flow: BillRuleFlow.income,
            ),
          ],
        ),
      );

      final payment = engine.match(
        pendingBill(title: '支付成功', content: '金额 10.00'),
      );
      final refund = engine.match(
        pendingBill(title: '退款到账', content: '金额 10.00'),
      );

      expect(payment?.rule.id, 'normal');
      expect(refund?.rule.id, 'refund');
      expect(refund?.rule.flow, BillRuleFlow.income);
    });

    test('不同字段的关键词条件需要同时满足', () {
      final engine = BillParseRuleEngine(
        BillParseRuleDocument(
          rules: [
            rule(
              id: 'strict',
              packageName: 'example.package',
              titleContainsAny: const ['交易'],
              paymentContainsAny: const ['余额'],
            ),
          ],
        ),
      );

      expect(
        engine.match(
          pendingBill(title: '交易成功', content: '20.00', payment: '银行卡'),
        ),
        isNull,
      );
      expect(
        engine.match(
          pendingBill(title: '交易成功', content: '20.00', payment: '账户余额'),
        ),
        isNotNull,
      );
    });
  });

  test('空金额正则仍可预填方向、账户、类目和备注', () {
    final parseRule = rule(
      id: 'prefill',
      packageName: 'example.package',
      amountPattern: '',
      flow: BillRuleFlow.income,
      accountName: '余额',
      categoryName: '退款',
      commentTemplate: '{appName}: {title}',
    );
    final engine = BillParseRuleEngine(
      BillParseRuleDocument(rules: [parseRule]),
    );
    final raw = pendingBill(title: '退款到账');
    final result = engine.match(raw);
    final bill = BillListenerService().convertToBill(raw, engine);

    expect(result?.amount, isNull);
    expect(result?.comment, '测试应用: 退款到账');
    expect(bill.flow, 'income');
    expect(bill.accountText, '余额');
    expect(bill.categoryText, '退款');
    expect(bill.rawTitle, '退款到账');
    expect(bill.matchedRuleId, 'prefill');
  });

  group('JSON 校验', () {
    test('单条规则模板可以往返解析', () {
      final template = rule(
        id: 'single-template',
        packageName: globalBillRulePackage,
        priority: 100,
      );

      final restored = BillParseRule.fromJsonString(
        template.toJsonString(pretty: true),
      );

      expect(restored.id, 'single-template');
      expect(restored.packageName, globalBillRulePackage);
      expect(restored.amountPattern, r'(\d+\.\d{2})');
    });

    test('单条规则 JSON 拒绝数组和完整规则文档', () {
      expect(() => BillParseRule.fromJsonString('[]'), throwsFormatException);
      expect(
        () => BillParseRule.fromJsonString(
          BillParseRuleDocument.defaults().toJsonString(),
        ),
        throwsFormatException,
      );
    });

    test('文档可以格式化后往返解析', () {
      final defaults = BillParseRuleDocument.defaults();
      final restored = BillParseRuleDocument.fromJsonString(
        defaults.toJsonString(pretty: true),
      );

      expect(restored.schemaVersion, billParseRuleSchemaVersion);
      expect(restored.rules.map((item) => item.id), [
        'builtin-jd-amount',
        'builtin-global-two-decimals',
      ]);
    });

    test('拒绝重复 id', () {
      expect(
        () => BillParseRuleDocument(
          rules: [
            rule(id: 'same', packageName: 'a'),
            rule(id: 'same', packageName: 'b'),
          ],
        ),
        throwsFormatException,
      );
    });

    test('拒绝无效正则和不支持的 schemaVersion', () {
      expect(
        () => BillParseRule.fromJson({
          ...rule(id: 'bad', packageName: 'a').toJson(),
          'amountPattern': '(',
        }),
        throwsFormatException,
      );
      expect(
        () =>
            BillParseRuleDocument.fromJson({'schemaVersion': 99, 'rules': []}),
        throwsFormatException,
      );
    });
  });
}
