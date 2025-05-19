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

  Future<int?> clearAllConfig() async {
    final result = await _channel.invokeMethod<int?>('clearAllConfig');
    return result;
  }

  Future<void> putConfigList(
    String key,
    List<Map<String, dynamic>> value,
  ) async {
    await _channel.invokeMethod('putConfigList', {'key': key, 'value': value});
  }

  Future<List<Map<String, dynamic>>?> getConfigList(String key) async {
    final result = await _channel.invokeMethod<List<dynamic>?>(
      'getConfigList',
      {'key': key},
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
}
