import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeMethodChannel {
  NativeMethodChannel._privateConstructor();

  static final NativeMethodChannel _instance =
      NativeMethodChannel._privateConstructor();

  static NativeMethodChannel get instance => _instance;

  static const MethodChannel _channel = MethodChannel('channel_listener');

  void setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    _channel.setMethodCallHandler(handler);
  }

  // 调用原生方法
  Future<bool> checkNotificationListenerPermission() async {
    return await _channel.invokeMethod('checkNotificationPermission');
  }

  Future<void> minimizeApp() async {
    await _channel.invokeMethod('minimizeApp');
  }

  Future<void> requestNotificationListenerPermission() async {
    await _channel.invokeMethod('requestNotificationPermission');
  }

  Future getBills() async {
    return await _channel.invokeMethod('getBills');
  }

  Future clearBills() async {
    final count = await _channel.invokeMethod('clearBills');
    return count;
  }

  Future delBill(int index) async {
    return await _channel.invokeMethod('delBill', {'index': index});
  }

  Future exportJsonToDownloads(String jsonString, String fileName) async {
    return await _channel.invokeMethod('exportJsonToDownloads', {
      'fileContent': jsonString,
      'fileName': fileName,
    });
  }

  Future copyToDownloads(String sourcePath, String fileName) async {
    return await _channel.invokeMethod('copyToDownloads', {
      'sourcePath': sourcePath,
      'fileName': fileName,
    });
  }

  Future openAccessibilitySettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  Future<bool> checkAccessibilityPermission() async {
    var permission = await _channel.invokeMethod('isAccessibilityEnabled');
    return permission;
  }

  Future<void> putConfig(String key, String value) async {
    await _channel.invokeMethod('putConfig', {'key': key, 'value': value});
  }

  Future<String?> getConfig(String key) async {
    final result = await _channel.invokeMethod<String?>('getConfig', {
      'key': key,
    });
    return result;
  }

  Future<void> removeConfig(String key) async {
    await _channel.invokeMethod('removeConfig', {'key': key});
  }

  Future<void> clearAllConfig() async {
    await _channel.invokeMethod('clearAllConfig');
  }

  Future<List<Map<String, dynamic>>?> getAbAllowPackageConfig() async {
    final result = await _channel.invokeMethod<List<dynamic>?>(
      'getAbAllowPackageConfig',
    );
    if (result == null) return null;
    try {
      return result
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      return null;
    }
  }

  Future<void> putAbAllowPackageConfig(List<Map<String, dynamic>> value) async {
    await _channel.invokeMethod('putAbAllowPackageConfig', {'value': value});
  }

  Future<List<Map<String, dynamic>>?> getNlAllowPackageConfig() async {
    final result = await _channel.invokeMethod<List<dynamic>?>(
      'getNlAllowPackageConfig',
    );
    if (result == null) return null;
    try {
      return result
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      return null;
    }
  }

  Future<void> putNlAllowPackageConfig(List<Map<String, dynamic>> value) async {
    await _channel.invokeMethod('putNlAllowPackageConfig', {'value': value});
  }

  Future<List<String>?> getAllowKeywords() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod<List<dynamic>?>(
        'getAllowKeywords',
      );
      if (result == null) {
        return null;
      }
      return result.map((item) => item.toString()).toList();
    } catch (e) {
      return null;
    }
  }

  Future<void> putAllowKeywords(List<String> keywords) async {
    try {
      await _channel.invokeMethod('putAllowKeywords', {'keywords': keywords});
    } catch (e) {
      //
    }
  }

  Future<List<Map<String, dynamic>>> getExtractionRules() async {
    try {
      // 1. 调用原生方法，现在期望返回一个JSON字符串
      final String? rulesJsonString = await _channel.invokeMethod<String>(
        'getExtractionRules',
      );

      // 2. 如果返回的字符串为空，则返回一个空列表
      if (rulesJsonString == null || rulesJsonString.isEmpty) {
        return [];
      }

      // 3. 使用 dart:convert 解码JSON字符串
      final List<dynamic> decodedList = jsonDecode(rulesJsonString);

      // 4. 将解码后的列表转换为期望的类型 List<Map<String, dynamic>>
      return decodedList
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } on PlatformException catch (e) {
      debugPrint('Failed to get extraction rules: ${e.message}');
      return [];
    } catch (e) {
      debugPrint(
        'An unexpected error occurred while parsing extraction rules: $e',
      );
      return [];
    }
  }

  Future<void> putExtractionRules(List<Map<String, dynamic>> rules) async {
    try {
      final String jsonString = jsonEncode(rules);
      await _channel.invokeMethod('putExtractionRules', {'rules': jsonString});
    } catch (e) {
      debugPrint('Failed to put extraction rules: $e');
      // 可以根据需要处理异常
    }
  }

  /// 获取是否开启“窗口内容变化”监听
  Future<bool> getEnableWindowContentChange() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'getEnableWindowContentChange',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to get enableWindowContentChange: $e');
      return false;
    }
  }

  /// 设置是否开启“窗口内容变化”监听
  Future<void> putEnableWindowContentChange(bool value) async {
    try {
      await _channel.invokeMethod('putEnableWindowContentChange', {
        'value': value,
      });
    } catch (e) {
      debugPrint('Failed to put enableWindowContentChange: $e');
    }
  }
}
