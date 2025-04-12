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

    return await Hive.openBox('config',
        encryptionCipher: HiveAesCipher(keyValue));
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
}
