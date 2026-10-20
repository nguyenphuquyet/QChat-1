import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'components.dart';

/// Shared TDesign navigation, retaining QChat's system-bar handling.
class DetailPage extends StatelessWidget {
  const DetailPage({
    super.key,
    required this.child,
    this.title = '',
    this.whiteHeader = false,
  });
  final Widget child;
  final String title;
  final bool whiteHeader;
  @override
  Widget build(BuildContext context) => QChatPage(
    statusBackground: whiteHeader ? surface(context) : null,
    child: Column(
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            extensions: [
              ...Theme.of(
                context,
              ).extensions.values.where((e) => e is! TNavBarThemeData),
              TNavBarThemeData(
                backgroundColor: whiteHeader
                    ? surface(context)
                    : Theme.of(context).scaffoldBackgroundColor,
              ),
            ],
          ),
          child: TNavBar(title: Text(title), height: 54, useDefaultBack: true),
        ),
        Expanded(child: child),
      ],
    ),
  );
}
