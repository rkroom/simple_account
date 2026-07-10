import 'dart:convert';

const int billParseRuleSchemaVersion = 1;
const String globalBillRulePackage = '*';

enum BillRuleTextSource { title, content, payment }

enum BillRuleFlow { consume, income, transfer }

class RawPendingBill {
  final String id;
  final String packageName;
  final String appName;
  final String title;
  final String content;
  final String payment;
  final int postTime;

  const RawPendingBill({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.content,
    required this.payment,
    required this.postTime,
  });

  factory RawPendingBill.fromJson(Map<String, dynamic> json) {
    int parsePostTime(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return RawPendingBill(
      id: json['id']?.toString() ?? '',
      packageName: json['packageName']?.toString() ?? '',
      appName: json['appName']?.toString() ?? 'Unknown',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      payment: json['payment']?.toString() ?? '',
      postTime: parsePostTime(json['postTime']),
    );
  }

  String textFor(BillRuleTextSource source) {
    switch (source) {
      case BillRuleTextSource.title:
        return title;
      case BillRuleTextSource.content:
        return content;
      case BillRuleTextSource.payment:
        return payment;
    }
  }
}

class BillParseRule {
  final String id;
  final String name;
  final String packageName;
  final bool enabled;
  final int priority;
  final List<String> titleContainsAny;
  final List<String> contentContainsAny;
  final List<String> paymentContainsAny;
  final BillRuleTextSource amountSource;
  final String amountPattern;
  final int amountGroup;
  final BillRuleFlow flow;
  final String? accountName;
  final String? categoryName;
  final String? commentTemplate;

  const BillParseRule({
    required this.id,
    required this.name,
    required this.packageName,
    required this.enabled,
    required this.priority,
    required this.titleContainsAny,
    required this.contentContainsAny,
    required this.paymentContainsAny,
    required this.amountSource,
    required this.amountPattern,
    required this.amountGroup,
    required this.flow,
    this.accountName,
    this.categoryName,
    this.commentTemplate,
  });

  factory BillParseRule.fromJsonString(String source) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('JSON 格式错误：${error.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('单条规则 JSON 必须是对象');
    }
    return BillParseRule.fromJson(Map<String, dynamic>.from(decoded));
  }

  factory BillParseRule.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw FormatException('规则字段 "$key" 不能为空');
      }
      return value;
    }

    String? optionalString(String key) {
      final value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    List<String> stringList(String key) {
      final value = json[key];
      if (value == null) return const [];
      if (value is! List) {
        throw FormatException('规则字段 "$key" 必须是字符串数组');
      }
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    int intValue(String key, int fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is int) return value;
      final parsed = int.tryParse(value.toString());
      if (parsed == null) {
        throw FormatException('规则字段 "$key" 必须是整数');
      }
      return parsed;
    }

    final amountSourceName =
        json['amountSource']?.toString() ?? BillRuleTextSource.content.name;
    final amountSource = _enumByName(
      BillRuleTextSource.values,
      amountSourceName,
      'amountSource',
    );

    final flowName = json['flow']?.toString() ?? BillRuleFlow.consume.name;
    final flow = _enumByName(BillRuleFlow.values, flowName, 'flow');

    final rule = BillParseRule(
      id: requiredString('id'),
      name: requiredString('name'),
      packageName: requiredString('packageName'),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      priority: intValue('priority', 0),
      titleContainsAny: stringList('titleContainsAny'),
      contentContainsAny: stringList('contentContainsAny'),
      paymentContainsAny: stringList('paymentContainsAny'),
      amountSource: amountSource,
      amountPattern: json['amountPattern']?.toString() ?? '',
      amountGroup: intValue('amountGroup', 0),
      flow: flow,
      accountName: optionalString('accountName'),
      categoryName: optionalString('categoryName'),
      commentTemplate: optionalString('commentTemplate'),
    );

    rule.validate();
    return rule;
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String name,
    String field,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException(
      '规则字段 "$field" 的值 "$name" 无效，可选值：'
      '${values.map((item) => item.name).join(', ')}',
    );
  }

  void validate() {
    if (id.trim().isEmpty ||
        name.trim().isEmpty ||
        packageName.trim().isEmpty) {
      throw const FormatException('规则 id、name 和 packageName 不能为空');
    }
    if (amountGroup < 0) {
      throw FormatException('规则 "$name" 的 amountGroup 不能小于 0');
    }
    if (amountPattern.isNotEmpty) {
      try {
        RegExp(amountPattern);
      } on FormatException catch (error) {
        throw FormatException('规则 "$name" 的金额正则无效：${error.message}');
      }
    }
  }

  BillParseRule copyWith({
    String? id,
    String? name,
    String? packageName,
    bool? enabled,
    int? priority,
    List<String>? titleContainsAny,
    List<String>? contentContainsAny,
    List<String>? paymentContainsAny,
    BillRuleTextSource? amountSource,
    String? amountPattern,
    int? amountGroup,
    BillRuleFlow? flow,
    String? accountName,
    bool clearAccountName = false,
    String? categoryName,
    bool clearCategoryName = false,
    String? commentTemplate,
    bool clearCommentTemplate = false,
  }) {
    return BillParseRule(
      id: id ?? this.id,
      name: name ?? this.name,
      packageName: packageName ?? this.packageName,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      titleContainsAny: titleContainsAny ?? this.titleContainsAny,
      contentContainsAny: contentContainsAny ?? this.contentContainsAny,
      paymentContainsAny: paymentContainsAny ?? this.paymentContainsAny,
      amountSource: amountSource ?? this.amountSource,
      amountPattern: amountPattern ?? this.amountPattern,
      amountGroup: amountGroup ?? this.amountGroup,
      flow: flow ?? this.flow,
      accountName: clearAccountName ? null : (accountName ?? this.accountName),
      categoryName:
          clearCategoryName ? null : (categoryName ?? this.categoryName),
      commentTemplate:
          clearCommentTemplate
              ? null
              : (commentTemplate ?? this.commentTemplate),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'packageName': packageName,
      'enabled': enabled,
      'priority': priority,
      'titleContainsAny': titleContainsAny,
      'contentContainsAny': contentContainsAny,
      'paymentContainsAny': paymentContainsAny,
      'amountSource': amountSource.name,
      'amountPattern': amountPattern,
      'amountGroup': amountGroup,
      'flow': flow.name,
      'accountName': accountName,
      'categoryName': categoryName,
      'commentTemplate': commentTemplate,
    };
  }

  String toJsonString({bool pretty = false}) {
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(toJson())
        : jsonEncode(toJson());
  }
}

class BillParseRuleDocument {
  final int schemaVersion;
  final List<BillParseRule> rules;

  BillParseRuleDocument({
    this.schemaVersion = billParseRuleSchemaVersion,
    required List<BillParseRule> rules,
  }) : rules = List.unmodifiable(rules) {
    validate();
  }

  factory BillParseRuleDocument.fromJsonString(String source) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('JSON 格式错误：${error.message}');
    }
    return BillParseRuleDocument.fromJson(decoded);
  }

  factory BillParseRuleDocument.fromJson(dynamic json) {
    dynamic normalizedJson = json;
    if (normalizedJson is List) {
      normalizedJson = <String, dynamic>{
        'schemaVersion': billParseRuleSchemaVersion,
        'rules': List<dynamic>.from(normalizedJson),
      };
    }
    if (normalizedJson is! Map) {
      throw const FormatException('规则 JSON 顶层必须是对象');
    }

    final map = Map<String, dynamic>.from(normalizedJson);
    final rawVersion = map['schemaVersion'] ?? billParseRuleSchemaVersion;
    final version =
        rawVersion is int ? rawVersion : int.tryParse(rawVersion.toString());
    if (version != billParseRuleSchemaVersion) {
      throw FormatException(
        '不支持 schemaVersion=$rawVersion，当前仅支持 '
        '$billParseRuleSchemaVersion',
      );
    }

    final rawRules = map['rules'];
    if (rawRules is! List) {
      throw const FormatException('规则 JSON 的 rules 必须是数组');
    }

    final rules = <BillParseRule>[];
    for (var index = 0; index < rawRules.length; index++) {
      final rawRule = rawRules[index];
      if (rawRule is! Map) {
        throw FormatException('第 ${index + 1} 条规则必须是对象');
      }
      try {
        rules.add(BillParseRule.fromJson(Map<String, dynamic>.from(rawRule)));
      } on FormatException catch (error) {
        throw FormatException('第 ${index + 1} 条规则无效：${error.message}');
      }
    }

    return BillParseRuleDocument(schemaVersion: version!, rules: rules);
  }

  //默认规则，可考虑移动到config_service.dart
  factory BillParseRuleDocument.defaults() {
    return BillParseRuleDocument(
      rules: [
        BillParseRule(
          id: 'builtin-jd-amount',
          name: '京东金额',
          packageName: 'com.jingdong.app.mall',
          enabled: true,
          priority: 100,
          titleContainsAny: const [],
          contentContainsAny: const [],
          paymentContainsAny: const [],
          amountSource: BillRuleTextSource.content,
          amountPattern: r'(\d+(?:\.\d{1,2})?)',
          amountGroup: 1,
          flow: BillRuleFlow.consume,
        ),
        BillParseRule(
          id: 'builtin-global-two-decimals',
          name: '通用两位小数金额',
          packageName: globalBillRulePackage,
          enabled: true,
          priority: 0,
          titleContainsAny: const [],
          contentContainsAny: const [],
          paymentContainsAny: const [],
          amountSource: BillRuleTextSource.content,
          amountPattern: r'(\d+\.\d{2})',
          amountGroup: 1,
          flow: BillRuleFlow.consume,
        ),
      ],
    );
  }

  void validate() {
    if (schemaVersion != billParseRuleSchemaVersion) {
      throw FormatException('不支持 schemaVersion=$schemaVersion');
    }
    final ids = <String>{};
    for (final rule in rules) {
      rule.validate();
      if (!ids.add(rule.id)) {
        throw FormatException('规则 id 重复：${rule.id}');
      }
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
    };
  }

  String toJsonString({bool pretty = false}) {
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(toJson())
        : jsonEncode(toJson());
  }
}

class BillRuleMatch {
  final BillParseRule rule;
  final String? amount;
  final String? comment;
  final String? accountName;

  const BillRuleMatch({
    required this.rule,
    required this.amount,
    required this.comment,
    required this.accountName,
  });
}

class BillParseRuleEngine {
  final BillParseRuleDocument document;

  const BillParseRuleEngine(this.document);

  BillRuleMatch? match(RawPendingBill bill) {
    final candidates =
        document.rules.asMap().entries.where((entry) {
          final rule = entry.value;
          return rule.enabled &&
              (rule.packageName == bill.packageName ||
                  rule.packageName == globalBillRulePackage);
        }).toList();

    candidates.sort((left, right) {
      final leftExact = left.value.packageName == bill.packageName;
      final rightExact = right.value.packageName == bill.packageName;
      if (leftExact != rightExact) return leftExact ? -1 : 1;

      final priority = right.value.priority.compareTo(left.value.priority);
      if (priority != 0) return priority;
      return left.key.compareTo(right.key);
    });

    BillParseRule? primaryRule;
    String? amount;
    String? comment;

    for (final entry in candidates) {
      final rule = entry.value;
      if (!_matchesRuleConditions(bill, rule)) continue;

      if (rule.amountPattern.isNotEmpty) {
        amount = _extractAmount(bill, rule);
        if (amount == null) continue;
      }

      primaryRule = rule;
      comment = _renderComment(rule.commentTemplate, bill, amount);
      break;
    }

    BillParseRule? accountRule;
    for (final entry in candidates) {
      final rule = entry.value;
      if (rule.accountName == null || !_matchesRuleConditions(bill, rule)) {
        continue;
      }
      accountRule = rule;
      break;
    }

    final matchedRule = primaryRule ?? accountRule;
    if (matchedRule == null) return null;
    return BillRuleMatch(
      rule: matchedRule,
      amount: amount,
      comment:
          comment ?? _renderComment(matchedRule.commentTemplate, bill, amount),
      accountName: accountRule?.accountName ?? primaryRule?.accountName,
    );
  }

  bool _matchesRuleConditions(RawPendingBill bill, BillParseRule rule) {
    return _matchesKeywords(bill.title, rule.titleContainsAny) &&
        _matchesKeywords(bill.content, rule.contentContainsAny) &&
        _matchesKeywords(bill.payment, rule.paymentContainsAny);
  }

  bool _matchesKeywords(String value, List<String> keywords) {
    if (keywords.isEmpty) return true;
    final normalized = value.toLowerCase();
    return keywords.any(
      (keyword) => normalized.contains(keyword.toLowerCase()),
    );
  }

  String? _extractAmount(RawPendingBill bill, BillParseRule rule) {
    final regex = RegExp(rule.amountPattern, caseSensitive: false);
    final match = regex.firstMatch(bill.textFor(rule.amountSource));
    if (match == null) return null;

    String? captured;
    try {
      captured = match.group(rule.amountGroup);
    } on RangeError {
      return null;
    }
    if (captured == null || captured.trim().isEmpty) return null;

    final compact = captured.replaceAll(',', '').replaceAll('，', '').trim();
    final numberMatch = RegExp(
      r'-?(?:\d+(?:\.\d*)?|\.\d+)',
    ).firstMatch(compact);
    if (numberMatch == null) return null;

    var amount = numberMatch.group(0)!;
    if (amount.startsWith('-')) amount = amount.substring(1);
    if (amount.startsWith('.')) amount = '0$amount';
    if (double.tryParse(amount) == null) return null;
    return amount;
  }

  String? _renderComment(
    String? template,
    RawPendingBill bill,
    String? amount,
  ) {
    if (template == null || template.isEmpty) return null;
    return template
        .replaceAll('{title}', bill.title)
        .replaceAll('{content}', bill.content)
        .replaceAll('{payment}', bill.payment)
        .replaceAll('{appName}', bill.appName)
        .replaceAll('{amount}', amount ?? '');
  }
}
