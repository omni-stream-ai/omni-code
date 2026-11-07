// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> openDesktopWindow() async {
  html.window.open(Uri.base.resolve('/').toString(), '_blank');
}
