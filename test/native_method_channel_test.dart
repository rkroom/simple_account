import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/tools/native_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('channel_listener');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('exportJsonToDownloads forwards JSON content and file name', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return 'Download/bill_rules.json';
    });

    final result = await NativeMethodChannel.instance.exportJsonToDownloads(
      '{"schemaVersion":1,"rules":[]}',
      'bill_rules.json',
    );

    expect(result, 'Download/bill_rules.json');
    expect(receivedCall?.method, 'exportJsonToDownloads');
    expect(receivedCall?.arguments, {
      'fileContent': '{"schemaVersion":1,"rules":[]}',
      'fileName': 'bill_rules.json',
    });
  });
}
