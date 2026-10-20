import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'qchat_colors.dart';

ThemeData qchatTheme(bool dark) {
  final defaultTheme = TThemeData.defaultData();
  // Loại bỏ PingFang SC để dùng font hệ thống (SF Pro trên iOS, Roboto trên Android)
  // giúp hiển thị đầy đủ dấu tiếng Việt (hỏi, ngã, nặng,...) mà không bị lỗi tách dấu / dấu phẩy
  defaultTheme.fontFamilyMap.remove('fontFamily');
  defaultTheme.fontFamilyMap.remove('fontFamilyMedium');
  if (defaultTheme.dark != null) {
    defaultTheme.dark!.fontFamilyMap.remove('fontFamily');
    defaultTheme.dark!.fontFamilyMap.remove('fontFamilyMedium');
  }

  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: dark
        ? const Color(0xff111111)
        : QChatColors.background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    colorSchemeSeed: QChatColors.green,
    extensions: [
      defaultTheme,
      TInputThemeData(
        hintStyle: const TextStyle(
          fontSize: 16,
          color: Color(0xffb2b2b2),
        ),
        backgroundColor: dark ? const Color(0xff222222) : Colors.white,
        borderColor: dark ? const Color(0xff333333) : QChatColors.line,
        borderRadius: 5,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ],
  );
}
