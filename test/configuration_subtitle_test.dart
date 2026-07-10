import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/pages/configuration.dart';
import 'package:simple_account/tools/entity.dart';

PackageConfig package({
  String packageName = 'com.example.app',
  String appName = '示例应用',
  bool isAllowed = true,
}) {
  return PackageConfig(
    packageName: packageName,
    appName: appName,
    isAllowed: isAllowed,
  );
}

void main() {
  group('监听应用摘要', () {
    test('显示预设及具体应用名称', () {
      expect(
        buildListeningAppsSubtitle([
          package(appName: '支付宝'),
          package(packageName: 'com.example.jd', appName: '京东'),
          package(packageName: 'com.example.taobao', appName: '淘宝'),
        ]),
        '预设：支付宝，京东，淘宝',
      );
    });

    test('空列表、全部禁用或无效配置显示未配置应用', () {
      expect(buildListeningAppsSubtitle(const []), '未配置应用');
      expect(buildListeningAppsSubtitle([package(isAllowed: false)]), '未配置应用');
      expect(buildListeningAppsSubtitle([package(packageName: '')]), '未配置应用');
      expect(buildListeningAppsSubtitle([package(appName: '...')]), '未配置应用');
    });
  });
}
