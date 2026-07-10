import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/pages/accessibility_rule_editor.dart';
import 'package:simple_account/tools/accessibility_extraction_rule.dart';

const packageName = 'com.example.pay';

Map<String, dynamic> ruleJson({
  String ruleName = '支付完成页',
  List<Map<String, dynamic>>? contentRules,
}) {
  return {
    'ruleName': ruleName,
    'packageName': packageName,
    'activityName': 'com.example.pay.ResultActivity',
    'contentRules':
        contentRules ??
        [
          {
            'keywords': ['支付成功'],
            'strategy': {
              'type': 'SimpleOffset',
              'offset': 1,
              'useExactMatch': true,
            },
          },
        ],
    'paymentRules': const [],
    'continueOnContentFailure': false,
    'triggerOnEmptyNodes': false,
    'emptyNodeTriggerCooldownMs': 120000,
    'preFilterByKeywords': false,
    'allowContentChangeTrigger': false,
    'hasPaymentInfo': true,
    'maxContentTriggerTimes': 2,
    'dynamicRetryTimes': 0,
    'dynamicRetryIntervalMs': 1000,
  };
}

void main() {
  group('AccessibilityExtractionRuleCodec', () {
    test('五种原生策略均可往返并保留扩展字段', () {
      final strategies = <Map<String, dynamic>>[
        {'type': 'SimpleOffset', 'offset': -1, 'useExactMatch': true},
        {
          'type': 'ConditionalOffset',
          'checkOffset': 0,
          'expectedTexts': ['¥', '￥'],
          'targetOffset': 2,
        },
        {
          'type': 'Concatenate',
          'parts': [
            {'type': 'NodeText', 'offset': 0},
            {'type': 'Literal', 'text': ': '},
          ],
        },
        {'type': 'DirectViewId', 'viewId': '$packageName:id/amount'},
        {
          'type': 'ExtractByViewId',
          'viewId': 'id/amount',
          'useExactMatch': false,
        },
      ];
      final source = ruleJson(
        contentRules: [
          for (final strategy in strategies)
            {
              'keywords': ['支付成功'],
              'strategy': strategy,
              'detailExtension': 'kept',
            },
        ],
      )..['ruleExtension'] = {'enabled': true};

      final parsed = AccessibilityExtractionRuleCodec.parseList([
        source,
      ], packageName: packageName);
      final reparsed = AccessibilityExtractionRuleCodec.parseJson(
        AccessibilityExtractionRuleCodec.encode(parsed, pretty: true),
        packageName: packageName,
      );

      expect(
        reparsed.single.contentRules.map((detail) => detail.strategyType),
        accessibilityStrategyTypes,
      );
      expect(reparsed.single.extra['ruleExtension'], {'enabled': true});
      expect(
        reparsed.single.contentRules.first.extra['detailExtension'],
        'kept',
      );
    });

    test('拒绝包名不匹配和非字符串关键词', () {
      final wrongPackage = ruleJson()..['packageName'] = 'com.other';
      expect(
        () => AccessibilityExtractionRuleCodec.parseList([
          wrongPackage,
        ], packageName: packageName),
        throwsFormatException,
      );

      final invalidKeywords = ruleJson(
        contentRules: [
          {
            'keywords': [1],
            'strategy': {'type': 'SimpleOffset', 'offset': 0},
          },
        ],
      );
      expect(
        () => AccessibilityExtractionRuleCodec.parseList([
          invalidKeywords,
        ], packageName: packageName),
        throwsFormatException,
      );
    });

    test('单条规则 JSON 使用对象格式并校验包名', () {
      final parsed = AccessibilityExtractionRuleCodec.parseRuleJson(
        jsonEncode(ruleJson()),
        packageName: packageName,
      );
      final encoded = AccessibilityExtractionRuleCodec.encodeRule(
        parsed,
        pretty: true,
      );

      expect(jsonDecode(encoded), isA<Map<String, dynamic>>());
      expect(parsed.ruleName, '支付完成页');
      expect(
        () => AccessibilityExtractionRuleCodec.parseRuleJson(
          jsonEncode([ruleJson()]),
          packageName: packageName,
        ),
        throwsFormatException,
      );
    });
  });

  group('AccessibilityRuleEditorPage', () {
    Future<void> pumpEditor(
      WidgetTester tester, {
      List<Map<String, dynamic>>? initialRules,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityRuleEditorPage(
            packageName: packageName,
            initialRules: initialRules ?? [ruleJson()],
          ),
        ),
      );
    }

    testWidgets('表单和 JSON 位于同一层级并可双向同步', (tester) async {
      await pumpEditor(tester);

      expect(find.text('表单'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('支付完成页'), findsOneWidget);

      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();

      final jsonEditor = find.byKey(accessibilityRuleJsonEditorKey);
      final jsonField = tester.widget<TextField>(jsonEditor);
      final edited = ruleJson(ruleName: 'JSON 修改后的规则');
      await tester.enterText(
        jsonEditor,
        const JsonEncoder.withIndent('  ').convert([edited]),
      );
      await tester.tap(find.text('表单'));
      await tester.pumpAndSettle();

      expect(jsonDecode(jsonField.controller!.text), isA<List<dynamic>>());
      expect(find.text('JSON 修改后的规则'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无现有规则时 JSON 模式包含默认模板', (tester) async {
      await pumpEditor(tester, initialRules: const []);

      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(accessibilityRuleJsonEditorKey),
      );
      final decoded = jsonDecode(field.controller!.text) as List<dynamic>;
      final template = decoded.single as Map<String, dynamic>;
      expect(template['packageName'], packageName);
      expect(template['contentRules'], isNotEmpty);
      expect(template['paymentRules'], isNotEmpty);
    });

    testWidgets('无现有规则时拒绝直接保存默认模板', (tester) async {
      await pumpEditor(tester, initialRules: const []);

      await tester.tap(find.byTooltip('保存'));
      await tester.pump();

      expect(find.text('请输入规则'), findsOneWidget);
      expect(find.byType(AccessibilityRuleEditorPage), findsOneWidget);
    });

    testWidgets('JSON 规则的 activityName 为空时拒绝保存', (tester) async {
      await pumpEditor(tester, initialRules: const []);
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();

      final jsonEditor = find.byKey(accessibilityRuleJsonEditorKey);
      final field = tester.widget<TextField>(jsonEditor);
      final decoded = jsonDecode(field.controller!.text) as List<dynamic>;
      (decoded.single as Map<String, dynamic>)['activityName'] = '';
      await tester.enterText(jsonEditor, jsonEncode(decoded));
      await tester.tap(find.byTooltip('保存'));
      await tester.pump();

      expect(find.textContaining('请输入 activityName'), findsOneWidget);
      expect(find.byType(AccessibilityRuleEditorPage), findsOneWidget);
    });

    testWidgets('打开表单规则后取消不会产生框架异常', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('支付完成页'));
      await tester.pumpAndSettle();
      expect(find.text('编辑提取规则'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('支付完成页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('新增提取规则支持单条 JSON 并保存到规则列表', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('添加提取规则'));
      await tester.pumpAndSettle();

      final form = find.byType(AccessibilityExtractionRuleForm);
      await tester.tap(find.descendant(of: form, matching: find.text('JSON')));
      await tester.pumpAndSettle();

      final editor = find.byKey(accessibilitySingleRuleJsonEditorKey);
      final field = tester.widget<TextField>(editor);
      expect(jsonDecode(field.controller!.text), isA<Map<String, dynamic>>());

      final added = ruleJson(ruleName: 'JSON 新增规则')
        ..['activityName'] = 'com.example.pay.NewActivity';
      await tester.enterText(editor, jsonEncode(added));
      await tester.tap(find.descendant(of: form, matching: find.text('保存')));
      await tester.pumpAndSettle();

      expect(find.text('JSON 新增规则'), findsOneWidget);
      expect(find.byType(AccessibilityExtractionRuleForm), findsNothing);
    });
  });

  group('AccessibilityExtractionRuleForm', () {
    Future<void> pumpForm(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibilityExtractionRuleForm(
              rule: AccessibilityExtractionRule.defaultForPackage(packageName),
              isNew: true,
            ),
          ),
        ),
      );
    }

    testWidgets('新增规则未修改模板时拒绝保存', (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.text('请输入规则').hitTestable(), findsOneWidget);
      expect(find.byType(AccessibilityExtractionRuleForm), findsOneWidget);
    });

    testWidgets('新增单条 JSON 未修改模板时拒绝保存', (tester) async {
      await pumpForm(tester);
      final form = find.byType(AccessibilityExtractionRuleForm);
      await tester.tap(find.descendant(of: form, matching: find.text('JSON')));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: form, matching: find.text('保存')));
      await tester.pump();

      expect(find.text('请输入规则').hitTestable(), findsOneWidget);
      expect(find.byKey(accessibilitySingleRuleJsonEditorKey), findsOneWidget);
      expect(find.byType(AccessibilityExtractionRuleForm), findsOneWidget);
    });

    testWidgets('activityName 为空时拒绝保存并提示', (tester) async {
      await pumpForm(tester);
      final activityField = find.widgetWithText(TextFormField, 'Activity 类名');
      await tester.enterText(activityField, '');

      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.text('请输入 activityName'), findsOneWidget);
      expect(find.byType(AccessibilityExtractionRuleForm), findsOneWidget);
    });

    testWidgets('单条 JSON 可以校验后同步到表单并保留扩展字段', (tester) async {
      await pumpForm(tester);
      final form = find.byType(AccessibilityExtractionRuleForm);
      await tester.tap(find.descendant(of: form, matching: find.text('JSON')));
      await tester.pumpAndSettle();

      final edited = ruleJson(ruleName: 'JSON 编辑规则')
        ..['ruleExtension'] = {'enabled': true};
      await tester.enterText(
        find.byKey(accessibilitySingleRuleJsonEditorKey),
        jsonEncode(edited),
      );
      await tester.tap(find.descendant(of: form, matching: find.text('表单')));
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, '规则名称'),
      );
      expect(nameField.controller!.text, 'JSON 编辑规则');

      await tester.tap(find.descendant(of: form, matching: find.text('JSON')));
      await tester.pumpAndSettle();
      final jsonField = tester.widget<TextField>(
        find.byKey(accessibilitySingleRuleJsonEditorKey),
      );
      final reparsed = jsonDecode(jsonField.controller!.text) as Map;
      expect(reparsed['ruleExtension'], {'enabled': true});
    });
  });
}
