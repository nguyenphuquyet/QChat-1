import 'package:flutter/widgets.dart';
import 'client.dart';

// ConnectionBanner chỉ là wrapper trong suốt – trạng thái offline được
// expose qua client.offline để các màn hình tự xử lý giao diện tương ứng.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.client,
    required this.child,
  });
  final QChatClient client;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
