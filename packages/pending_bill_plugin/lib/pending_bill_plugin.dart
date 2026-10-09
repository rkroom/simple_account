import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PendingBillPlugin {
  PendingBillPlugin._();

  static const MethodChannel _channel = MethodChannel(
    'com.rkroom.simple_account/pending_bills',
  );

  static Future<int> getPendingBillCount() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return 0;
    }

    final count = await _channel.invokeMethod<int>('getPendingBillCount');
    return count ?? 0;
  }
}
