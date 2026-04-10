import 'dart:convert';

import 'config_enum.dart';

class Config {
  String path;
  String password;

  Config(this.path, this.password);
}

class PackageConfig {
  final String packageName;
  final String appName;
  bool isAllowed;

  PackageConfig({
    required this.packageName,
    required this.appName,
    required this.isAllowed,
  });

  factory PackageConfig.fromJson(Map<String, dynamic> json) {
    return PackageConfig(
      packageName: json['packageName'] as String,
      appName: json['appName'] as String,
      isAllowed: json['isAllowed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'appName': appName,
      'isAllowed': isAllowed,
    };
  }
}

class Bill {
  final String id;
  String? detailed;
  int? account;
  DateTime time;
  String accountText;
  List<int>? selectedCategory;
  String categoryText;
  int? categoryId;
  String? source;

  Bill({
    required this.id,
    this.detailed,
    this.account,
    required this.time,
    this.accountText = "请选择",
    this.selectedCategory,
    this.categoryText = "请选择",
    this.categoryId,
    this.source,
  });

  factory Bill.fromMap(Map<String, dynamic> map, String id) {
    return Bill(
      id: map['id'] ?? '',
      detailed: map['detailed'],
      account: map['account'],
      time:
          map['time'] is DateTime
              ? map['time']
              : DateTime.fromMillisecondsSinceEpoch(map['time'] ?? 0),
      accountText: map['consumeAccountText'],
      selectedCategory:
          map['selectedCategory'] != null
              ? List<int>.from(map['selectedCategory'])
              : null,
      categoryText: map['consumeCategoryText'] ?? "请选择",
      categoryId: map['categoryId'],
      source: map['source'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'detailed': detailed,
      'account': account,
      'time': time.millisecondsSinceEpoch,
      'consumeAccountText': accountText,
      'selectedCategory': selectedCategory,
      'consumeCategoryText': categoryText,
      'categoryId': categoryId,
      'source': source,
    };
  }
}

class ScheduleItem {
  final int id;
  final String content;
  final String date;
  final String? lastCompletedDate;
  final String? finished;
  final ScheduleCycle cycleValue;
  final String created;
  final ScheduleStatus status;
  final String dateSign;
  final String? finalDate;

  // 新增：扩展周期参数
  final Map<String, dynamic>? ruleParams;

  ScheduleItem({
    required this.id,
    required this.content,
    required this.date,
    this.lastCompletedDate,
    this.finished,
    required this.cycleValue,
    required this.created,
    required this.status,
    required this.dateSign,
    this.finalDate,
    this.ruleParams,
  });

  @override
  String toString() {
    return 'ScheduleItem('
        'id: $id, '
        'content: $content, '
        'date: $date, '
        'lastCompletedDate: $lastCompletedDate, '
        'finished: $finished, '
        'cycleValue: $cycleValue, '
        'created: $created, '
        'status: $status, '
        'dateSign: $dateSign, '
        'finalDate: $finalDate, '
        'ruleParams: $ruleParams'
        ')';
  }

  static Map<String, dynamic>? _parseRuleParams(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;

    final text = raw.toString().trim();
    if (text.isEmpty) return null;

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  factory ScheduleItem.fromMap(Map<String, dynamic> map) {
    final String cycleRaw =
        (map['rule_type'] ?? map['round'] ?? ScheduleCycle.once.name)
            .toString();

    final String createdValue =
        (map['createdf'] ?? map['created'] ?? '').toString();

    final String statusRaw =
        (map['status'] ?? ScheduleStatus.continuing.name).toString();

    return ScheduleItem(
      id: map['id'],
      content: map['content']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      lastCompletedDate: map['last_completed_date']?.toString(),
      finished: map['finished']?.toString(),
      cycleValue: ScheduleCycle.fromString(cycleRaw),
      created: createdValue,
      status: ScheduleStatus.fromString(statusRaw),
      dateSign: map['datesign']?.toString() ?? '',
      finalDate: map['finaldate']?.toString(),
      ruleParams: _parseRuleParams(map['rule_params']),
    );
  }
}
