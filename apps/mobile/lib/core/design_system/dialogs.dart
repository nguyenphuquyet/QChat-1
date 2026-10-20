import 'package:flutter/material.dart';
import '../localization/strings.dart';

Future<String?> editText(
  BuildContext context,
  String title, {
  String initial = '',
  int maxLength = 300,
  bool secret = false,
  int lines = 1,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    initial: initial,
    maxLength: maxLength,
    secret: secret,
    lines: lines,
  ),
);

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr(c, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr(c, 'confirm')),
          ),
        ],
      ),
    ) ??
    false;

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.maxLength,
    required this.secret,
    required this.lines,
  });
  final String title, initial;
  final int maxLength, lines;
  final bool secret;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      obscureText: widget.secret,
      maxLength: widget.maxLength,
      maxLines: widget.lines,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: Text(tr(c, 'cancel')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(
          c,
          widget.secret ? controller.text : controller.text.trim(),
        ),
        child: Text(tr(c, 'save')),
      ),
    ],
  );
}
