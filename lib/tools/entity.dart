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

  Bill({
    this.detailed,
    this.account,
    required this.time,
    this.accountText = "请选择",
    this.selectedCategory,
    this.categoryText = "请选择",
    this.categoryId,
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
      selectedCategory: map['selectedCategory'],
      categoryText: map['consumeCategoryText'] ?? "请选择",
      categoryId: map['categoryId'],
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
    };
  }
}
