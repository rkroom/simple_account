import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/tools/automatic_service_config.dart';
import 'package:simple_account/tools/bill_parse_rule.dart';

void main() {
  group('AutomaticServiceConfig', () {
    test('导入导出包含辅助功能配置和账单解析规则', () {
      final source = AutomaticServiceConfig(
        accessibilityPackageConfig: const [
          {
            'appName': '测试应用',
            'packageName': 'com.example.app',
            'isAllowed': true,
          },
        ],
        notificationPackageConfig: const [],
        notificationKeywords: const ['支付'],
        accessibilityExtractionRules: const [
          {
            'packageName': 'com.example.app',
            'contentRules': <dynamic>[],
            'paymentRules': <dynamic>[],
          },
        ],
        enableWindowContentChange: true,
        enableRecordToast: true,
        billParseRules: BillParseRuleDocument.defaults(),
      );

      final restored = AutomaticServiceConfig.fromJson(source.toJson());

      expect(restored.accessibilityPackageConfig, hasLength(1));
      expect(restored.accessibilityExtractionRules, hasLength(1));
      expect(restored.enableWindowContentChange, isTrue);
      expect(restored.enableRecordToast, isTrue);
      expect(
        restored.billParseRules.rules.length,
        BillParseRuleDocument.defaults().rules.length,
      );
    });

    test('拒绝缺少当前字段的旧总配置文件', () {
      expect(
        () => AutomaticServiceConfig.fromJson({
          'abPackageConfig': <dynamic>[],
          'nlPackageConfig': <dynamic>[],
          'nlKeywords': <dynamic>[],
        }),
        throwsFormatException,
      );
    });

    test('拒绝无效的账单解析规则', () {
      expect(
        () => AutomaticServiceConfig.fromJson({
          'abPackageConfig': <dynamic>[],
          'nlPackageConfig': <dynamic>[],
          'nlKeywords': <dynamic>[],
          'extractionRules': <dynamic>[],
          'enableWindowContentChange': false,
          'enableRecordToast': true,
          'billParseRules': {
            'schemaVersion': billParseRuleSchemaVersion,
            'rules': [
              {'id': ''},
            ],
          },
        }),
        throwsFormatException,
      );
    });
  });
}
