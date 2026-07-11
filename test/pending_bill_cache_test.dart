import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/tools/pending_bill_cache.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pending_bill_cache_test',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  PendingBillCache createCache() {
    return PendingBillCache(directoryProvider: () async => temporaryDirectory);
  }

  test('reads the pending bill count', () async {
    final cache = createCache();
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}'
      '${PendingBillCache.fileName}',
    );
    await file.writeAsString('3');

    expect(await cache.readCount(), 3);
  });

  test('returns zero when the cache is missing or invalid', () async {
    final cache = createCache();
    expect(await cache.readCount(), 0);

    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}'
      '${PendingBillCache.fileName}',
    );
    await file.writeAsString('invalid');

    expect(await cache.readCount(), 0);
  });
}
