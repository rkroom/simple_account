import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tools/accessibility_extraction_rule.dart';
import '../tools/tools.dart';

const accessibilityRuleJsonEditorKey = ValueKey<String>(
  'accessibilityRuleJsonEditor',
);
const accessibilitySingleRuleJsonEditorKey = ValueKey<String>(
  'accessibilitySingleRuleJsonEditor',
);

enum AccessibilityRuleEditorMode { form, json }

class AccessibilityRuleEditorPage extends StatefulWidget {
  final String packageName;
  final List<Map<String, dynamic>> initialRules;

  const AccessibilityRuleEditorPage({
    super.key,
    required this.packageName,
    required this.initialRules,
  });

  @override
  State<AccessibilityRuleEditorPage> createState() =>
      _AccessibilityRuleEditorPageState();
}

class _AccessibilityRuleEditorPageState
    extends State<AccessibilityRuleEditorPage> {
  late List<AccessibilityExtractionRule> _rules;
  AccessibilityExtractionRule? _initialTemplate;
  late final TextEditingController _jsonController;
  AccessibilityRuleEditorMode _mode = AccessibilityRuleEditorMode.form;
  String? _jsonError;

  @override
  void initState() {
    super.initState();
    _initialTemplate =
        widget.initialRules.isEmpty
            ? AccessibilityExtractionRule.defaultForPackage(widget.packageName)
            : null;
    _rules =
        _initialTemplate != null
            ? [_initialTemplate!]
            : AccessibilityExtractionRuleCodec.parseList(
              widget.initialRules,
              packageName: widget.packageName,
            );
    _jsonController = TextEditingController(
      text: AccessibilityExtractionRuleCodec.encode(_rules, pretty: true),
    );
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  List<AccessibilityExtractionRule>? _parseJson() {
    try {
      final rules = AccessibilityExtractionRuleCodec.parseJson(
        _jsonController.text,
        packageName: widget.packageName,
      );
      setState(() => _jsonError = null);
      return rules;
    } on FormatException catch (error) {
      setState(() => _jsonError = error.message);
      return null;
    }
  }

  void _switchMode(AccessibilityRuleEditorMode nextMode) {
    if (nextMode == _mode) return;
    if (nextMode == AccessibilityRuleEditorMode.json) {
      _jsonController.text = AccessibilityExtractionRuleCodec.encode(
        _rules,
        pretty: true,
      );
      setState(() {
        _jsonError = null;
        _mode = nextMode;
      });
      return;
    }

    final parsed = _parseJson();
    if (parsed == null) return;
    setState(() {
      _rules = parsed;
      _mode = nextMode;
    });
  }

  Future<void> _editRule([int? index]) async {
    final current =
        index == null
            ? AccessibilityExtractionRule.defaultForPackage(widget.packageName)
            : _rules[index];
    final result = await showModalBottomSheet<AccessibilityExtractionRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (context) => AccessibilityExtractionRuleForm(
            rule: current,
            isNew: index == null,
          ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _rules.add(result);
      } else {
        _rules[index] = result;
      }
    });
  }

  Future<void> _deleteRule(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除提取规则'),
            content: Text('确定删除“${_rules[index].ruleName}”吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _rules.removeAt(index));
  }

  void _save() {
    final rules =
        _mode == AccessibilityRuleEditorMode.form ? _rules : _parseJson();
    if (rules == null) return;
    if (_initialTemplate != null &&
        rules.length == 1 &&
        AccessibilityExtractionRuleCodec.encode(rules) ==
            AccessibilityExtractionRuleCodec.encode([_initialTemplate!])) {
      showNoticeSnackBar(context, '请输入规则');
      return;
    }
    Navigator.of(
      context,
    ).pop(rules.map((rule) => rule.toJson()).toList(growable: false));
  }

  Widget _buildFormMode() {
    if (_rules.isEmpty) {
      return const Center(child: Text('暂无提取规则'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: _rules.length,
      itemBuilder: (context, index) {
        final rule = _rules[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          child: ListTile(
            onTap: () => _editRule(index),
            title: Text(rule.ruleName),
            subtitle: Text(
              '${rule.activityName}\n'
              '内容 ${rule.contentRules.length} · 支付方式 ${rule.paymentRules.length}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              tooltip: '规则操作',
              onSelected: (value) {
                if (value == 'edit') _editRule(index);
                if (value == 'delete') _deleteRule(index);
              },
              itemBuilder:
                  (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildJsonMode() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      child: TextField(
        key: accessibilityRuleJsonEditorKey,
        controller: _jsonController,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        onChanged: (_) {
          if (_jsonError != null) setState(() => _jsonError = null);
        },
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          errorText: _jsonError,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('辅助功能提取规则'),
        actions: [
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: SegmentedButton<AccessibilityRuleEditorMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: AccessibilityRuleEditorMode.form,
                  icon: Icon(Icons.tune),
                  label: Text('表单'),
                ),
                ButtonSegment(
                  value: AccessibilityRuleEditorMode.json,
                  icon: Icon(Icons.code),
                  label: Text('JSON'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) => _switchMode(value.first),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child:
                _mode == AccessibilityRuleEditorMode.form
                    ? _buildFormMode()
                    : _buildJsonMode(),
          ),
        ],
      ),
      floatingActionButton:
          _mode == AccessibilityRuleEditorMode.form
              ? FloatingActionButton(
                tooltip: '添加提取规则',
                onPressed: () => _editRule(),
                child: const Icon(Icons.add),
              )
              : null,
    );
  }
}

class AccessibilityExtractionRuleForm extends StatefulWidget {
  final AccessibilityExtractionRule rule;
  final bool isNew;
  final AccessibilityRuleEditorMode initialMode;

  const AccessibilityExtractionRuleForm({
    super.key,
    required this.rule,
    required this.isNew,
    this.initialMode = AccessibilityRuleEditorMode.form,
  });

  @override
  State<AccessibilityExtractionRuleForm> createState() =>
      _AccessibilityExtractionRuleFormState();
}

class _AccessibilityExtractionRuleFormState
    extends State<AccessibilityExtractionRuleForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _activityController;
  late final TextEditingController _cooldownController;
  late final TextEditingController _maxTriggerController;
  late final TextEditingController _retryTimesController;
  late final TextEditingController _retryIntervalController;
  late final TextEditingController _jsonController;
  late List<AccessibilityRuleDetail> _contentRules;
  late List<AccessibilityRuleDetail> _paymentRules;
  late Map<String, dynamic> _extra;
  late AccessibilityRuleEditorMode _mode;
  late bool _continueOnContentFailure;
  late bool _triggerOnEmptyNodes;
  late bool _preFilterByKeywords;
  late bool _allowContentChangeTrigger;
  late bool _hasPaymentInfo;
  String? _errorText;
  String? _jsonError;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _nameController = TextEditingController(text: rule.ruleName);
    _activityController = TextEditingController(text: rule.activityName);
    _cooldownController = TextEditingController(
      text: '${rule.emptyNodeTriggerCooldownMs}',
    );
    _maxTriggerController = TextEditingController(
      text: '${rule.maxContentTriggerTimes}',
    );
    _retryTimesController = TextEditingController(
      text: '${rule.dynamicRetryTimes}',
    );
    _retryIntervalController = TextEditingController(
      text: '${rule.dynamicRetryIntervalMs}',
    );
    _jsonController = TextEditingController(
      text: AccessibilityExtractionRuleCodec.encodeRule(rule, pretty: true),
    );
    _contentRules = rule.contentRules.toList();
    _paymentRules = rule.paymentRules.toList();
    _extra = Map<String, dynamic>.from(rule.extra);
    _mode = widget.initialMode;
    _continueOnContentFailure = rule.continueOnContentFailure;
    _triggerOnEmptyNodes = rule.triggerOnEmptyNodes;
    _preFilterByKeywords = rule.preFilterByKeywords;
    _allowContentChangeTrigger = rule.allowContentChangeTrigger;
    _hasPaymentInfo = rule.hasPaymentInfo;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _activityController.dispose();
    _cooldownController.dispose();
    _maxTriggerController.dispose();
    _retryTimesController.dispose();
    _retryIntervalController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _editDetail(bool isContent, [int? index]) async {
    final source = isContent ? _contentRules : _paymentRules;
    final detail =
        index == null
            ? AccessibilityRuleDetail(
              keywords: const [],
              strategy: const {
                'type': 'SimpleOffset',
                'offset': 0,
                'useExactMatch': false,
              },
            )
            : source[index];
    final result = await showModalBottomSheet<AccessibilityRuleDetail>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (context) =>
              AccessibilityRuleDetailForm(detail: detail, isNew: index == null),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        source.add(result);
      } else {
        source[index] = result;
      }
    });
  }

  Widget _buildDetailSection({required String title, required bool isContent}) {
    final rules = isContent ? _contentRules : _paymentRules;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: '添加$title',
              icon: const Icon(Icons.add),
              onPressed: () => _editDetail(isContent),
            ),
          ],
        ),
        if (rules.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('暂无规则', style: TextStyle(color: Colors.black54)),
          ),
        for (var index = 0; index < rules.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => _editDetail(isContent, index),
            title: Text(rules[index].strategyType),
            subtitle: Text(
              rules[index].keywords.isEmpty
                  ? '无关键词'
                  : rules[index].keywords.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => rules.removeAt(index)),
            ),
          ),
      ],
    );
  }

  Widget _intField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (value) => int.tryParse(value ?? '') == null ? '请输入整数' : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  AccessibilityExtractionRule? _buildFormRule() {
    if (_formKey.currentState?.validate() != true) return null;
    try {
      return AccessibilityExtractionRule(
        ruleName: _nameController.text.trim(),
        packageName: widget.rule.packageName,
        activityName: _activityController.text.trim(),
        contentRules: _contentRules,
        paymentRules: _paymentRules,
        continueOnContentFailure: _continueOnContentFailure,
        triggerOnEmptyNodes: _triggerOnEmptyNodes,
        emptyNodeTriggerCooldownMs: int.parse(_cooldownController.text),
        preFilterByKeywords: _preFilterByKeywords,
        allowContentChangeTrigger: _allowContentChangeTrigger,
        hasPaymentInfo: _hasPaymentInfo,
        maxContentTriggerTimes: int.parse(_maxTriggerController.text),
        dynamicRetryTimes: int.parse(_retryTimesController.text),
        dynamicRetryIntervalMs: int.parse(_retryIntervalController.text),
        extra: _extra,
      );
    } on FormatException catch (error) {
      setState(() => _errorText = error.message);
      return null;
    }
  }

  AccessibilityExtractionRule? _buildJsonRule() {
    try {
      final rule = AccessibilityExtractionRuleCodec.parseRuleJson(
        _jsonController.text,
        packageName: widget.rule.packageName,
      );
      if (_jsonError != null) setState(() => _jsonError = null);
      return rule;
    } on FormatException catch (error) {
      setState(() => _jsonError = error.message);
      return null;
    }
  }

  void _applyRuleToForm(AccessibilityExtractionRule rule) {
    _nameController.text = rule.ruleName;
    _activityController.text = rule.activityName;
    _cooldownController.text = '${rule.emptyNodeTriggerCooldownMs}';
    _maxTriggerController.text = '${rule.maxContentTriggerTimes}';
    _retryTimesController.text = '${rule.dynamicRetryTimes}';
    _retryIntervalController.text = '${rule.dynamicRetryIntervalMs}';
    _contentRules = rule.contentRules.toList();
    _paymentRules = rule.paymentRules.toList();
    _extra = Map<String, dynamic>.from(rule.extra);
    _continueOnContentFailure = rule.continueOnContentFailure;
    _triggerOnEmptyNodes = rule.triggerOnEmptyNodes;
    _preFilterByKeywords = rule.preFilterByKeywords;
    _allowContentChangeTrigger = rule.allowContentChangeTrigger;
    _hasPaymentInfo = rule.hasPaymentInfo;
  }

  void _switchMode(AccessibilityRuleEditorMode nextMode) {
    if (nextMode == _mode) return;
    if (_errorText != null) setState(() => _errorText = null);

    if (nextMode == AccessibilityRuleEditorMode.json) {
      final rule = _buildFormRule();
      if (rule == null) return;
      _jsonController.text = AccessibilityExtractionRuleCodec.encodeRule(
        rule,
        pretty: true,
      );
      setState(() {
        _jsonError = null;
        _mode = nextMode;
      });
      return;
    }

    final rule = _buildJsonRule();
    if (rule == null) return;
    setState(() {
      _applyRuleToForm(rule);
      _mode = nextMode;
    });
  }

  void _save() {
    if (_errorText != null) setState(() => _errorText = null);
    final rule =
        _mode == AccessibilityRuleEditorMode.form
            ? _buildFormRule()
            : _buildJsonRule();
    if (rule == null) return;
    if (widget.isNew &&
        AccessibilityExtractionRuleCodec.encodeRule(rule) ==
            AccessibilityExtractionRuleCodec.encodeRule(widget.rule)) {
      setState(() => _errorText = '请输入规则');
      return;
    }
    Navigator.of(context).pop(rule);
  }

  Widget _buildJsonEditor() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('复制'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _jsonController.text),
                  );
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.paste),
                label: const Text('粘贴'),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (!mounted || data?.text == null) return;
                  _jsonController.text = data!.text!;
                  setState(() {
                    _jsonError = null;
                    _errorText = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              key: accessibilitySingleRuleJsonEditorKey,
              controller: _jsonController,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              onChanged: (_) {
                if (_jsonError != null || _errorText != null) {
                  setState(() {
                    _jsonError = null;
                    _errorText = null;
                  });
                }
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: _jsonError,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.95,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  widget.isNew ? '新增提取规则' : '编辑提取规则',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<AccessibilityRuleEditorMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: AccessibilityRuleEditorMode.form,
                  icon: Icon(Icons.tune),
                  label: Text('表单'),
                ),
                ButtonSegment(
                  value: AccessibilityRuleEditorMode.json,
                  icon: Icon(Icons.code),
                  label: Text('JSON'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) => _switchMode(value.first),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child:
                _mode == AccessibilityRuleEditorMode.form
                    ? Form(
                      key: _formKey,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          MediaQuery.of(context).viewInsets.bottom + 24,
                        ),
                        children: [
                          TextFormField(
                            controller: _nameController,
                            validator:
                                (value) =>
                                    value == null || value.trim().isEmpty
                                        ? '请输入规则名称'
                                        : null,
                            decoration: const InputDecoration(
                              labelText: '规则名称',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _activityController,
                            validator:
                                (value) =>
                                    value == null || value.trim().isEmpty
                                        ? '请输入 activityName'
                                        : null,
                            decoration: const InputDecoration(
                              labelText: 'Activity 类名',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildDetailSection(title: '内容规则', isContent: true),
                          const Divider(),
                          _buildDetailSection(
                            title: '支付方式规则',
                            isContent: false,
                          ),
                          const Divider(),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('内容提取失败后继续'),
                            value: _continueOnContentFailure,
                            onChanged:
                                (value) => setState(
                                  () => _continueOnContentFailure = value,
                                ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('进入页面直接记录'),
                            value: _triggerOnEmptyNodes,
                            onChanged:
                                (value) => setState(
                                  () => _triggerOnEmptyNodes = value,
                                ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('关键字预过滤'),
                            value: _preFilterByKeywords,
                            onChanged:
                                (value) => setState(
                                  () => _preFilterByKeywords = value,
                                ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('允许内容变化触发'),
                            value: _allowContentChangeTrigger,
                            onChanged:
                                (value) => setState(
                                  () => _allowContentChangeTrigger = value,
                                ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('页面包含支付方式'),
                            value: _hasPaymentInfo,
                            onChanged:
                                (value) =>
                                    setState(() => _hasPaymentInfo = value),
                          ),
                          const SizedBox(height: 10),
                          _intField(_cooldownController, '直接记录冷却时间（毫秒）'),
                          const SizedBox(height: 10),
                          _intField(_maxTriggerController, '最大内容变化触发次数'),
                          const SizedBox(height: 10),
                          _intField(_retryTimesController, '动态重试次数'),
                          const SizedBox(height: 10),
                          _intField(_retryIntervalController, '动态重试间隔（毫秒）'),
                        ],
                      ),
                    )
                    : _buildJsonEditor(),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('保存'),
                        onPressed: _save,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AccessibilityRuleDetailForm extends StatefulWidget {
  final AccessibilityRuleDetail detail;
  final bool isNew;

  const AccessibilityRuleDetailForm({
    super.key,
    required this.detail,
    required this.isNew,
  });

  @override
  State<AccessibilityRuleDetailForm> createState() =>
      _AccessibilityRuleDetailFormState();
}

class _AccessibilityRuleDetailFormState
    extends State<AccessibilityRuleDetailForm> {
  late final TextEditingController _keywordsController;
  late final TextEditingController _offsetController;
  late final TextEditingController _checkOffsetController;
  late final TextEditingController _targetOffsetController;
  late final TextEditingController _expectedTextsController;
  late final TextEditingController _viewIdController;
  late String _strategyType;
  late bool _useExactMatch;
  late List<Map<String, dynamic>> _parts;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final detail = widget.detail;
    final strategy = detail.strategy;
    _keywordsController = TextEditingController(
      text: detail.keywords.join(', '),
    );
    _offsetController = TextEditingController(
      text: '${strategy['offset'] ?? 0}',
    );
    _checkOffsetController = TextEditingController(
      text: '${strategy['checkOffset'] ?? 0}',
    );
    _targetOffsetController = TextEditingController(
      text: '${strategy['targetOffset'] ?? 0}',
    );
    _expectedTextsController = TextEditingController(
      text:
          strategy['expectedTexts'] is List
              ? (strategy['expectedTexts'] as List).join(', ')
              : '',
    );
    _viewIdController = TextEditingController(
      text: strategy['viewId']?.toString() ?? '',
    );
    _strategyType = detail.strategyType;
    _useExactMatch = strategy['useExactMatch'] == true;
    _parts =
        strategy['parts'] is List
            ? (strategy['parts'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
  }

  @override
  void dispose() {
    _keywordsController.dispose();
    _offsetController.dispose();
    _checkOffsetController.dispose();
    _targetOffsetController.dispose();
    _expectedTextsController.dispose();
    _viewIdController.dispose();
    super.dispose();
  }

  List<String> _splitText(String value) {
    return value
        .split(RegExp(r'[,，\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> _strategyExtra() {
    const known = {
      'type',
      'offset',
      'useExactMatch',
      'checkOffset',
      'targetOffset',
      'expectedTexts',
      'viewId',
      'parts',
    };
    return Map<String, dynamic>.from(widget.detail.strategy)
      ..removeWhere((key, _) => known.contains(key));
  }

  Future<void> _editPart([int? index]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) =>
              _ConcatPartDialog(initial: index == null ? null : _parts[index]),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _parts.add(result);
      } else {
        _parts[index] = result;
      }
    });
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      inputFormatters: [
        TextInputFormatter.withFunction((oldValue, newValue) {
          return RegExp(r'^-?\d*$').hasMatch(newValue.text)
              ? newValue
              : oldValue;
        }),
      ],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildStrategyFields() {
    switch (_strategyType) {
      case 'SimpleOffset':
        return Column(
          children: [
            _numberField(_offsetController, '偏移量'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('关键词完全匹配'),
              value: _useExactMatch,
              onChanged: (value) => setState(() => _useExactMatch = value),
            ),
          ],
        );
      case 'ConditionalOffset':
        return Column(
          children: [
            _numberField(_checkOffsetController, '条件偏移量'),
            const SizedBox(height: 10),
            TextField(
              controller: _expectedTextsController,
              decoration: const InputDecoration(
                labelText: '条件文本',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            _numberField(_targetOffsetController, '目标偏移量'),
          ],
        );
      case 'Concatenate':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('拼接项', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  tooltip: '添加拼接项',
                  icon: const Icon(Icons.add),
                  onPressed: () => _editPart(),
                ),
              ],
            ),
            for (var index = 0; index < _parts.length; index++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _editPart(index),
                title: Text(_parts[index]['type']?.toString() ?? ''),
                subtitle: Text(
                  _parts[index]['type'] == 'Literal'
                      ? _parts[index]['text']?.toString() ?? ''
                      : '偏移量 ${_parts[index]['offset']}',
                ),
                trailing: IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _parts.removeAt(index)),
                ),
              ),
          ],
        );
      case 'DirectViewId':
        return TextField(
          controller: _viewIdController,
          decoration: const InputDecoration(
            labelText: '完整 View ID',
            border: OutlineInputBorder(),
          ),
        );
      case 'ExtractByViewId':
        return Column(
          children: [
            TextField(
              controller: _viewIdController,
              decoration: const InputDecoration(
                labelText: 'View ID',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('View ID 完全匹配'),
              value: _useExactMatch,
              onChanged: (value) => setState(() => _useExactMatch = value),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _save() {
    try {
      final extra = _strategyExtra();
      final strategy = <String, dynamic>{...extra, 'type': _strategyType};
      switch (_strategyType) {
        case 'SimpleOffset':
          strategy.addAll({
            'offset': int.parse(_offsetController.text),
            'useExactMatch': _useExactMatch,
          });
          break;
        case 'ConditionalOffset':
          strategy.addAll({
            'checkOffset': int.parse(_checkOffsetController.text),
            'expectedTexts': _splitText(_expectedTextsController.text),
            'targetOffset': int.parse(_targetOffsetController.text),
          });
          break;
        case 'Concatenate':
          strategy['parts'] = _parts;
          break;
        case 'DirectViewId':
          strategy['viewId'] = _viewIdController.text.trim();
          break;
        case 'ExtractByViewId':
          strategy.addAll({
            'viewId': _viewIdController.text.trim(),
            'useExactMatch': _useExactMatch,
          });
          break;
      }
      final detail = AccessibilityRuleDetail(
        keywords: _splitText(_keywordsController.text),
        strategy: strategy,
        extra: widget.detail.extra,
      );
      Navigator.of(context).pop(detail);
    } on FormatException catch (error) {
      setState(() => _errorText = error.message);
    } catch (_) {
      setState(() => _errorText = '请完整填写策略参数');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  widget.isNew ? '新增规则明细' : '编辑规则明细',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              children: [
                TextField(
                  controller: _keywordsController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '关键词',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _strategyType,
                  decoration: const InputDecoration(
                    labelText: '提取策略',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      accessibilityStrategyTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _strategyType = value);
                  },
                ),
                const SizedBox(height: 14),
                _buildStrategyFields(),
                if (_errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('保存'),
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcatPartDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;

  const _ConcatPartDialog({this.initial});

  @override
  State<_ConcatPartDialog> createState() => _ConcatPartDialogState();
}

class _ConcatPartDialogState extends State<_ConcatPartDialog> {
  late String _type;
  late final TextEditingController _valueController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _type =
        initial == null ? 'Literal' : initial['type']?.toString() ?? 'Literal';
    _valueController = TextEditingController(
      text:
          _type == 'Literal'
              ? (initial == null ? null : initial['text'])?.toString() ?? ''
              : (initial == null ? null : initial['offset'])?.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _save() {
    if (_type == 'Literal') {
      Navigator.of(context).pop(<String, dynamic>{
        'type': 'Literal',
        'text': _valueController.text,
      });
      return;
    }
    final offset = int.tryParse(_valueController.text);
    if (offset == null) {
      setState(() => _errorText = '偏移量必须是整数');
      return;
    }
    Navigator.of(
      context,
    ).pop(<String, dynamic>{'type': 'NodeText', 'offset': offset});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('拼接项'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Literal', label: Text('文本')),
              ButtonSegment(value: 'NodeText', label: Text('节点')),
            ],
            selected: {_type},
            onSelectionChanged: (value) {
              setState(() {
                _type = value.first;
                _valueController.text = _type == 'Literal' ? '' : '0';
                _errorText = null;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueController,
            decoration: InputDecoration(
              labelText: _type == 'Literal' ? '文本' : '偏移量',
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('确定')),
      ],
    );
  }
}
