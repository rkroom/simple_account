import 'dart:convert';

const List<String> accessibilityStrategyTypes = [
  'SimpleOffset',
  'ConditionalOffset',
  'Concatenate',
  'DirectViewId',
  'ExtractByViewId',
];

class AccessibilityRuleDetail {
  final List<String> keywords;
  final Map<String, dynamic> strategy;
  final Map<String, dynamic> extra;

  AccessibilityRuleDetail({
    required List<String> keywords,
    required Map<String, dynamic> strategy,
    Map<String, dynamic> extra = const {},
  }) : keywords = List.unmodifiable(keywords),
       strategy = Map.unmodifiable(strategy),
       extra = Map.unmodifiable(extra) {
    validate();
  }

  factory AccessibilityRuleDetail.fromJson(Map<String, dynamic> json) {
    final rawKeywords = json['keywords'];
    if (rawKeywords != null && rawKeywords is! List) {
      throw const FormatException('keywords 必须是字符串数组');
    }
    final keywordItems = rawKeywords as List? ?? const [];
    if (keywordItems.any((item) => item is! String)) {
      throw const FormatException('keywords 必须是字符串数组');
    }
    final keywords = keywordItems
        .cast<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final rawStrategy = json['strategy'];
    if (rawStrategy is! Map) {
      throw const FormatException('缺少有效的 strategy 对象');
    }
    final extra =
        Map<String, dynamic>.from(json)
          ..remove('keywords')
          ..remove('strategy');
    return AccessibilityRuleDetail(
      keywords: keywords,
      strategy: Map<String, dynamic>.from(rawStrategy),
      extra: extra,
    );
  }

  String get strategyType => strategy['type']?.toString() ?? '';

  void validate() {
    final type = strategyType;
    if (!accessibilityStrategyTypes.contains(type)) {
      throw FormatException('未知的策略类型 "$type"');
    }

    int requireInt(String key) {
      final value = strategy[key];
      if (value is! int) {
        throw FormatException('$type.$key 必须是整数');
      }
      return value;
    }

    String requireText(String key) {
      final value = strategy[key]?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw FormatException('$type.$key 不能为空');
      }
      return value;
    }

    void validateOptionalBool(String key) {
      if (strategy.containsKey(key) && strategy[key] is! bool) {
        throw FormatException('$type.$key 必须是布尔值');
      }
    }

    switch (type) {
      case 'SimpleOffset':
        requireInt('offset');
        validateOptionalBool('useExactMatch');
        break;
      case 'ConditionalOffset':
        requireInt('checkOffset');
        requireInt('targetOffset');
        final expectedTexts = strategy['expectedTexts'];
        if (expectedTexts is! List || expectedTexts.isEmpty) {
          throw const FormatException(
            'ConditionalOffset.expectedTexts 必须是非空字符串数组',
          );
        }
        if (expectedTexts.any(
          (item) => item is! String || item.trim().isEmpty,
        )) {
          throw const FormatException(
            'ConditionalOffset.expectedTexts 不能包含空字符串',
          );
        }
        break;
      case 'Concatenate':
        final parts = strategy['parts'];
        if (parts is! List || parts.isEmpty) {
          throw const FormatException('Concatenate.parts 必须是非空数组');
        }
        for (var index = 0; index < parts.length; index++) {
          final rawPart = parts[index];
          if (rawPart is! Map) {
            throw FormatException('Concatenate.parts[$index] 必须是对象');
          }
          final part = Map<String, dynamic>.from(rawPart);
          switch (part['type']) {
            case 'Literal':
              if (!part.containsKey('text') || part['text'] is! String) {
                throw FormatException('Concatenate.parts[$index].text 必须是字符串');
              }
              break;
            case 'NodeText':
              if (part['offset'] is! int) {
                throw FormatException('Concatenate.parts[$index].offset 必须是整数');
              }
              break;
            default:
              throw FormatException(
                'Concatenate.parts[$index] 的 type 必须是 Literal 或 NodeText',
              );
          }
        }
        break;
      case 'DirectViewId':
        requireText('viewId');
        break;
      case 'ExtractByViewId':
        requireText('viewId');
        validateOptionalBool('useExactMatch');
        break;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      'keywords': keywords,
      'strategy': Map<String, dynamic>.from(strategy),
    };
  }
}

class AccessibilityExtractionRule {
  final String ruleName;
  final String packageName;
  final String activityName;
  final List<AccessibilityRuleDetail> contentRules;
  final List<AccessibilityRuleDetail> paymentRules;
  final bool continueOnContentFailure;
  final bool triggerOnEmptyNodes;
  final int emptyNodeTriggerCooldownMs;
  final bool preFilterByKeywords;
  final bool allowContentChangeTrigger;
  final bool hasPaymentInfo;
  final int maxContentTriggerTimes;
  final int dynamicRetryTimes;
  final int dynamicRetryIntervalMs;
  final Map<String, dynamic> extra;

  AccessibilityExtractionRule({
    required this.ruleName,
    required this.packageName,
    required this.activityName,
    required List<AccessibilityRuleDetail> contentRules,
    required List<AccessibilityRuleDetail> paymentRules,
    this.continueOnContentFailure = false,
    this.triggerOnEmptyNodes = false,
    this.emptyNodeTriggerCooldownMs = 120000,
    this.preFilterByKeywords = false,
    this.allowContentChangeTrigger = false,
    this.hasPaymentInfo = true,
    this.maxContentTriggerTimes = 2,
    this.dynamicRetryTimes = 0,
    this.dynamicRetryIntervalMs = 1000,
    Map<String, dynamic> extra = const {},
  }) : contentRules = List.unmodifiable(contentRules),
       paymentRules = List.unmodifiable(paymentRules),
       extra = Map.unmodifiable(extra) {
    validate();
  }

  factory AccessibilityExtractionRule.fromJson(Map<String, dynamic> json) {
    String requireText(String key) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isEmpty) {
        if (key == 'activityName') {
          throw const FormatException('请输入 activityName');
        }
        throw FormatException('$key 不能为空');
      }
      return value;
    }

    bool readBool(String key, bool fallback) {
      if (!json.containsKey(key)) return fallback;
      final value = json[key];
      if (value is! bool) throw FormatException('$key 必须是布尔值');
      return value;
    }

    int readInt(String key, int fallback) {
      if (!json.containsKey(key)) return fallback;
      final value = json[key];
      if (value is! int) throw FormatException('$key 必须是整数');
      return value;
    }

    List<AccessibilityRuleDetail> readDetails(String key) {
      final value = json[key];
      if (value == null) return const [];
      if (value is! List) throw FormatException('$key 必须是数组');
      return value
          .asMap()
          .entries
          .map((entry) {
            final item = entry.value;
            if (item is! Map) {
              throw FormatException('$key[${entry.key}] 必须是对象');
            }
            try {
              return AccessibilityRuleDetail.fromJson(
                Map<String, dynamic>.from(item),
              );
            } on FormatException catch (error) {
              throw FormatException('$key[${entry.key}]：${error.message}');
            }
          })
          .toList(growable: false);
    }

    const knownKeys = {
      'ruleName',
      'packageName',
      'activityName',
      'contentRules',
      'paymentRules',
      'continueOnContentFailure',
      'triggerOnEmptyNodes',
      'emptyNodeTriggerCooldownMs',
      'preFilterByKeywords',
      'allowContentChangeTrigger',
      'hasPaymentInfo',
      'maxContentTriggerTimes',
      'dynamicRetryTimes',
      'dynamicRetryIntervalMs',
    };
    final extra = Map<String, dynamic>.from(json)
      ..removeWhere((key, _) => knownKeys.contains(key));

    return AccessibilityExtractionRule(
      ruleName: requireText('ruleName'),
      packageName: requireText('packageName'),
      activityName: requireText('activityName'),
      contentRules: readDetails('contentRules'),
      paymentRules: readDetails('paymentRules'),
      continueOnContentFailure: readBool('continueOnContentFailure', false),
      triggerOnEmptyNodes: readBool('triggerOnEmptyNodes', false),
      emptyNodeTriggerCooldownMs: readInt('emptyNodeTriggerCooldownMs', 120000),
      preFilterByKeywords: readBool('preFilterByKeywords', false),
      allowContentChangeTrigger: readBool('allowContentChangeTrigger', false),
      hasPaymentInfo: readBool('hasPaymentInfo', true),
      maxContentTriggerTimes: readInt('maxContentTriggerTimes', 2),
      dynamicRetryTimes: readInt('dynamicRetryTimes', 0),
      dynamicRetryIntervalMs: readInt('dynamicRetryIntervalMs', 1000),
      extra: extra,
    );
  }

  factory AccessibilityExtractionRule.defaultForPackage(String packageName) {
    return AccessibilityExtractionRule(
      ruleName: 'Rule for $packageName',
      packageName: packageName,
      activityName: '填写 Activity 类名，支持后缀匹配',
      contentRules: [
        AccessibilityRuleDetail(
          keywords: const ['支付成功', '交易成功'],
          strategy: const {
            'type': 'ExtractByViewId',
            'viewId': 'pkgname:id/view_id',
            'useExactMatch': true,
          },
        ),
      ],
      paymentRules: [
        AccessibilityRuleDetail(
          keywords: const ['付款方式', '交易方式'],
          strategy: const {
            'type': 'SimpleOffset',
            'offset': 1,
            'useExactMatch': false,
          },
        ),
      ],
    );
  }

  void validate() {
    if (ruleName.trim().isEmpty || packageName.trim().isEmpty) {
      throw const FormatException('ruleName 和 packageName 不能为空');
    }
    if (activityName.trim().isEmpty) {
      throw const FormatException('请输入 activityName');
    }
    if (emptyNodeTriggerCooldownMs < 0 ||
        maxContentTriggerTimes < 1 ||
        dynamicRetryTimes < 0 ||
        dynamicRetryIntervalMs < 0) {
      throw const FormatException('冷却和重试参数不能为负数，最大触发次数至少为 1');
    }
    for (final detail in [...contentRules, ...paymentRules]) {
      detail.validate();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      'ruleName': ruleName,
      'packageName': packageName,
      'activityName': activityName,
      'contentRules': contentRules.map((item) => item.toJson()).toList(),
      'paymentRules': paymentRules.map((item) => item.toJson()).toList(),
      'continueOnContentFailure': continueOnContentFailure,
      'triggerOnEmptyNodes': triggerOnEmptyNodes,
      'emptyNodeTriggerCooldownMs': emptyNodeTriggerCooldownMs,
      'preFilterByKeywords': preFilterByKeywords,
      'allowContentChangeTrigger': allowContentChangeTrigger,
      'hasPaymentInfo': hasPaymentInfo,
      'maxContentTriggerTimes': maxContentTriggerTimes,
      'dynamicRetryTimes': dynamicRetryTimes,
      'dynamicRetryIntervalMs': dynamicRetryIntervalMs,
    };
  }
}

class AccessibilityExtractionRuleCodec {
  static AccessibilityExtractionRule parseRule(
    dynamic decoded, {
    required String packageName,
  }) {
    if (decoded is! Map) {
      throw const FormatException('单条规则 JSON 必须是对象');
    }
    final rule = AccessibilityExtractionRule.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (rule.packageName != packageName) {
      throw FormatException('packageName 必须是 "$packageName"');
    }
    return rule;
  }

  static List<AccessibilityExtractionRule> parseList(
    dynamic decoded, {
    required String packageName,
  }) {
    if (decoded is! List) {
      throw const FormatException('JSON 顶层必须是规则数组');
    }
    final rules = <AccessibilityExtractionRule>[];
    for (var index = 0; index < decoded.length; index++) {
      final item = decoded[index];
      if (item is! Map) {
        throw FormatException('第 ${index + 1} 条规则必须是对象');
      }
      try {
        rules.add(parseRule(item, packageName: packageName));
      } on FormatException catch (error) {
        throw FormatException('第 ${index + 1} 条规则：${error.message}');
      }
    }
    return rules;
  }

  static List<AccessibilityExtractionRule> parseJson(
    String source, {
    required String packageName,
  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('JSON 格式错误：${error.message}');
    }
    return parseList(decoded, packageName: packageName);
  }

  static AccessibilityExtractionRule parseRuleJson(
    String source, {
    required String packageName,
  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('JSON 格式错误：${error.message}');
    }
    return parseRule(decoded, packageName: packageName);
  }

  static String encode(
    List<AccessibilityExtractionRule> rules, {
    bool pretty = false,
  }) {
    final value = rules.map((rule) => rule.toJson()).toList(growable: false);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(value)
        : jsonEncode(value);
  }

  static String encodeRule(
    AccessibilityExtractionRule rule, {
    bool pretty = false,
  }) {
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(rule.toJson())
        : jsonEncode(rule.toJson());
  }
}
