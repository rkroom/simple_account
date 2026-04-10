enum Transaction {
  income("income"),
  consume("consume"),
  transfer("transfer");

  // 定义一个存储字符串值的字段
  final String value;

  // 枚举的构造函数，用于初始化每个枚举值的字符串
  const Transaction(this.value);
}

enum AccountType {
  debt("debt"),
  asset("asset");

  final String value;

  const AccountType(this.value);
}

enum ScheduleCycle {
  day('每天'),
  week('每周'),
  month('每月'),
  year('每年'),
  once('一次'),
  custom('自定义'),

  quarterMonthDay('季度'),
  quarterDay('季度：自定义'),
  monthAfterDay('每月：自定义');

  final String label;
  const ScheduleCycle(this.label);

  static ScheduleCycle fromString(String value) {
    return ScheduleCycle.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ScheduleCycle.once,
    );
  }
}

enum ScheduleStatus {
  continuing('进行中', 'continuing'),
  finished('已完成', 'finshed'),
  giveup('已放弃', 'giveup');

  const ScheduleStatus(this.label, this.dbValue);
  final String label;
  final String dbValue;

  static ScheduleStatus fromString(String dbValue) {
    return ScheduleStatus.values.firstWhere(
      (e) => e.dbValue == dbValue,
      orElse: () => ScheduleStatus.continuing,
    );
  }
}
