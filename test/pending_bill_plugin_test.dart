import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pending_bill_plugin/pending_bill_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.rkroom.simple_account/pending_bills');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reads the pending bill count from the headless plugin', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return 3;
    });

    expect(await PendingBillPlugin.getPendingBillCount(), 3);
    expect(receivedCall?.method, 'getPendingBillCount');
  });

  test('uses zero when the native provider returns null', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(await PendingBillPlugin.getPendingBillCount(), 0);
  });

  test('uses zero on platforms without a native implementation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(await PendingBillPlugin.getPendingBillCount(), 0);
  });
}
