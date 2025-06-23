import 'package:path_provider/path_provider.dart';
import 'package:simple_account/tools/config_service.dart';
import 'entity.dart';

// 创建配置
createConfig(String path, String password) async {
  await ConfigService().setDBPath(path);
  await ConfigService().setDBPassword(password);
}

// 全局变量，用以储存全局需要用到的信息
class Global {
  // 配置信息
  static Config? config;
  // 是否跳过Loading页
  static bool jumpLoad = false;

  static bool isReturningFromSettings = false;

  static late String externalStorageDirectory;

  static Future init() async {
    externalStorageDirectory = (await getExternalStorageDirectory())!.path;
    config = await ConfigService().getConfig();
    if (config != null) {
      jumpLoad = true;
    }
  }
}
