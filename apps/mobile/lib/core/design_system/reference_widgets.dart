import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import 'components.dart';
import '../localization/strings.dart';

const sectionGap = SizedBox(height: 9);
const menuBlue = Color(0xff168fe5);
void openFeature(BuildContext c, String key) => c.push('/feature/$key');

class MenuRow extends StatelessWidget {
  const MenuRow(
    this.label, {
    super.key,
    this.icon,
    this.color = menuBlue,
    this.value,
    this.subtitle,
    this.onTap,
    this.boxed = false,
    this.trailing,
  });
  final String label;
  final String? icon, value, subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool boxed;
  final Widget? trailing;
  @override
  Widget build(BuildContext c) => QChatListTile(
    title: tr(c, label),
    titleLines: label == 'invoice' ? 2 : 1,
    subtitle: subtitle == null ? null : tr(c, subtitle!),
    leading: icon == null
        ? null
        : boxed
        ? Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: QChatIcon(icon!, color: Colors.white, size: 27),
            ),
          )
        : SizedBox(width: 26, child: QChatIcon(icon!, color: color, size: 23)),
    trailing:
        trailing ??
        (value == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      value!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: QChatColors.muted,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const QChatIcon(
                    'chevron',
                    size: 18,
                    color: Color(0xffb8b8b8),
                  ),
                ],
              )),
    onTap: onTap ?? () => openFeature(c, label),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 7),
    child: Text(
      tr(c, label),
      style: const TextStyle(fontSize: 14, color: Color(0xff888888)),
    ),
  );
}

Future<void> qchatTopMenu(
  BuildContext context,
  List<(String, String, VoidCallback)> actions,
) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: tr(context, 'cancel'),
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 120),
  pageBuilder: (c, _, _) => SafeArea(
    child: Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 49, right: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -5,
              right: 15,
              child: Transform.rotate(
                angle: .785398,
                child: Container(
                  width: 12,
                  height: 12,
                  color: const Color(0xff4c4c4c),
                ),
              ),
            ),
            Container(
              width: 190,
              decoration: BoxDecoration(
                color: const Color(0xff4c4c4c),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in actions)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.pop(c);
                        a.$3();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Color(0xff555555),
                              width: .5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            QChatIcon(a.$1, color: Colors.white, size: 23),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Text(
                                tr(c, a.$2),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

class FeatureScreen extends StatelessWidget {
  const FeatureScreen({super.key, required this.kind});
  final String kind;
  @override
  Widget build(BuildContext c) => QChatPage(
    title: tr(c, kind),
    leading: QChatIconButton(
      'back',
      label: tr(c, 'back'),
      onTap: () => c.pop(),
    ),
    child: QChatEmptyState(tr(c, 'serviceLater'), icon: 'settings'),
  );
}
