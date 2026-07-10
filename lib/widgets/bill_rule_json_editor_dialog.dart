import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tools/bill_parse_rule.dart';

class BillRuleJsonEditorDialog extends StatefulWidget {
  final BillParseRuleDocument initialDocument;

  const BillRuleJsonEditorDialog({super.key, required this.initialDocument});

  @override
  State<BillRuleJsonEditorDialog> createState() =>
      _BillRuleJsonEditorDialogState();
}

class _BillRuleJsonEditorDialogState extends State<BillRuleJsonEditorDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialDocument.toJsonString(pretty: true),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndSave() {
    try {
      final parsed = BillParseRuleDocument.fromJsonString(_controller.text);
      Navigator.of(context).pop(parsed);
    } on FormatException catch (error) {
      setState(() => _errorText = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'JSON',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('复制'),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _controller.text),
                      );
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.paste),
                    label: const Text('粘贴'),
                    onPressed: () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (!mounted || data?.text == null) return;
                      _controller.text = data!.text!;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: _errorText,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('校验并保存'),
                    onPressed: _validateAndSave,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
