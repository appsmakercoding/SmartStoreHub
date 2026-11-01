import 'package:path/path.dart' as pth;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';
import 'ui.dart';

Future<void> doBackup() async {
  final path = pth.join(await getDatabasesPath(), 'smartstorehub.db');
  await Share.shareXFiles([XFile(path)], text: 'SmartStoreHub Backup');
  await Db.setSetting('last_backup', nowIso());
  await Db.log('ব্যাকআপ নেওয়া হয়েছে');
}
