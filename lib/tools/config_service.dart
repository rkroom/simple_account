import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'entity.dart';

class ConfigService {
  // 单例模式
  static final ConfigService _singleton = ConfigService._internal();
  factory ConfigService() => _singleton;
  ConfigService._internal();

  // 私有的 Box 实例以及 Future，用于延迟初始化
  static Future<Box>? _boxFuture;

  // 获取 Box 实例，使用延迟初始化
  Future<Box> get _box async {
    return _boxFuture ??= _initialize();
  }

  // 初始化 Hive Box
  Future<Box> _initialize() async {
    await Hive.initFlutter();

    const FlutterSecureStorage storage = FlutterSecureStorage();
    const key = 'KEY';
    var existingValue = await storage.read(key: key);
    List<int>? keyValue;
    if (existingValue != null) {
      keyValue = base64Decode(existingValue);
    } else {
      // 如果不存在，随机生成
      keyValue = List.generate(32, (_) => Random.secure().nextInt(256));
      var encodedValue = base64Encode(keyValue);
      await storage.write(key: key, value: encodedValue);
    }

    return await Hive.openBox(
      'config',
      encryptionCipher: HiveAesCipher(keyValue),
    );
  }

  // 获取数据库路径
  Future<String?> getDBPath() async {
    var box = await _box;
    return box.get("path", defaultValue: null);
  }

  // 设置数据库路径
  Future<void> setDBPath(String path) async {
    var box = await _box;
    await box.put("path", path);
  }

  // 获取数据库密码
  Future<String?> getDBPassword() async {
    var box = await _box;
    return box.get("password", defaultValue: null);
  }

  // 设置数据库密码
  Future<void> setDBPassword(String password) async {
    var box = await _box;
    await box.put("password", password);
  }

  Future<Config?> getConfig() async {
    var box = await _box;
    var path = box.get("path", defaultValue: null);
    if (path == null) {
      return null;
    }
    var password = box.get("password");
    return Config(path, password);
  }

  // 获取后台通知状态
  Future<bool> getNotificationRegistered() async {
    var box = await _box;
    return box.get("isNotificationRegistered", defaultValue: false);
  }

  // 设置通知注册状态
  Future<void> setNotificationRegistered(bool succeeded) async {
    var box = await _box;
    return box.put("isNotificationRegistered", succeeded);
  }

  // 获取后台任务执行时间
  Future<DateTime?> getScheduledTaskTime() async {
    var box = await _box;
    return box.get("scheduledTaskTime", defaultValue: null);
  }

  // 设置后台任务执行时间
  Future<void> setScheduledTaskTime(DateTime time) async {
    var box = await _box;
    box.put("scheduledTaskTime", time);
  }

  Future<bool> getAppInstructions() async {
    var box = await _box;
    return box.get("appInstructions", defaultValue: false);
  }

  Future<void> setAppInstructions(bool read) async {
    var box = await _box;
    return box.put("appInstructions", read);
  }

  Future<bool> getNotificationTaskStatus() async {
    var box = await _box;
    return box.get("notificationTaskStatus", defaultValue: false);
  }

  Future<void> setNotificationTaskStatus(bool status) async {
    var box = await _box;
    return box.put("notificationTaskStatus", status);
  }

  Future<Map<String, int>> getNotificationTaskTime() async {
    var box = await _box;
    // 直接 await，确保返回的是 Map<dynamic, dynamic>
    final raw = await box.get(
      "notificationTaskTime",
      defaultValue: {"hour": 11, "minute": 0, "second": 0},
    );
    return Map<String, int>.from(
      raw.cast<String, dynamic>(),
    ).map((k, v) => MapEntry(k, v));
  }

  Future<void> setNotificationTaskTime(Map<String, int> time) async {
    var box = await _box;
    return box.put("notificationTaskTime", time);
  }

  Future<bool> getScheduleNotificationTaskStatus() async {
    var box = await _box;
    return box.get("ScheduleNotificationTaskStatus", defaultValue: false);
  }

  Future<void> setScheduleNotificationTaskStatus(bool status) async {
    var box = await _box;
    return box.put("ScheduleNotificationTaskStatus", status);
  }

  Future<Map<String, int>> getScheduleNotificationTaskTime() async {
    var box = await _box;
    final raw = await box.get(
      "scheduleNotificationTaskTime",
      defaultValue: {"hour": 6, "minute": 0, "second": 0},
    );
    return Map<String, int>.from(
      raw.cast<String, dynamic>(),
    ).map((k, v) => MapEntry(k, v));
  }

  Future<void> setScheduleNotificationTaskTime(Map<String, int> time) async {
    var box = await _box;
    return box.put("scheduleNotificationTaskTime", time);
  }

  Future<bool> getPendingBillNotificationTaskStatus() async {
    var box = await _box;
    return box.get("pendingBillNotificationTaskStatus", defaultValue: false);
  }

  Future<void> setPendingBillNotificationTaskStatus(bool status) async {
    var box = await _box;
    return box.put("pendingBillNotificationTaskStatus", status);
  }

  Future<Map<String, int>> getPendingBillNotificationTaskTime() async {
    var box = await _box;
    final raw = await box.get(
      "pendingBillNotificationTaskTime",
      defaultValue: {"hour": 19, "minute": 0, "second": 0},
    );
    return Map<String, int>.from(
      raw.cast<String, dynamic>(),
    ).map((k, v) => MapEntry(k, v));
  }

  Future<void> setPendingBillNotificationTaskTime(Map<String, int> time) async {
    var box = await _box;
    return box.put("pendingBillNotificationTaskTime", time);
  }

  Future<bool> getSavedAccConfig() async {
    var box = await _box;
    return box.get("accConfig", defaultValue: false);
  }

  Future<void> setSavedAccConfig(bool hasSaved) async {
    var box = await _box;
    return box.put("accConfig", hasSaved);
  }

  Future<bool> getSavedNlConfig() async {
    var box = await _box;
    return box.get("nlConfig", defaultValue: false);
  }

  Future<void> setSavedNlConfig(bool hasSaved) async {
    var box = await _box;
    return box.put("nlConfig", hasSaved);
  }

  Future<bool> getBiometricUnlockEnabled() async {
    var box = await _box;
    return box.get("biometricUnlockEnabled", defaultValue: false);
  }

  Future<void> setBiometricUnlockEnabled(bool enabled) async {
    var box = await _box;
    return box.put("biometricUnlockEnabled", enabled);
  }

  Future<bool> resetSettings() async {
    var box = await _box;
    try {
      await box.delete("notificationTaskStatus");
      await box.delete("notificationTaskTime");
      await box.delete("ScheduleNotificationTaskStatus");
      await box.delete("scheduleNotificationTaskTime");
      await box.delete("pendingBillNotificationTaskStatus");
      await box.delete("pendingBillNotificationTaskTime");
      await box.delete("accConfig");
      await box.delete("nlConfig");
      await box.delete("biometricUnlockEnabled");
      return true;
    } catch (e) {
      //debugPrint(e.toString());
      return false;
    }
  }
}
