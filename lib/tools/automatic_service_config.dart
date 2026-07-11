import 'bill_parse_rule.dart';

/// 可导入、导出的自动服务配置。
///
/// Android 系统授予的辅助功能和通知监听权限不属于应用数据，无法通过
/// 配置文件迁移。这里保存的是应用侧的白名单、提取规则和相关开关。
class AutomaticServiceConfig {
  final List<Map<String, dynamic>> accessibilityPackageConfig;
  final List<Map<String, dynamic>> notificationPackageConfig;
  final List<String> notificationKeywords;
  final List<Map<String, dynamic>> accessibilityExtractionRules;
  final bool enableWindowContentChange;
  final bool enableRecordToast;
  final BillParseRuleDocument billParseRules;

  const AutomaticServiceConfig({
    required this.accessibilityPackageConfig,
    required this.notificationPackageConfig,
    required this.notificationKeywords,
    required this.accessibilityExtractionRules,
    required this.enableWindowContentChange,
    required this.enableRecordToast,
    required this.billParseRules,
  });

  factory AutomaticServiceConfig.fromJson(dynamic json) {
    if (json is! Map) {
      throw const FormatException('配置文件顶层必须是对象');
    }
    final map = Map<String, dynamic>.from(json);

    final enableWindowContentChange = map['enableWindowContentChange'];
    final enableRecordToast = map['enableRecordToast'];
    if (enableWindowContentChange is! bool) {
      throw const FormatException('enableWindowContentChange 必须是布尔值');
    }
    if (enableRecordToast is! bool) {
      throw const FormatException('enableRecordToast 必须是布尔值');
    }

    final billParseRulesRaw = map['billParseRules'];
    if (billParseRulesRaw is! Map) {
      throw const FormatException('billParseRules 必须是对象');
    }
    final billParseRules = BillParseRuleDocument.fromJson(billParseRulesRaw);

    return AutomaticServiceConfig(
      accessibilityPackageConfig: _readMapList(
        map['abPackageConfig'],
        'abPackageConfig',
      ),
      notificationPackageConfig: _readMapList(
        map['nlPackageConfig'],
        'nlPackageConfig',
      ),
      notificationKeywords: _readStringList(map['nlKeywords'], 'nlKeywords'),
      accessibilityExtractionRules: _readMapList(
        map['extractionRules'],
        'extractionRules',
      ),
      enableWindowContentChange: enableWindowContentChange,
      enableRecordToast: enableRecordToast,
      billParseRules: billParseRules,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'abPackageConfig': accessibilityPackageConfig,
      'nlPackageConfig': notificationPackageConfig,
      'nlKeywords': notificationKeywords,
      'extractionRules': accessibilityExtractionRules,
      'enableWindowContentChange': enableWindowContentChange,
      'enableRecordToast': enableRecordToast,
      'billParseRules': billParseRules.toJson(),
    };
  }

  static List<Map<String, dynamic>> _readMapList(
    dynamic value,
    String fieldName,
  ) {
    if (value is! List) {
      throw FormatException('$fieldName 必须是数组');
    }

    return [
      for (var index = 0; index < value.length; index++)
        if (value[index] is Map)
          Map<String, dynamic>.from(value[index] as Map)
        else
          throw FormatException('$fieldName 的第 ${index + 1} 项必须是对象'),
    ];
  }

  static List<String> _readStringList(dynamic value, String fieldName) {
    if (value is! List) {
      throw FormatException('$fieldName 必须是数组');
    }
    return value.map((item) => item.toString()).toList(growable: false);
  }
}
