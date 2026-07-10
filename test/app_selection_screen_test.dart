import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/widgets/app_selection_screen.dart';

void main() {
  group('应用选择数据', () {
    test('进入页面时剔除已卸载但仍被选中的应用', () {
      final result = processAppSelectionData({
        'apps': [
          {'name': '已安装应用', 'packageName': 'com.example.installed'},
        ],
        'config': [
          {
            'appName': '已安装应用',
            'packageName': 'com.example.installed',
            'isAllowed': true,
          },
          {
            'appName': '已卸载应用',
            'packageName': 'com.example.removed',
            'isAllowed': true,
          },
        ],
      });

      expect(result['selectedList'], ['com.example.installed']);
      expect(result['selectionWasPruned'], isTrue);
    });

    test('所有已选应用均已安装时无需更新配置', () {
      final result = processAppSelectionData({
        'apps': [
          {'name': '已安装应用', 'packageName': 'com.example.installed'},
        ],
        'config': [
          {
            'appName': '已安装应用',
            'packageName': 'com.example.installed',
            'isAllowed': true,
          },
        ],
      });

      expect(result['selectedList'], ['com.example.installed']);
      expect(result['selectionWasPruned'], isFalse);
    });
  });
}
