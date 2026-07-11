import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef PendingBillDirectoryProvider = Future<Directory> Function();

class PendingBillCache {
  static const String fileName = 'pending_bill_count';

  PendingBillCache({PendingBillDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final PendingBillDirectoryProvider _directoryProvider;

  Future<int> readCount() async {
    try {
      final file = await _cacheFile();
      final value = int.tryParse((await file.readAsString()).trim());
      return value != null && value > 0 ? value : 0;
    } on FileSystemException {
      return 0;
    }
  }

  Future<File> _cacheFile() async {
    final directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }
}
