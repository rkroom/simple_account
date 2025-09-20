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
  String? detailed;
  int? account;
  DateTime time;
  String accountText;
  List<int>? selectedCategory;
  String categoryText;
  int? categoryId;
  String? source;

  Bill({
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
  });

  @override
  String toString() {
    return 'ScheduleItem(id: $id, content: $content, date: $date, lastCompletedDate: $lastCompletedDate, finished: $finished, cycleValue: $cycleValue, created: $created, status: $status, dateSign: $dateSign,  finalDate: $finalDate)';
  }

  factory ScheduleItem.fromMap(Map<String, dynamic> map) {
    return ScheduleItem(
      id: map['id'],
      content: map['content'],
      date: map['date'],
      lastCompletedDate: map['last_completed_date'],
      finished: map['finished'],
      cycleValue: ScheduleCycle.values.byName(map['round']),
      created: map["createdf"],
      status: ScheduleStatus.values.byName(map['status']),
      dateSign: map['datesign'] ?? '',
      finalDate: map['finaldate'],
    );
  }
}
