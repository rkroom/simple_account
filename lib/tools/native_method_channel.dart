import 'package:flutter/services.dart';

class NativeMethodChannel {
  // 私有构造函数
  NativeMethodChannel._privateConstructor();

  // 提供一个公开的工厂构造函数
  static final NativeMethodChannel _instance =
      NativeMethodChannel._privateConstructor();

  // 获取实例的静态方法
  static NativeMethodChannel get instance => _instance;

  // MethodChannel 通道名，保证唯一
  static const MethodChannel _channel = MethodChannel('notification_listener');

  void setMethodCallHandler(
      Future<dynamic> Function(MethodCall call)? handler) {
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
    return await _channel.invokeMethod(
      'exportJsonToDownloads',
      {
        'fileContent': jsonString,
        'fileName': fileName,
      },
    );
  }

  Future copyToDownloads(String sourcePath, String fileName) async {
    return await _channel.invokeMethod(
      'copyToDownloads',
      {
        'sourcePath': sourcePath,
        'fileName': fileName,
      },
    );
  }
}
