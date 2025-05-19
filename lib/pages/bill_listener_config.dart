import 'package:flutter/material.dart';
import 'package:simple_account/tools/entity.dart';
import 'package:simple_account/tools/native_method_channel.dart';

import 'package:simple_account/tools/tools.dart';

class BillListenerConfigWidget extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const BillListenerConfigWidget({super.key, this.arguments});

  @override
  State<BillListenerConfigWidget> createState() =>
      _BillListenerConfigWidgetState();
}

class _BillListenerConfigWidgetState extends State<BillListenerConfigWidget> {
  List<PackageConfig> _packages = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _configType;
  String _appBarTitle = "加载配置中...";
  String _emptyDataMessage = '暂无可配置的应用';

  List<String> _keywords = [];
  final TextEditingController _keywordsController = TextEditingController();
  bool _isKeywordsLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          widget.arguments ??
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      if (args != null && args.containsKey('config')) {
        _configType = args['config'] as String?;
        if (_configType == 'acc') {
          _appBarTitle = "无障碍服务配置";
        } else if (_configType == 'noti') {
          _appBarTitle = "通知监听服务配置";
        } else {
          _appBarTitle = "未知配置";
          _configType = null;
        }
      } else {
        _appBarTitle = "缺少配置类型参数";
        _configType = null;
        debugPrint("错误: 未找到 'config' 参数。");
      }

      if (_configType != null) {
        _loadConfigs();
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _emptyDataMessage = '配置类型缺失或无效。';
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    if (_configType == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        if (_configType == 'noti') {
          _isKeywordsLoading = true;
        }
      });
    }

    try {
      List<Map<String, dynamic>>? rawPackagesData;

      if (_configType == 'acc') {
        rawPackagesData =
            await NativeMethodChannel.instance.getAbAllowPackageConfig();
      } else if (_configType == 'noti') {
        rawPackagesData =
            await NativeMethodChannel.instance.getNlAllowPackageConfig();

        try {
          final List<String>? keywordsData =
              await NativeMethodChannel.instance.getAllowKeywords();
          if (mounted) {
            setState(() {
              _keywords = keywordsData ?? [];
              _keywordsController.text = _keywords.join(', ');
              _isKeywordsLoading = false;
            });
          }
        } catch (e) {
          debugPrint('加载关键词失败: $e');
          if (mounted) {
            setState(() {
              _keywords = [];
              _keywordsController.text = '';
              _isKeywordsLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _appBarTitle = "内部错误";
            _emptyDataMessage = "遇到无效的配置类型。";
          });
        }
        debugPrint("内部逻辑错误: _loadConfigs 接收到未处理的 configType: $_configType");
        return;
      }

      if (rawPackagesData == null) {
        if (mounted) {
          setState(() {
            _packages = [];
            _isLoading = false;
            _emptyDataMessage = '未能获取配置数据或数据为空。';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _packages =
              rawPackagesData!
                  .map((data) => PackageConfig.fromJson(data))
                  .toList();
          _isLoading = false;
          if (_packages.isEmpty && _configType != 'noti') {
            _emptyDataMessage = '暂无可配置的应用。';
          } else if (_packages.isEmpty &&
              _configType == 'noti' &&
              _keywords.isEmpty &&
              !_isKeywordsLoading) {
            _emptyDataMessage = '暂无可配置的应用或关键词。';
          }
        });
      }
    } catch (e) {
      debugPrint('加载配置失败 ($_configType): $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _packages = [];
          _appBarTitle = "加载配置错误";
          _emptyDataMessage = '加载配置时发生错误。';
          if (_configType == 'noti') {
            _keywords = [];
            _keywordsController.text = '';
            _isKeywordsLoading = false;
          }
        });
      }
    }
  }

  void _updatePackagePermissionToggle(PackageConfig pkg, bool isAllowed) {
    if (mounted) {
      setState(() {
        final index = _packages.indexOf(pkg);
        if (index != -1) {
          _packages[index].isAllowed = isAllowed;
        }
      });
    }
  }

  Future<void> _saveConfiguration() async {
    // 如果正在加载，或者包列表和关键词列表都为空（且关键词输入框也为空），则不执行保存
    if (_isLoading ||
        _isKeywordsLoading ||
        (_configType == null ||
            (_packages.isEmpty &&
                _keywordsController.text.trim().isEmpty &&
                !_isLoading))) {
      if (mounted) {
        showNoticeSnackBar(context, "没有可保存的配置、配置类型无效或仍在加载数据。");
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isSaving = true;
      });
    }

    try {
      final List<Map<String, dynamic>> packageListToSave =
          _packages.map((pkg) => pkg.toJson()).toList();

      if (_configType == 'acc') {
        await NativeMethodChannel.instance.putAbAllowPackageConfig(
          packageListToSave,
        );
      } else if (_configType == 'noti') {
        await NativeMethodChannel.instance.putNlAllowPackageConfig(
          packageListToSave,
        );

        final List<String> keywordsToSave =
            _keywordsController.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
        await NativeMethodChannel.instance.putAllowKeywords(keywordsToSave);
        if (mounted) {
          setState(() {
            _keywords = keywordsToSave;
          });
        }
      } else {
        throw Exception("无效的配置类型，无法保存配置。");
      }

      if (mounted) {
        showNoticeSnackBar(context, "保存配置成功。");
      }
    } catch (e) {
      debugPrint('保存配置失败: $e');
      if (mounted) {
        showNoticeSnackBar(context, "保存配置失败: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    if (_isLoading) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else {
      List<Widget> children = [];

      if (_configType == 'noti') {
        children.add(
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "允许的关键词 (用英文逗号分隔):",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _isKeywordsLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TextField(
                      controller: _keywordsController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: "例如: 支付成功,收款,到账",
                      ),
                      maxLines: null,
                    ),
                const SizedBox(height: 16),
                if (_packages.isNotEmpty) const Divider(),
              ],
            ),
          ),
        );
      }

      if (_packages.isEmpty) {
        if (_configType == 'noti' &&
            (_isKeywordsLoading ||
                _keywords.isEmpty && _keywordsController.text.trim().isEmpty)) {
          bodyContent = Column(
            children: [
              ...children,
              Expanded(child: Center(child: Text(_emptyDataMessage))),
            ],
          );
        } else if (_configType == 'noti' &&
            !_isKeywordsLoading &&
            (_keywords.isNotEmpty ||
                _keywordsController.text.trim().isNotEmpty)) {
          bodyContent = ListView(children: children);
        } else {
          bodyContent = Center(child: Text(_emptyDataMessage));
        }
      } else {
        children.add(
          Expanded(
            child: ListView.builder(
              itemCount: _packages.length,
              itemBuilder: (context, index) {
                final pkg = _packages[index];
                return CheckboxListTile(
                  title: Text(pkg.appName),
                  subtitle: Text(pkg.packageName),
                  value: pkg.isAllowed,
                  onChanged: (checked) {
                    if (checked != null) {
                      _updatePackagePermissionToggle(pkg, checked);
                    }
                  },
                  controlAffinity: ListTileControlAffinity.trailing,
                );
              },
            ),
          ),
        );
        bodyContent = Column(children: children);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(_appBarTitle)),
      body: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: bodyContent,
      ),
      floatingActionButton:
          (_isLoading || _isKeywordsLoading) ||
                  (_packages.isEmpty &&
                      _keywordsController.text.trim().isEmpty &&
                      _configType != 'acc')
              ? null
              : FloatingActionButton.extended(
                onPressed: _isSaving ? null : _saveConfiguration,
                label: _isSaving ? const Text('保存中...') : const Text('确认修改'),
                icon:
                    _isSaving
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                        : const Icon(Icons.check),
              ),
    );
  }
}
