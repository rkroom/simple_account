import 'package:flutter/material.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:simple_account/tools/config.dart';
import 'package:simple_account/tools/config_service.dart';
import 'package:simple_account/tools/entity.dart';
import 'package:simple_account/tools/native_method_channel.dart';
import 'package:simple_account/tools/tools.dart';
import 'package:simple_account/tools/workmanager_tool.dart';

class ConfigurationWidget extends StatefulWidget {
  const ConfigurationWidget({super.key});

  @override
  State<ConfigurationWidget> createState() => ConfigurationWidgetState();
}

class ConfigurationWidgetState extends State<ConfigurationWidget>
    with WidgetsBindingObserver {
  bool _accessibilityChecked = false;
  bool _notificationChecked = false;
  bool _postNotificationChecked = false;
  bool _notificationTaskChecked = false;
  bool _isLoading = true;

  int _taskHour = 0;
  int _taskMinute = 0;
  int _taskSecond = 0;

  List<PackageConfig> _abAllowedPackages = [];
  List<PackageConfig> _nlAllowedPackages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePermissionsAndTime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializePermissionsAndTime();
    }
  }

  Future<void> _initializePermissionsAndTime() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final acc =
          await NativeMethodChannel.instance.checkAccessibilityPermission();
      final noti =
          await NativeMethodChannel.instance
              .checkNotificationListenerPermission();
      PermissionStatus status = await Permission.notification.status;
      final postNoti = status == PermissionStatus.granted;
      final taskStatus = await ConfigService().getNotificationTaskStatus();
      final savedTime = await ConfigService().getNotificationTaskTime();

      final List<Map<String, dynamic>>? rawAbData =
          await NativeMethodChannel.instance.getAbAllowPackageConfig();
      final List<Map<String, dynamic>>? rawNlData =
          await NativeMethodChannel.instance.getNlAllowPackageConfig();

      final List<PackageConfig> abPackages =
          rawAbData!.map((data) => PackageConfig.fromJson(data)).toList();
      final List<PackageConfig> nlPackages =
          rawNlData!.map((data) => PackageConfig.fromJson(data)).toList();

      if (!mounted) return;
      setState(() {
        _accessibilityChecked = acc;
        _notificationChecked = noti;
        _postNotificationChecked = postNoti;
        _notificationTaskChecked = taskStatus;
        _taskHour = savedTime['hour']!;
        _taskMinute = savedTime['minute']!;
        _taskSecond = savedTime['second']!;
        _abAllowedPackages = abPackages;
        _nlAllowedPackages = nlPackages;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      showNoticeSnackBar(context, '加载配置失败: $e');
    }
  }

  void _pickTaskTime() {
    DatePicker.showTimePicker(
      context,
      showSecondsColumn: true,
      currentTime: DateTime(0, 0, 0, _taskHour, _taskMinute, _taskSecond),
      locale: LocaleType.zh,
      onConfirm: (DateTime dt) async {
        final newTime = {
          'hour': dt.hour,
          'minute': dt.minute,
          'second': dt.second,
        };
        await ConfigService().setNotificationTaskTime(newTime);
        bool notificationTaskStatus =
            await ConfigService().getNotificationTaskStatus();
        if (notificationTaskStatus) {
          if (!Global.isWorkmanagerInit) {
            await initializeAndScheduleTask();
          }
          scheduleDailyTask();
        }
        if (!mounted) return;
        setState(() {
          _taskHour = dt.hour;
          _taskMinute = dt.minute;
          _taskSecond = dt.second;
        });
      },
    );
  }

  String _getSubtitleText(List<PackageConfig> packages) {
    if (packages.isEmpty) {
      return '未配置允许的应用';
    }
    final allowedAppNames =
        packages
            .where((pkg) => pkg.isAllowed)
            .map((pkg) => pkg.appName)
            .toList();
    if (allowedAppNames.isEmpty) {
      return '当前无已允许的应用';
    }
    return allowedAppNames.join(', ');
  }

  Future<void> _handleResetSettings() async {
    final confirmReset = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认操作'),
          content: const Text('您确定要重置设置吗？此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text('确定重置'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmReset == true) {
      setState(() => _isLoading = true);
      try {
        final count = await NativeMethodChannel.instance.clearAllConfig();
        if (mounted) {
          showNoticeSnackBar(
            context,
            count != null && count > 0 ? '已成功重置所有设置' : '没有设置被重置或操作失败',
          );
          await _initializePermissionsAndTime();
        }
      } catch (e) {
        if (mounted) {
          showNoticeSnackBar(context, '重置设置失败: $e');
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('配置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final timeLabel =
        '${_taskHour.toString().padLeft(2, '0')}:'
        '${_taskMinute.toString().padLeft(2, '0')}:'
        '${_taskSecond.toString().padLeft(2, '0')}';

    final String abSubtitle = _getSubtitleText(_abAllowedPackages);
    final String nlSubtitle = _getSubtitleText(_nlAllowedPackages);

    Future<void> handleDailyNotificationToggle(bool newCheckedState) async {
      await ConfigService().setNotificationTaskStatus(newCheckedState);
      if (newCheckedState) {
        if (!Global.isWorkmanagerInit) {
          await initializeAndScheduleTask();
        }
        scheduleDailyTask();
      } else {
        if (!Global.isWorkmanagerInit) {
          await initializeAndScheduleTask();
        }
        cancelDailyTask();
      }
      if (!mounted) return;
      setState(() {
        _notificationTaskChecked = newCheckedState;
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('配置')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              title: const Text('辅助功能权限'),
              subtitle: Text(
                abSubtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              trailing: Checkbox(
                value: _accessibilityChecked,
                onChanged: (bool? newValue) async {
                  Global.isReturningFromSettings = true;
                  await NativeMethodChannel.instance
                      .openAccessibilitySettings();
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onTap: () async {
                await Navigator.of(context).pushNamed(
                  '/billListenerConfig',
                  arguments: {'config': 'acc'},
                );
                if (mounted) {
                  _initializePermissionsAndTime();
                }
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              title: const Text('通知监听权限'),
              subtitle: Text(
                nlSubtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              trailing: Checkbox(
                value: _notificationChecked,
                onChanged: (bool? newValue) async {
                  Global.isReturningFromSettings = true;
                  await NativeMethodChannel.instance
                      .requestNotificationListenerPermission();
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onTap: () async {
                await Navigator.of(context).pushNamed(
                  '/billListenerConfig',
                  arguments: {'config': 'noti'},
                );
                if (mounted) {
                  _initializePermissionsAndTime();
                }
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              title: const Text('通知发布权限'),
              trailing: Checkbox(
                value: _postNotificationChecked,
                onChanged: (bool? newValue) async {
                  await openAppSettings();
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onTap: () async {
                await openAppSettings();
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              title: const Text('每日通知开关'),
              trailing: Checkbox(
                value: _notificationTaskChecked,
                onChanged: (bool? checked) async {
                  if (checked != null) {
                    await handleDailyNotificationToggle(checked);
                  }
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onTap: () async {
                await handleDailyNotificationToggle(!_notificationTaskChecked);
              },
            ),
            ListTile(
              title: const Text('通知触发时间'),
              subtitle: Text(timeLabel),
              trailing: IconButton(
                icon: const Icon(Icons.access_time),
                onPressed: _pickTaskTime,
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 20.0,
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _handleResetSettings,
                child: const Text(
                  '重置自动服务设置',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
