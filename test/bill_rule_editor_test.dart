import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/pages/bill_rule_config.dart';
import 'package:simple_account/tools/bill_parse_rule.dart';

BillParseRule newRuleTemplate() {
  return BillParseRule(
    id: 'rule-template',
    name: '新规则',
    packageName: globalBillRulePackage,
    enabled: true,
    priority: 100,
    titleContainsAny: const [],
    contentContainsAny: const [],
    paymentContainsAny: const [],
    amountSource: BillRuleTextSource.content,
    amountPattern: r'(\d+(?:\.\d{1,2})?)',
    amountGroup: 1,
    flow: BillRuleFlow.consume,
  );
}

void main() {
  testWidgets('JSON 新增模式展示完整的单条规则模板', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BillRuleEditorSheet(
            rule: newRuleTemplate(),
            isNew: true,
            initialMode: BillRuleEditorMode.json,
            reservedRuleIds: const {},
            packageLabels: const {globalBillRulePackage: '预置规则'},
            accounts: const [],
            consumeCategories: const [],
            incomeCategories: const [],
          ),
        ),
      ),
    );

    expect(find.text('新增规则'), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    final parsed = BillParseRule.fromJsonString(textField.controller!.text);

    expect(parsed.id, 'rule-template');
    expect(parsed.name, '新规则');
    expect(parsed.packageName, globalBillRulePackage);
    expect(parsed.priority, 100);
    expect(parsed.amountPattern, r'(\d+(?:\.\d{1,2})?)');
  });

  testWidgets('单条规则 JSON 可以校验后同步到表单', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BillRuleEditorSheet(
            rule: newRuleTemplate(),
            isNew: false,
            initialMode: BillRuleEditorMode.json,
            reservedRuleIds: const {},
            packageLabels: const {globalBillRulePackage: '预置规则'},
            accounts: const [],
            consumeCategories: const [],
            incomeCategories: const [],
          ),
        ),
      ),
    );

    final modified = newRuleTemplate().copyWith(
      id: 'edited-id',
      name: 'JSON 编辑规则',
      priority: 250,
    );
    await tester.enterText(
      find.byType(TextField),
      modified.toJsonString(pretty: true),
    );
    await tester.tap(find.text('表单'));
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields.first.controller!.text, 'JSON 编辑规则');
    expect(fields.elementAt(2).controller!.text, '250');
    expect(tester.takeException(), isNull);
  });

  testWidgets('单条规则 JSON 的重复 ID 会留在编辑器内提示', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BillRuleEditorSheet(
            rule: newRuleTemplate(),
            isNew: true,
            initialMode: BillRuleEditorMode.json,
            reservedRuleIds: const {'duplicate-id'},
            packageLabels: const {globalBillRulePackage: '预置规则'},
            accounts: const [],
            consumeCategories: const [],
            incomeCategories: const [],
          ),
        ),
      ),
    );

    final duplicate = newRuleTemplate().copyWith(id: 'duplicate-id');
    await tester.enterText(
      find.byType(TextField),
      duplicate.toJsonString(pretty: true),
    );
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('规则 ID "duplicate-id" 已存在'), findsOneWidget);
    expect(find.byType(BillRuleEditorSheet), findsOneWidget);
  });

  for (final mode in BillRuleEditorMode.values) {
    testWidgets(
      '新增${mode == BillRuleEditorMode.form ? '表单' : ' JSON'}规则未修改模板时拒绝保存',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BillRuleEditorSheet(
                rule: newRuleTemplate(),
                isNew: true,
                initialMode: mode,
                reservedRuleIds: const {},
                packageLabels: const {globalBillRulePackage: '预置规则'},
                accounts: const [],
                consumeCategories: const [],
                incomeCategories: const [],
              ),
            ),
          ),
        );

        await tester.tap(find.text('保存'));
        await tester.pump();

        expect(find.text('请输入规则').hitTestable(), findsOneWidget);
        expect(find.byType(BillRuleEditorSheet), findsOneWidget);
      },
    );
  }
}
