import 'package:tdesign_flutter/tdesign_flutter.dart';
import '../localization/strings.dart';

Future<String?> editText(
  BuildContext context,
  String title, {
  String initial = '',
  int maxLength = 300,
  bool secret = false,
  int lines = 1,
}) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: true,
  barrierLabel: tr(context, 'cancel'),
  barrierColor: const Color(0x66000000),
  transitionDuration: const Duration(milliseconds: 160),
  pageBuilder: (c, _, _) => _TextDialog(
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
    await TDialog.showPopupDialog<bool>(
      context: context,
      builder: (c) => TDialog(
        title: Text(title),
        content: Text(message),
        buttons: [
          TDialogButtonData(
            title: Text(tr(c, 'cancel')),
            action: (_) {
              Navigator.pop(c, false);
              return true;
            },
          ),
          TDialogButtonData(
            title: Text(tr(c, 'confirm')),
            action: (_) {
              Navigator.pop(c, true);
              return true;
            },
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
  Widget build(BuildContext c) => Align(
    alignment: Alignment.center,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Material(
        type: MaterialType.transparency,
        child: TDialog(
          title: Text(widget.title),
          content: TInput(
            controller: controller,
            autofocus: true,
            obscureText: widget.secret,
            maxLength: widget.maxLength,
            maxLines: widget.lines,
            hintText: '',
          ),
          buttons: [
            TDialogButtonData(
              title: Text(tr(c, 'cancel')),
              action: (_) {
                Navigator.pop(c);
                return true;
              },
            ),
            TDialogButtonData(
              title: Text(tr(c, 'save')),
              action: (_) {
                Navigator.pop(
                  c,
                  widget.secret
                      ? controller.text
                      : controller.text.trim(),
                );
                return true;
              },
            ),
          ],
        ),
      ),
    ),
  );
}
