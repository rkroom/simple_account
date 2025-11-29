import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../tools/config.dart';
import '../tools/config_service.dart';
import '../tools/entity.dart';
import '../tools/native_method_channel.dart';
import '../tools/tools.dart';
import '../tools/workmanager_tool.dart';
import '../widgets/app_selection_screen.dart';

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
  bool _scheduleNotificationTaskChecked = false;
  bool _enableWindowContentChange = false;
  bool _isLoading = true;
  bool _savedAccConfig = false;
  bool _savedNlConfig = false;

  int _taskHour = 0;
  int _taskMinute = 0;
  int _taskSecond = 0;

  int _scheduleTaskHour = 0;
  int _scheduleTaskMinute = 0;
  int _scheduleTaskSecond = 0;

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

  Future<void> _navigateToAppSelection(ConfigType configType) async {
    try {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AppSelectionScreen(configType: configType),
        ),
      );
      _initializePermissionsAndTime();
    } catch (e) {
      if (!mounted) return;
      showNoticeSnackBar(context, '无法获取应用列表，请检查应用权限。错误: $e');
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
      final enableWindowChange =
          await NativeMethodChannel.instance.getEnableWindowContentChange();

      final savedAcc = await ConfigService().getSavedAccConfig();
      final savedNl = await ConfigService().getSavedNlConfig();

      // 每日任务
      final taskStatus = await ConfigService().getNotificationTaskStatus();
      final savedTime = await ConfigService().getNotificationTaskTime();

      // 计划任务
      final scheduleTaskStatus =
          await ConfigService().getScheduleNotificationTaskStatus();
      final savedScheduleTime =
          await ConfigService().getScheduleNotificationTaskTime();

      final List<Map<String, dynamic>>? rawAbData =
          await NativeMethodChannel.instance.getAbAllowPackageConfig();
      final List<Map<String, dynamic>>? rawNlData =
          await NativeMethodChannel.instance.getNlAllowPackageConfig();

      final List<PackageConfig> abPackages =
          rawAbData?.map((data) => PackageConfig.fromJson(data)).toList() ?? [];
      final List<PackageConfig> nlPackages =
          rawNlData?.map((data) => PackageConfig.fromJson(data)).toList() ?? [];

      if (!mounted) return;
      setState(() {
        _accessibilityChecked = acc;
        _notificationChecked = noti;
        _postNotificationChecked = postNoti;
        _enableWindowContentChange = enableWindowChange;
        _savedAccConfig = savedAcc;
        _savedNlConfig = savedNl;

        _notificationTaskChecked = taskStatus;
        _taskHour = savedTime['hour']!;
        _taskMinute = savedTime['minute']!;
        _taskSecond = savedTime['second']!;

        _scheduleNotificationTaskChecked = scheduleTaskStatus;
        _scheduleTaskHour = savedScheduleTime['hour']!;
        _scheduleTaskMinute = savedScheduleTime['minute']!;
        _scheduleTaskSecond = savedScheduleTime['second']!;

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
        if (_notificationTaskChecked) {
          await WorkmanagerTool.scheduleDailyTask();
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

  void _pickScheduleTaskTime() {
    DatePicker.showTimePicker(
      context,
      showSecondsColumn: true,
      currentTime: DateTime(
        0,
        0,
        0,
        _scheduleTaskHour,
        _scheduleTaskMinute,
        _scheduleTaskSecond,
      ),
      locale: LocaleType.zh,
      onConfirm: (DateTime dt) async {
        final newTime = {
          'hour': dt.hour,
          'minute': dt.minute,
          'second': dt.second,
        };
        await ConfigService().setScheduleNotificationTaskTime(newTime);

        if (_scheduleNotificationTaskChecked) {
          await WorkmanagerTool.scheduleNotificationTask();
        }

        if (!mounted) return;
        setState(() {
          _scheduleTaskHour = dt.hour;
          _scheduleTaskMinute = dt.minute;
          _scheduleTaskSecond = dt.second;
        });
      },
    );
  }

  String _getSubtitleText(List<PackageConfig> packages) {
    if (packages.isEmpty) {
      return '未配置应用';
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
          title: const Text('确认'),
          content: const Text('您确定要重置设置吗？此操作不可撤销（已授予权限需要您到系统设置页面手动取消）。'),
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
        await ConfigService().resetSettings();
        await NativeMethodChannel.instance.clearAllConfig();

        await WorkmanagerTool.cancelDailyTask();
        await WorkmanagerTool.cancelScheduleNotificationTask();

        if (mounted) {
          showNoticeSnackBar(context, '已成功重置所有设置');
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

  Future<void> _handleExportSettings() async {
    final confirmExport = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('导出配置'),
          content: const Text('您要将当前的自动服务配置导出为一个 JSON 文件吗？'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('导出'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmExport != true) return;

    setState(() => _isLoading = true);
    try {
      final abConfig =
          await NativeMethodChannel.instance.getAbAllowPackageConfig() ?? [];
      final nlConfig =
          await NativeMethodChannel.instance.getNlAllowPackageConfig() ?? [];
      final keywords =
          await NativeMethodChannel.instance.getAllowKeywords() ?? [];
      final rules = await NativeMethodChannel.instance.getExtractionRules();

      final allConfigs = {
        'abPackageConfig': abConfig,
        'nlPackageConfig': nlConfig,
        'nlKeywords': keywords,
        'extractionRules': rules,
      };

      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(allConfigs);

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'config_$timestamp.json';

      final savedPath = await NativeMethodChannel.instance
          .exportJsonToDownloads(jsonString, fileName);

      if (mounted) {
        showNoticeSnackBar(context, '配置已成功导出到: $savedPath');
      }
    } catch (e) {
      if (mounted) {
        showNoticeSnackBar(context, '导出配置失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleImportSettings() async {
    final confirmImport = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('导入配置'),
          content: const Text('您确定要导入配置文件吗？此操作将清空并覆盖您当前的自动服务设置。'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('确定导入'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmImport != true) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);
        final filePath = result.files.single.path!;
        final file = File(filePath);
        final jsonString = await file.readAsString();
        final decodedJson = jsonDecode(jsonString) as Map<String, dynamic>;

        final abConfigRaw = decodedJson['abPackageConfig'];
        final nlConfigRaw = decodedJson['nlPackageConfig'];
        final keywordsRaw = decodedJson['nlKeywords'];
        final rulesRaw = decodedJson['extractionRules'];

        if (abConfigRaw is! List ||
            nlConfigRaw is! List ||
            keywordsRaw is! List ||
            (rulesRaw != null && rulesRaw is! List)) {
          throw Exception('配置文件格式无效。');
        }

        final abConfig =
            (abConfigRaw)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
        final nlConfig =
            (nlConfigRaw)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
        final keywords = (keywordsRaw).map((item) => item.toString()).toList();
        final rules =
            (rulesRaw as List<dynamic>?)
                ?.map((item) => Map<String, dynamic>.from(item as Map))
                .toList() ??
            [];

        await NativeMethodChannel.instance.clearAllConfig();
        await NativeMethodChannel.instance.putAbAllowPackageConfig(abConfig);
        await NativeMethodChannel.instance.putNlAllowPackageConfig(nlConfig);
        await NativeMethodChannel.instance.putAllowKeywords(keywords);
        await NativeMethodChannel.instance.putExtractionRules(rules);

        if (mounted) {
          showNoticeSnackBar(context, '配置已成功导入');
          await _initializePermissionsAndTime();
        }
      } else {
        if (mounted) {
          showNoticeSnackBar(context, '未选择文件');
        }
      }
    } catch (e) {
      if (mounted) {
        showNoticeSnackBar(context, '导入配置失败: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> handleDailyNotificationToggle(bool newCheckedState) async {
    await ConfigService().setNotificationTaskStatus(newCheckedState);
    if (newCheckedState) {
      await WorkmanagerTool.scheduleDailyTask();
    } else {
      await WorkmanagerTool.cancelDailyTask();
    }
    if (!mounted) return;
    setState(() {
      _notificationTaskChecked = newCheckedState;
    });
  }

  Future<void> handleScheduleNotificationToggle(bool newCheckedState) async {
    await ConfigService().setScheduleNotificationTaskStatus(newCheckedState);
    if (newCheckedState) {
      await WorkmanagerTool.scheduleNotificationTask();
    } else {
      await WorkmanagerTool.cancelScheduleNotificationTask();
    }

    if (!mounted) return;
    setState(() {
      _scheduleNotificationTaskChecked = newCheckedState;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String abSubtitle =
        _savedAccConfig
            ? _getSubtitleText(_abAllowedPackages)
            : '预设：${_getSubtitleText(_abAllowedPackages)}';

    final String nlSubtitle =
        _savedNlConfig
            ? _getSubtitleText(_nlAllowedPackages)
            : '预设：${_getSubtitleText(_nlAllowedPackages)}';
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

    final scheduleTimeLabel =
        '${_scheduleTaskHour.toString().padLeft(2, '0')}:'
        '${_scheduleTaskMinute.toString().padLeft(2, '0')}:'
        '${_scheduleTaskSecond.toString().padLeft(2, '0')}';

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
              onTap: () {
                _navigateToAppSelection(ConfigType.acc);
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              title: const Text('内容变化监听'),
              subtitle: const Text(
                '开启后可识别动态刷新的页面，可能会增加耗电。需开启辅助功能权限。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: Checkbox(
                value: _enableWindowContentChange,
                onChanged: (bool? newValue) async {
                  if (newValue != null) {
                    // 1. 调用原生方法保存配置
                    await NativeMethodChannel.instance
                        .putEnableWindowContentChange(newValue);

                    // 2. 更新界面状态
                    setState(() {
                      _enableWindowContentChange = newValue;
                    });
                  }
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onTap: () async {
                // 点击整行也能切换
                final newValue = !_enableWindowContentChange;
                await NativeMethodChannel.instance.putEnableWindowContentChange(
                  newValue,
                );
                setState(() {
                  _enableWindowContentChange = newValue;
                });
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
              onTap: () {
                _navigateToAppSelection(ConfigType.nl);
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
                  if (checked == true) {
                    registerNotification();
                  }
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
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              title: const Text('计划通知开关'),
              trailing: Checkbox(
                value: _scheduleNotificationTaskChecked,
                onChanged: (bool? checked) async {
                  if (checked == true) {
                    registerNotification();
                  }
                  if (checked != null) {
                    await handleScheduleNotificationToggle(checked);
                  }
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onTap: () async {
                await handleScheduleNotificationToggle(
                  !_scheduleNotificationTaskChecked,
                );
              },
            ),
            ListTile(
              title: const Text('检测计划时间'),
              subtitle: Text(scheduleTimeLabel),
              trailing: IconButton(
                icon: const Icon(Icons.access_time),
                onPressed: _pickScheduleTaskTime,
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
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
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _handleImportSettings,
                    child: const Text('导入配置文件'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _handleExportSettings,
                    child: const Text('导出配置文件'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
