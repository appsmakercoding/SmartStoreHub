import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:android_id/android_id.dart';
import 'package:http/http.dart' as http;
import 'db.dart';

// ⚠ নিচের দুটি আপনার নিজের তথ্য দিয়ে বদলান
const kFirebase = 'https://my-shop-7013d-default-rtdb.firebaseio.com';
const kContact = 'লাইসেন্স কিনতে যোগাযোগ করুন: Hasan — 01XXXXXXXXX';
const kTrialDays = 14;
const kOfflineGraceDays = 14;

enum LState { trial, active, expired, blocked }

class LicenseInfo {
  final LState state;
  final String plan;
  final int daysLeft;
  final String message;
  const LicenseInfo(this.state, this.plan, this.daysLeft, this.message);
  bool get ok => state == LState.trial || state == LState.active;
}

class License {
  static LicenseInfo? current;
  static DateTime? _srv;

  static int get maxUsers {
    switch (current?.plan) {
      case 'basic':
        return 3;
      case 'enterprise':
        return 999;
      default:
        return 10; // trial / pro
    }
  }

  static DateTime _now() => _srv ?? DateTime.now();

  static Future<String> deviceId() async {
    var id = await Db.setting('device_id');
    if (id.isNotEmpty) return id;
    try {
      id = await const AndroidId().getId() ?? '';
    } catch (_) {}
    if (id.isEmpty) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    }
    id = id.toUpperCase();
    await Db.setSetting('device_id', id);
    return id;
  }

  static Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$kFirebase/$path.json')).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw Exception('http ${r.statusCode}');
    try {
      final d = r.headers['date'];
      if (d != null) _srv = HttpDate.parse(d).toLocal();
    } catch (_) {}
    return jsonDecode(r.body);
  }

  static Future<bool> _put(String path, Object v) async {
    final r = await http.put(Uri.parse('$kFirebase/$path.json'), body: jsonEncode(v)).timeout(const Duration(seconds: 8));
    return r.statusCode == 200;
  }

  static Future<LicenseInfo> check() async {
    _srv = null;
    final dev = await deviceId();
    final key = await Db.setting('lic_key');
    final res = key.isNotEmpty ? await _checkKey(key, dev) : await _checkTrial(dev);
    if (res.state == LState.blocked && res.message == 'clock') {
      return const LicenseInfo(LState.blocked, '', 0, 'ডিভাইসের তারিখ/সময় ঠিক করুন, তারপর অ্যাপ আবার চালু করুন।');
    }
    return res;
  }

  static Future<bool> _clockOk() async {
    final ls = DateTime.tryParse(await Db.setting('last_seen'));
    final now = _now();
    if (ls != null && now.isBefore(ls.subtract(const Duration(days: 1)))) return false;
    if (ls == null || now.isAfter(ls)) await Db.setSetting('last_seen', now.toIso8601String());
    return true;
  }

  static Future<LicenseInfo> _checkTrial(String dev) async {
    String? cloud;
    var online = false;
    try {
      final v = await _get('trials/$dev');
      online = true;
      if (v is String) cloud = v;
    } catch (_) {}
    if (!await _clockOk()) return const LicenseInfo(LState.blocked, '', 0, 'clock');
    var local = await Db.setting('trial_start');
    if (local.isEmpty) {
      local = cloud ?? _now().toIso8601String();
      await Db.setSetting('trial_start', local);
    }
    var start = DateTime.parse(local);
    if (cloud != null) {
      final c = DateTime.tryParse(cloud);
      if (c != null && c.isBefore(start)) {
        start = c;
        await Db.setSetting('trial_start', cloud);
      }
    } else if (online) {
      try {
        await _put('trials/$dev', start.toIso8601String());
      } catch (_) {}
    }
    final left = kTrialDays - _now().difference(start).inDays;
    if (left <= 0) return const LicenseInfo(LState.expired, 'trial', 0, 'ফ্রি ট্রায়াল শেষ হয়েছে। চালিয়ে যেতে লাইসেন্স কী দিন।');
    return LicenseInfo(LState.trial, 'trial', left, 'ফ্রি ট্রায়াল: $left দিন বাকি');
  }

  static Future<LicenseInfo> _checkKey(String key, String dev) async {
    Map? lic;
    var online = false;
    try {
      final v = await _get('licenses/$key');
      online = true;
      if (v is Map) lic = v;
    } catch (_) {}
    if (!await _clockOk()) return const LicenseInfo(LState.blocked, '', 0, 'clock');
    String plan, expiry;
    if (online) {
      if (lic == null || lic['revoked'] == true) {
        await Db.setSetting('lic_key', '');
        return const LicenseInfo(LState.blocked, '', 0, 'এই লাইসেন্স বাতিল করা হয়েছে।');
      }
      if (lic['device'] != dev) {
        return const LicenseInfo(LState.blocked, '', 0, 'এই লাইসেন্স অন্য ডিভাইসে ব্যবহৃত হচ্ছে।');
      }
      plan = '${lic['plan'] ?? 'basic'}';
      expiry = '${lic['expiry'] ?? ''}';
      await Db.setSetting('lic_plan', plan);
      await Db.setSetting('lic_expiry', expiry);
      await Db.setSetting('lic_ok', _now().toIso8601String());
    } else {
      plan = await Db.setting('lic_plan');
      expiry = await Db.setting('lic_expiry');
      final ok = DateTime.tryParse(await Db.setting('lic_ok'));
      if (plan.isEmpty || ok == null || _now().difference(ok).inDays > kOfflineGraceDays) {
        return const LicenseInfo(LState.blocked, '', 0, 'লাইসেন্স যাচাইয়ের জন্য ইন্টারনেট চালু করুন।');
      }
    }
    final exp = DateTime.tryParse('${expiry}T23:59:59');
    if (exp == null) return const LicenseInfo(LState.blocked, '', 0, 'লাইসেন্সের মেয়াদ সঠিক নয়।');
    final left = exp.difference(_now()).inDays + 1;
    if (_now().isAfter(exp)) return LicenseInfo(LState.expired, plan, 0, 'লাইসেন্সের মেয়াদ শেষ ($expiry)। রিনিউ করুন।');
    return LicenseInfo(LState.active, plan, left, '${plan.toUpperCase()} প্ল্যান • মেয়াদ $expiry ($left দিন বাকি)');
  }

  /// সফল হলে null, নয়তো ত্রুটির বার্তা
  static Future<String?> activate(String raw) async {
    final key = raw.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9\-]{6,40}$').hasMatch(key)) return 'লাইসেন্স কী সঠিক নয়';
    final dev = await deviceId();
    try {
      final v = await _get('licenses/$key');
      if (v is! Map) return 'লাইসেন্স কী পাওয়া যায়নি';
      if (v['revoked'] == true) return 'এই লাইসেন্স বাতিল';
      final d = v['device'];
      if (d != null && d != dev) return 'এই কী অন্য ডিভাইসে ব্যবহৃত হচ্ছে';
      if (d == null) {
        if (!await _put('licenses/$key/device', dev)) return 'অ্যাক্টিভেশন ব্যর্থ, আবার চেষ্টা করুন';
        if (await _get('licenses/$key/device') != dev) return 'এই কী অন্য ডিভাইসে ব্যবহৃত হচ্ছে';
      }
      await Db.setSetting('lic_key', key);
      return null;
    } catch (_) {
      return 'ইন্টারনেট সংযোগ নেই বা সার্ভার সমস্যা';
    }
  }
}
