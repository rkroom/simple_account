import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/tools/bill_parse_rule.dart';
import 'package:simple_account/widgets/bill_rule_json_editor_dialog.dart';

void main() {
  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<BillParseRuleDocument>(
                        context: context,
                        builder:
                            (context) => BillRuleJsonEditorDialog(
                              initialDocument: BillParseRuleDocument.defaults(),
                            ),
                      );
                    },
                    child: const Text('打开'),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(BillRuleJsonEditorDialog), findsOneWidget);
  }

  testWidgets('未编辑时可以安全取消 JSON 对话框', (tester) async {
    await openEditor(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(BillRuleJsonEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('聚焦并输入后可以安全取消 JSON 对话框', (tester) async {
    await openEditor(tester);

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '{"rules": []}');
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(BillRuleJsonEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
