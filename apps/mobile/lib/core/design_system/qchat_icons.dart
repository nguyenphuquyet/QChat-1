import 'package:flutter/widgets.dart';
import 'dart:math' as math;
import 'package:tdesign_flutter/tdesign_flutter.dart' show TIcons;

/// Original line icons drawn locally, independent of Material and WeChat assets.
class QChatIcon extends StatelessWidget {
  const QChatIcon(
    this.name, {
    super.key,
    this.color = const Color(0xff191919),
    this.size = 24,
    this.filled = false,
  });
  final String name;
  final Color color;
  final double size;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final glyph = switch (name) {
      'chats' => filled ? TIcons.chat_bubble_filled : TIcons.chat_bubble,
      'contacts' => filled ? TIcons.user_list_filled : TIcons.user_list,
      'me' => filled ? TIcons.user_filled : TIcons.user,
      'discover' => filled ? TIcons.compass_filled : TIcons.compass,
      'addFriend' => TIcons.user_add,
      'groups' => TIcons.usergroup_filled,
      'tag' => TIcons.tag_filled,
      'service' => TIcons.shop,
      'official' => TIcons.book_open,
      'chevron' => TIcons.chevron_right,
      'image' => filled ? TIcons.image_filled : TIcons.image,
      'camera' => TIcons.camera_filled,
      'location' => TIcons.location_filled,
      'file' => TIcons.folder_filled,
      'music' => TIcons.music,
      'miniApps' => TIcons.link,
      'call' => TIcons.call,
      'videoCall' => TIcons.video,
      'payments' => TIcons.chat_checked,
      'mail' => TIcons.mail,
      'mobile' => TIcons.mobile,
      'radar' => TIcons.radar,
      'qr' => TIcons.qrcode,
      'keyboard' => TIcons.keyboard,
      'transfer' => TIcons.folder,
      'lock' => TIcons.lock_on,
      'unlock' => TIcons.lock_off,
      'close' => TIcons.close,
      'delete' => TIcons.delete,
      _ => null,
    };
    if (glyph != null) return Icon(glyph, size: size, color: color);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _IconPainter(name, color)),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.name, this.color);
  final String name;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (name) {
      case 'channels':
        canvas.drawPath(
          Path()
            ..moveTo(12, 12)
            ..cubicTo(4, -2, 0, 0, 3, 14)
            ..cubicTo(6, 27, 10, 14, 12, 12)
            ..cubicTo(20, -2, 24, 0, 21, 14)
            ..cubicTo(18, 27, 14, 14, 12, 12),
          p,
        );
        break;
      case 'favorites':
        canvas.drawPath(
          Path()
            ..moveTo(3, 7)
            ..lineTo(12, 2)
            ..lineTo(21, 7)
            ..lineTo(12, 12)
            ..close(),
          p..color = const Color(0xff168fe5),
        );
        canvas.drawPath(
          Path()
            ..moveTo(3, 7)
            ..lineTo(3, 17)
            ..lineTo(12, 22)
            ..lineTo(12, 12),
          p..color = const Color(0xffeeb714),
        );
        canvas.drawPath(
          Path()
            ..moveTo(12, 22)
            ..lineTo(21, 17)
            ..lineTo(21, 7),
          p..color = const Color(0xffef6269),
        );
        break;
      case 'settings':
        final gear = Path();
        for (var i = 0; i < 48; i++) {
          final radius = i % 6 == 0 || i % 6 == 5 ? 8.0 : 10.5;
          final a = i * math.pi / 24;
          final x = 12 + radius * math.cos(a), y = 12 + radius * math.sin(a);
          if (i == 0) {
            gear.moveTo(x, y);
          } else {
            gear.lineTo(x, y);
          }
        }
        canvas.drawPath(gear..close(), p);
        canvas.drawCircle(const Offset(12, 12), 4, p);
        break;
      case 'stories':
        for (var i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(i * math.pi / 6);
          final hex = Path();
          for (var j = 0; j < 6; j++) {
            final a = j * math.pi / 3;
            final x = 10 * math.cos(a), y = 10 * math.sin(a);
            if (j == 0) {
              hex.moveTo(x, y);
            } else {
              hex.lineTo(x, y);
            }
          }
          canvas.drawPath(hex..close(), p);
          canvas.restore();
        }
        break;
      case 'nearby':
        canvas.drawCircle(const Offset(12, 7), 2.5, p);
        canvas.drawPath(
          Path()
            ..moveTo(9, 12)
            ..lineTo(15, 12)
            ..lineTo(13, 22)
            ..lineTo(11, 22)
            ..close(),
          p,
        );
        canvas.drawArc(const Rect.fromLTWH(1, 2, 22, 20), 2.2, 1.9, false, p);
        canvas.drawArc(const Rect.fromLTWH(1, 2, 22, 20), -.9, 1.9, false, p);
        break;
      case 'searchStar':
        for (var i = 0; i < 5; i++) {
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(i * math.pi * 2 / 5);
          canvas.drawLine(
            const Offset(5, 0),
            const Offset(11, 0),
            p..strokeWidth = 2,
          );
          canvas.restore();
        }
        break;
      case 'voice':
        canvas.drawCircle(const Offset(12, 12), 10, p);
        canvas.drawArc(const Rect.fromLTWH(3, 5, 13, 14), -.85, 1.7, false, p);
        canvas.drawArc(const Rect.fromLTWH(4, 8, 7, 8), -.8, 1.6, false, p);
        canvas.drawCircle(
          const Offset(7, 12),
          1,
          p..style = PaintingStyle.fill,
        );
        break;
      case 'moments':
        const colors = [
          Color(0xffef565d),
          Color(0xffeeb914),
          Color(0xff8bcd35),
          Color(0xff07c160),
          Color(0xff16b8bb),
          Color(0xff258ad7),
          Color(0xff7970da),
        ];
        for (var i = 0; i < 7; i++) {
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(i * 6.28318 / 7);
          canvas.drawArc(
            const Rect.fromLTWH(-10, -10, 20, 20),
            0,
            .9,
            false,
            p..color = colors[i],
          );
          canvas.drawPath(
            Path()
              ..moveTo(10, 0)
              ..lineTo(2, 4)
              ..lineTo(-4, 4),
            p,
          );
          canvas.restore();
        }
        break;
      case 'chats':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 3, 18, 15),
            const Radius.circular(6),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(7, 18)
            ..lineTo(5, 22)
            ..lineTo(12, 18),
          p,
        );
        break;
      case 'contacts':
      case 'me':
        canvas.drawCircle(const Offset(12, 7), 4, p);
        canvas.drawPath(
          Path()
            ..moveTo(3, 22)
            ..cubicTo(3, 13, 21, 13, 21, 22)
            ..close(),
          p,
        );
        break;
      case 'discover':
        canvas.drawCircle(const Offset(12, 12), 10, p);
        canvas.drawPath(
          Path()
            ..moveTo(16, 7)
            ..lineTo(14, 14)
            ..lineTo(7, 17)
            ..lineTo(10, 10)
            ..close(),
          p,
        );
        break;
      case 'search':
        canvas.drawCircle(const Offset(10, 10), 6, p);
        canvas.drawLine(const Offset(15, 15), const Offset(21, 21), p);
        break;
      case 'back':
        canvas.drawPath(
          Path()
            ..moveTo(15, 4)
            ..lineTo(7, 12)
            ..lineTo(15, 20),
          p,
        );
        break;
      case 'more':
        for (final x in [4.0, 12.0, 20.0]) {
          canvas.drawCircle(Offset(x, 12), 1.4, p..style = PaintingStyle.fill);
        }
        break;
      case 'plus':
        canvas.drawCircle(const Offset(12, 12), 10, p);
        canvas.drawLine(const Offset(6, 12), const Offset(18, 12), p);
        canvas.drawLine(const Offset(12, 6), const Offset(12, 18), p);
        break;
      case 'emoji':
        canvas.drawCircle(const Offset(12, 12), 10, p);
        canvas.drawArc(const Rect.fromLTWH(6, 7, 12, 11), 0.2, 2.7, false, p);
        canvas.drawCircle(const Offset(8, 8), .6, p);
        canvas.drawCircle(const Offset(16, 8), .6, p);
        break;
      case 'scan':
        canvas.drawPath(
          Path()
            ..moveTo(3, 15)
            ..cubicTo(0, 3, 3, 1, 8, 3)
            ..lineTo(12, 7)
            ..lineTo(19, 7)
            ..cubicTo(23, 7, 23, 12, 20, 14)
            ..lineTo(8, 14)
            ..cubicTo(6, 14, 5, 11, 3, 15),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(21, 10)
            ..cubicTo(24, 22, 21, 24, 16, 22)
            ..lineTo(12, 18)
            ..lineTo(5, 18),
          p,
        );
        break;
      case 'qr':
        for (final r in [
          const Rect.fromLTWH(2, 2, 7, 7),
          const Rect.fromLTWH(15, 2, 7, 7),
          const Rect.fromLTWH(2, 15, 7, 7),
        ]) {
          canvas.drawRect(r, p);
        }
        canvas.drawRect(const Rect.fromLTWH(15, 15, 6, 6), p);
        break;
      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 3, 16, 18),
            const Radius.circular(3),
          ),
          p,
        );
        canvas.drawLine(const Offset(8, 9), const Offset(16, 9), p);
        canvas.drawLine(const Offset(8, 15), const Offset(16, 15), p);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.name != name || old.color != color;
}
