import 'package:tdesign_flutter/tdesign_flutter.dart';
import '../../core/design_system/components.dart';

/// Thanh nhập tin nhắn: [mic tròn] [ô trắng bo góc] [emoji tròn] [+ tròn]
/// Chiều cao một dòng = 8 + 40 + 8 = 56.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.voice,
    required this.hasText,
    required this.voiceLabel,
    required this.emojiLabel,
    required this.plusLabel,
    required this.sendLabel,
    required this.holdLabel,
    required this.onVoice,
    required this.onEmoji,
    required this.onPlus,
    required this.onSend,
    required this.onHold,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool voice, hasText;
  final String voiceLabel, emojiLabel, plusLabel, sendLabel, holdLabel;
  final VoidCallback onVoice, onEmoji, onPlus, onSend, onHold;
  final ValueChanged<String>? onChanged;

  static const double fieldHeight = 40;

  @override
  Widget build(BuildContext c) {
    final dark = Theme.of(c).brightness == Brightness.dark;
    final decoration = BoxDecoration(
      color: dark ? const Color(0xff2c2c2c) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ink(c).withValues(alpha: .06), width: .5),
    );

    final Widget field = voice
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onHold,
            child: Container(
              height: fieldHeight,
              alignment: Alignment.center,
              decoration: decoration,
              child: Text(
                holdLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: ink(c),
                ),
              ),
            ),
          )
        : Container(
            constraints: const BoxConstraints(minHeight: fieldHeight),
            decoration: decoration,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              cursorColor: QChatColors.green,
              style: TextStyle(fontSize: 16, height: 1.35, color: ink(c)),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ComposerIcon(
            glyph: voice ? _Glyph.keyboard : _Glyph.voice,
            label: voiceLabel,
            onTap: onVoice,
            width: 44,
          ),
          const SizedBox(width: 2),
          Expanded(child: field),
          const SizedBox(width: 4),
          _ComposerIcon(glyph: _Glyph.emoji, label: emojiLabel, onTap: onEmoji),
          if (hasText && !voice)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: SizedBox(
                height: fieldHeight,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSend,
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: QChatColors.green,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sendLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            _ComposerIcon(glyph: _Glyph.plus, label: plusLabel, onTap: onPlus),
        ],
      ),
    );
  }
}

enum _Glyph { voice, keyboard, emoji, plus }

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.width = 40,
  });
  final _Glyph glyph;
  final String label;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext c) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: ChatInputBar.fieldHeight,
        child: Center(
          child: CustomPaint(
            size: const Size(27, 27),
            painter: _GlyphPainter(glyph, ink(c)),
          ),
        ),
      ),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);
  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(12, 12), 10.2, stroke);

    switch (glyph) {
      case _Glyph.plus:
        canvas.drawLine(const Offset(6.8, 12), const Offset(17.2, 12), stroke);
        canvas.drawLine(const Offset(12, 6.8), const Offset(12, 17.2), stroke);
      case _Glyph.emoji:
        canvas.drawLine(const Offset(8.6, 8.4), const Offset(8.6, 10.4), stroke);
        canvas.drawLine(
          const Offset(15.4, 8.4),
          const Offset(15.4, 10.4),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6.6, 13)
            ..lineTo(17.4, 13)
            ..cubicTo(17.4, 18.4, 6.6, 18.4, 6.6, 13)
            ..close(),
          stroke,
        );
      case _Glyph.voice:
        const center = Offset(8.4, 12);
        canvas.drawCircle(center, 1.25, fill);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 3.6),
          -.85,
          1.7,
          false,
          stroke,
        );
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 6.6),
          -.8,
          1.6,
          false,
          stroke,
        );
      case _Glyph.keyboard:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(6, 8, 18, 16),
            const Radius.circular(1.6),
          ),
          stroke,
        );
        for (final x in const [9.0, 12.0, 15.0]) {
          canvas.drawCircle(Offset(x, 10.8), .35, stroke);
        }
        canvas.drawLine(const Offset(9.5, 13.4), const Offset(14.5, 13.4), stroke);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
