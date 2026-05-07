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

  static bool biometricUnlockEnabled = false;

  // 当前 App 进程会话是否已经完成解锁。
  static bool biometricUnlockedInCurrentSession = true;

  static Future init() async {
    externalStorageDirectory = (await getExternalStorageDirectory())!.path;
    config = await ConfigService().getConfig();
    jumpLoad = config != null;

    if (jumpLoad) {
      biometricUnlockEnabled =
          await ConfigService().getBiometricUnlockEnabled();

      // 如果开启了生物识别，则冷启动时默认未解锁。
      // 如果未开启生物识别，则视为已解锁。
      biometricUnlockedInCurrentSession = !biometricUnlockEnabled;
    } else {
      biometricUnlockEnabled = false;
      biometricUnlockedInCurrentSession = true;
    }
  }
}
