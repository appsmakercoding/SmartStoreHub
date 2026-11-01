import 'package:url_launcher/url_launcher.dart';

String bdPhone(String p) {
  final d = p.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('880')) return d;
  if (d.startsWith('0')) return '88$d';
  return '880$d';
}

Future<bool> openUrl(String u) async {
  try {
    return await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<bool> callPhone(String p) => openUrl('tel:$p');
Future<bool> smsTo(String p, String body) => openUrl('sms:$p?body=${Uri.encodeComponent(body)}');
Future<bool> whatsappTo(String p, String body) => openUrl('https://wa.me/${bdPhone(p)}?text=${Uri.encodeComponent(body)}');
