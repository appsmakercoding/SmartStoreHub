import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as pth;
import 'package:sqflite/sqflite.dart';
import 'ui.dart';

typedef Rec = Map<String, Object?>;

String hashPw(String user, String pw) =>
    sha256.convert(utf8.encode('ssh|${user.toLowerCase()}|$pw')).toString();

class Session {
  static Rec? user;
  static int get id => user?['id'] as int? ?? 0;
  static int get branch => user?['branch_id'] as int? ?? 1;
  static int get company => user?['company_id'] as int? ?? 1;
  static String get role => user?['role'] as String? ?? '';
  static String get name => user?['name'] as String? ?? '';
  static String get username => user?['username'] as String? ?? '';
  static bool get isCashier => role == 'cashier';
  static bool get isAdmin => role == 'admin';
}

/// ভুল পাসওয়ার্ডে ৫ বার পর ৫ মিনিট লক
class LoginGuard {
  static final Map<String, int> _f = {};
  static final Map<String, DateTime> _lock = {};
  static int lockedMinutes(String u) {
    final t = _lock[u.toLowerCase()];
    if (t == null) return 0;
    final s = t.difference(DateTime.now()).inSeconds;
    if (s <= 0) {
      _lock.remove(u.toLowerCase());
      _f.remove(u.toLowerCase());
      return 0;
    }
    return (s / 60).ceil();
  }

  static void fail(String u) {
    final k = u.toLowerCase();
    final c = (_f[k] ?? 0) + 1;
    _f[k] = c;
    if (c >= 5) _lock[k] = DateTime.now().add(const Duration(minutes: 5));
  }

  static void ok(String u) {
    _f.remove(u.toLowerCase());
    _lock.remove(u.toLowerCase());
  }
}

class CartItem {
  final int id; // id <= 0 মানে খোলা/দ্রুত আইটেম (স্টকে নেই)
  final String name;
  final double price, cost, stock;
  double qty;
  final String unit;
  CartItem(this.id, this.name, this.price, this.cost, this.stock, {this.qty = 1, this.unit = 'পিস'});
}

class PItem {
  final int pid;
  final String name;
  final double qty, cost;
  PItem(this.pid, this.name, this.qty, this.cost);
}

class Db {
  static Database? _d;
  static Future<Database> get i async => _d ??= await _open();

  // সব টেবিলে company_id ও branch_id আছে => ভবিষ্যতে মাল্টি-শাখা/ক্লাউড সিঙ্কের জন্য প্রস্তুত
  static Future<Database> _open() async {
    final path = pth.join(await getDatabasesPath(), 'smartstorehub.db');
    return openDatabase(path, version: 3, onUpgrade: (d, o, nv) async {
      if (o < 2) await _v2(d);
      if (o < 3) await _v3(d);
    }, onCreate: (d, v) async {
      const t = [
        'CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, name TEXT, username TEXT UNIQUE, pass_hash TEXT, role TEXT, active INTEGER DEFAULT 1)',
        'CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, name TEXT, barcode TEXT, category TEXT, cost REAL DEFAULT 0, price REAL DEFAULT 0, stock REAL DEFAULT 0, min_stock REAL DEFAULT 5, expiry TEXT, active INTEGER DEFAULT 1)',
        'CREATE INDEX idx_barcode ON products(barcode)',
        'CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, name TEXT, phone TEXT, due REAL DEFAULT 0)',
        'CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, user_id INTEGER, customer_id INTEGER, total REAL, discount REAL, paid REAL, due REAL, method TEXT, created_at TEXT)',
        'CREATE TABLE sale_items(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, product_id INTEGER, name TEXT, qty REAL, price REAL, cost REAL)',
        'CREATE TABLE payments(id INTEGER PRIMARY KEY AUTOINCREMENT, branch_id INTEGER DEFAULT 1, customer_id INTEGER, user_id INTEGER, amount REAL, created_at TEXT)',
        'CREATE TABLE activity(id INTEGER PRIMARY KEY AUTOINCREMENT, branch_id INTEGER DEFAULT 1, user_id INTEGER, action TEXT, created_at TEXT)',
        'CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)',
      ];
      for (final s in t) {
        await d.execute(s);
      }
      await _v2(d);
      await _v3(d);
      await d.insert('users', {'name': 'মালিক', 'username': 'admin', 'pass_hash': hashPw('admin', 'admin123'), 'role': 'admin'});
      await d.insert('settings', {'k': 'shop_name', 'v': 'আমার সুপার শপ'});
    });
  }

  static Future<void> _v2(Database d) async {
    const t = [
      'CREATE TABLE IF NOT EXISTS suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, name TEXT, phone TEXT, due REAL DEFAULT 0)',
      'CREATE TABLE IF NOT EXISTS purchases(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, supplier_id INTEGER, user_id INTEGER, total REAL, paid REAL, due REAL, created_at TEXT)',
      'CREATE TABLE IF NOT EXISTS purchase_items(id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER, product_id INTEGER, name TEXT, qty REAL, cost REAL)',
    ];
    for (final s in t) {
      await d.execute(s);
    }
  }

  static Future<void> _v3(Database d) async {
    const alters = [
      'ALTER TABLE users ADD COLUMN deleted INTEGER DEFAULT 0',
      "ALTER TABLE products ADD COLUMN unit TEXT DEFAULT 'পিস'",
      'ALTER TABLE customers ADD COLUMN credit_limit REAL DEFAULT 0',
      'ALTER TABLE sales ADD COLUMN vat REAL DEFAULT 0',
      "ALTER TABLE sales ADD COLUMN status TEXT DEFAULT 'ok'",
      'ALTER TABLE sales ADD COLUMN cancel_reason TEXT',
      'ALTER TABLE sale_items ADD COLUMN returned_qty REAL DEFAULT 0',
      "ALTER TABLE sale_items ADD COLUMN unit TEXT DEFAULT 'পিস'",
      "ALTER TABLE payments ADD COLUMN kind TEXT DEFAULT 'cash'",
      'ALTER TABLE payments ADD COLUMN sale_id INTEGER',
      'ALTER TABLE payments ADD COLUMN note TEXT',
    ];
    for (final s in alters) {
      try {
        await d.execute(s);
      } catch (_) {}
    }
    const t = [
      'CREATE TABLE IF NOT EXISTS returns(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, sale_id INTEGER, user_id INTEGER, amount REAL, cash_refund REAL, due_adjust REAL, created_at TEXT)',
      'CREATE TABLE IF NOT EXISTS return_items(id INTEGER PRIMARY KEY AUTOINCREMENT, return_id INTEGER, product_id INTEGER, name TEXT, qty REAL, price REAL, cost REAL)',
      'CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, user_id INTEGER, category TEXT, amount REAL, note TEXT, created_at TEXT)',
      'CREATE TABLE IF NOT EXISTS stock_adjust(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, product_id INTEGER, name TEXT, qty REAL, cost REAL, reason TEXT, user_id INTEGER, created_at TEXT)',
      'CREATE TABLE IF NOT EXISTS cash_close(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, user_id INTEGER, day TEXT, expected REAL, actual REAL, diff REAL, note TEXT, created_at TEXT)',
      'CREATE TABLE IF NOT EXISTS supplier_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER DEFAULT 1, branch_id INTEGER DEFAULT 1, supplier_id INTEGER, user_id INTEGER, amount REAL, created_at TEXT)',
    ];
    for (final s in t) {
      await d.execute(s);
    }
  }

  static Future<List<Rec>> q(String sql, [List<Object?>? a]) async => (await i).rawQuery(sql, a);

  // ---------- Auth ----------
  static Future<Rec?> login(String u, String p, String role) async {
    final name = u.toLowerCase();
    final r = await q('SELECT * FROM users WHERE username=? AND pass_hash=? AND role=? AND active=1 AND deleted=0', [name, hashPw(name, p), role]);
    return r.isEmpty ? null : r.first;
  }

  static Future<void> log(String action) async {
    await (await i).insert('activity', {'branch_id': Session.branch, 'user_id': Session.id, 'action': action, 'created_at': nowIso()});
  }

  static Future<String> setting(String k, [String d = '']) async {
    final r = await q('SELECT v FROM settings WHERE k=?', [k]);
    return r.isEmpty ? d : r.first['v'] as String;
  }

  static Future<void> setSetting(String k, String v) async {
    await (await i).insert('settings', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- Products ----------
  static Future<List<Rec>> products([String s = '', String filter = 'all']) {
    var extra = '';
    if (filter == 'low') extra = ' AND stock<=min_stock';
    if (filter == 'exp') {
      final lim = DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10);
      extra = " AND expiry IS NOT NULL AND expiry<>'' AND expiry<='$lim'";
    }
    return q('SELECT * FROM products WHERE branch_id=? AND active=1 AND (name LIKE ? OR barcode LIKE ? OR category LIKE ?)$extra ORDER BY name LIMIT 500',
        [Session.branch, '%$s%', '%$s%', '%$s%']);
  }

  static Future<List<Rec>> deletedProducts() =>
      q('SELECT * FROM products WHERE branch_id=? AND active=0 ORDER BY name', [Session.branch]);

  static Future<void> restoreProduct(int id) async {
    await (await i).update('products', {'active': 1}, where: 'id=?', whereArgs: [id]);
    await log('পণ্য ফেরত আনা #$id');
  }

  static Future<Rec> productStats() async {
    final r = await q('SELECT COUNT(*) c, COALESCE(SUM(stock*cost),0) v, COALESCE(SUM(CASE WHEN stock<=min_stock THEN 1 ELSE 0 END),0) low FROM products WHERE branch_id=? AND active=1', [Session.branch]);
    return r.first;
  }

  static Future<Rec?> byBarcode(String c) async {
    final r = await q('SELECT * FROM products WHERE branch_id=? AND active=1 AND barcode=?', [Session.branch, c]);
    return r.isEmpty ? null : r.first;
  }

  /// সফল হলে null, নয়তো ত্রুটির বার্তা
  static Future<String?> saveProduct(Rec data, int? id) async {
    final d = await i;
    final bc = '${data['barcode'] ?? ''}';
    if (bc.isNotEmpty) {
      final dup = id == null
          ? await q('SELECT id FROM products WHERE branch_id=? AND active=1 AND barcode=?', [Session.branch, bc])
          : await q('SELECT id FROM products WHERE branch_id=? AND active=1 AND barcode=? AND id<>?', [Session.branch, bc, id]);
      if (dup.isNotEmpty) return 'এই বারকোড অন্য পণ্যে আছে';
    }
    if (id == null) {
      await d.insert('products', {...data, 'branch_id': Session.branch, 'company_id': Session.company});
      await log('পণ্য যোগ: ${data['name']}');
    } else {
      await d.update('products', data, where: 'id=?', whereArgs: [id]);
      await log('পণ্য আপডেট: ${data['name']}');
    }
    return null;
  }

  static Future<void> deleteProduct(int id, String name) async {
    await (await i).update('products', {'active': 0}, where: 'id=?', whereArgs: [id]);
    await log('পণ্য মুছেছে (রিসাইকেল বিনে): $name');
  }

  static Future<void> adjustStock(int pid, String name, double change, double cost, String reason) async {
    final d = await i;
    await d.transaction((t) async {
      await t.rawUpdate('UPDATE products SET stock=stock+? WHERE id=?', [change, pid]);
      await t.insert('stock_adjust', {'branch_id': Session.branch, 'company_id': Session.company, 'product_id': pid, 'name': name, 'qty': change, 'cost': cost, 'reason': reason, 'user_id': Session.id, 'created_at': nowIso()});
    });
    await log('স্টক সমন্বয় $name ${change > 0 ? '+' : ''}${fmtQty(change)} ($reason)');
  }

  // ---------- Customers ----------
  static Future<List<Rec>> customers({String s = '', bool dueOnly = false}) {
    final extra = dueOnly ? ' AND due>0' : '';
    return q('SELECT * FROM customers WHERE branch_id=? AND (name LIKE ? OR phone LIKE ?)$extra ORDER BY due DESC, name', [Session.branch, '%$s%', '%$s%']);
  }

  static Future<Rec?> customer(int id) async {
    final r = await q('SELECT * FROM customers WHERE id=?', [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<int> addCustomer(String name, String phone, {double limit = 0}) async {
    final id = await (await i).insert('customers', {'branch_id': Session.branch, 'company_id': Session.company, 'name': name, 'phone': phone, 'credit_limit': limit});
    await log('গ্রাহক যোগ: $name');
    return id;
  }

  static Future<void> receive(int id, double amt) async {
    final d = await i;
    await d.transaction((t) async {
      await t.rawUpdate('UPDATE customers SET due=due-? WHERE id=?', [amt, id]);
      await t.insert('payments', {'branch_id': Session.branch, 'customer_id': id, 'user_id': Session.id, 'amount': amt, 'created_at': nowIso(), 'kind': 'cash'});
    });
    await log('বকেয়া আদায় ${money(amt)}');
  }

  /// গ্রাহক খতিয়ান: প্রতিটি বিল/আদায়/সমন্বয় ও চলতি বাকি
  static Future<List<Rec>> customerLedger(int id) async {
    final sales = await q('SELECT id, created_at, total, paid, due, status FROM sales WHERE customer_id=?', [id]);
    final pays = await q('SELECT id, created_at, amount, kind, sale_id, note FROM payments WHERE customer_id=?', [id]);
    final out = <Rec>[];
    for (final s in sales) {
      out.add({'type': 'sale', 'date': s['created_at'], 'effect': n(s['due']), 'sale_id': s['id'], 'total': n(s['total']), 'paid': n(s['paid']), 'status': s['status']});
    }
    for (final p in pays) {
      final k = '${p['kind']}';
      out.add({'type': k, 'date': p['created_at'], 'effect': -n(p['amount']), 'sale_id': p['sale_id'], 'note': p['note']});
    }
    out.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    double run = 0;
    for (final e in out) {
      run += n(e['effect']);
      e['bal'] = run;
    }
    return out;
  }

  // ---------- Sales ----------
  static Future<int> saveSale(List<CartItem> cart, double discount, double vat, double paid, String method, int? cust) async {
    final d = await i;
    final sub = cart.fold<double>(0, (s, c) => s + c.price * c.qty);
    final total = sub - discount + vat;
    final pd = paid > total ? total : paid;
    final due = total - pd;
    late int id;
    await d.transaction((t) async {
      id = await t.insert('sales', {
        'branch_id': Session.branch, 'company_id': Session.company, 'user_id': Session.id, 'customer_id': cust,
        'total': total, 'discount': discount, 'vat': vat, 'paid': pd, 'due': due, 'method': method, 'created_at': nowIso(), 'status': 'ok',
      });
      for (final c in cart) {
        await t.insert('sale_items', {'sale_id': id, 'product_id': c.id > 0 ? c.id : null, 'name': c.name, 'qty': c.qty, 'price': c.price, 'cost': c.cost, 'unit': c.unit});
        if (c.id > 0) await t.rawUpdate('UPDATE products SET stock=stock-? WHERE id=?', [c.qty, c.id]);
      }
      if (due > 0 && cust != null) {
        await t.rawUpdate('UPDATE customers SET due=due+? WHERE id=?', [due, cust]);
      }
    });
    await log('বিক্রি #$id ${money(total)}');
    return id;
  }

  static Future<Rec?> sale(int id) async {
    final r = await q('SELECT s.*, u.name uname, c.name cname, c.phone cphone FROM sales s LEFT JOIN users u ON u.id=s.user_id LEFT JOIN customers c ON c.id=s.customer_id WHERE s.id=?', [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<List<Rec>> saleItems(int id) => q('SELECT * FROM sale_items WHERE sale_id=?', [id]);

  static Future<List<Rec>> salesList(String from, {int? uid, String s = ''}) {
    final w = uid == null ? '' : ' AND s.user_id=$uid';
    return q(
        'SELECT s.*, u.name uname, c.name cname FROM sales s LEFT JOIN users u ON u.id=s.user_id LEFT JOIN customers c ON c.id=s.customer_id WHERE s.branch_id=? AND s.created_at>=?$w AND (CAST(s.id AS TEXT) LIKE ? OR IFNULL(c.name,\'\') LIKE ?) ORDER BY s.id DESC LIMIT 150',
        [Session.branch, from, '%$s%', '%$s%']);
  }

  /// রিটার্ন: ব্যর্থ হলে String ছুড়ে দেয়
  static Future<Rec> returnSale(int saleId, Map<int, double> qtys) async {
    final d = await i;
    final s = await sale(saleId);
    if (s == null || s['status'] == 'cancelled') throw 'এই বিলে রিটার্ন সম্ভব নয়';
    final items = await saleItems(saleId);
    final sub = items.fold<double>(0, (a, x) => a + n(x['price']) * n(x['qty']));
    final disc = n(s['discount']), vat = n(s['vat']);
    final net = sub - disc;
    final ratio = sub > 0 ? net / sub : 1.0;
    final vatF = net > 0 ? 1 + vat / net : 1.0;
    double amtNet = 0;
    final lines = <Rec>[];
    for (final it in items) {
      final qy = qtys[it['id'] as int] ?? 0;
      if (qy <= 0) continue;
      final remain = n(it['qty']) - n(it['returned_qty']);
      if (qy > remain + 0.0001) throw '${it['name']}: সর্বোচ্চ ${fmtQty(remain)} ফেরত নেওয়া যায়';
      amtNet += n(it['price']) * ratio * qy;
      lines.add({...it, 'rq': qy});
    }
    if (lines.isEmpty) throw 'কোনো পণ্য নির্বাচন করা হয়নি';
    final amount = amtNet * vatF;
    double dueAdj = 0;
    final cust = s['customer_id'] as int?;
    if (cust != null && n(s['due']) > 0) {
      final adj = n((await q("SELECT COALESCE(SUM(amount),0) a FROM payments WHERE sale_id=? AND kind='return'", [saleId])).first['a']);
      final avail = n(s['due']) - adj;
      dueAdj = avail > 0 ? (amount < avail ? amount : avail) : 0;
    }
    final cash = amount - dueAdj;
    await d.transaction((t) async {
      final rid = await t.insert('returns', {'branch_id': Session.branch, 'company_id': Session.company, 'sale_id': saleId, 'user_id': Session.id, 'amount': amount, 'cash_refund': cash, 'due_adjust': dueAdj, 'created_at': nowIso()});
      for (final l in lines) {
        final pid = l['product_id'] as int?;
        await t.insert('return_items', {'return_id': rid, 'product_id': pid, 'name': l['name'], 'qty': l['rq'], 'price': n(l['price']) * ratio, 'cost': n(l['cost'])});
        await t.rawUpdate('UPDATE sale_items SET returned_qty=returned_qty+? WHERE id=?', [l['rq'], l['id']]);
        if (pid != null && pid > 0) await t.rawUpdate('UPDATE products SET stock=stock+? WHERE id=?', [l['rq'], pid]);
      }
      if (dueAdj > 0 && cust != null) {
        await t.rawUpdate('UPDATE customers SET due=due-? WHERE id=?', [dueAdj, cust]);
        await t.insert('payments', {'branch_id': Session.branch, 'customer_id': cust, 'user_id': Session.id, 'amount': dueAdj, 'created_at': nowIso(), 'kind': 'return', 'sale_id': saleId, 'note': 'রিটার্ন সমন্বয়'});
      }
    });
    await log('রিটার্ন বিল #$saleId ${money(amount)}');
    return {'amount': amount, 'cash': cash, 'dueAdj': dueAdj};
  }

  static Future<String?> cancelSale(int id, String reason) async {
    final d = await i;
    final s = await sale(id);
    if (s == null) return 'বিল পাওয়া যায়নি';
    if (s['status'] == 'cancelled') return 'এই বিল আগেই বাতিল করা হয়েছে';
    final rc = await q('SELECT COUNT(*) c FROM returns WHERE sale_id=?', [id]);
    if ((rc.first['c'] as int) > 0) return 'এই বিলে রিটার্ন আছে, বাতিল করা যাবে না';
    final items = await saleItems(id);
    await d.transaction((t) async {
      for (final it in items) {
        final pid = it['product_id'] as int?;
        if (pid != null && pid > 0) await t.rawUpdate('UPDATE products SET stock=stock+? WHERE id=?', [it['qty'], pid]);
      }
      final cust = s['customer_id'] as int?;
      final due = n(s['due']);
      if (cust != null && due > 0) {
        await t.rawUpdate('UPDATE customers SET due=due-? WHERE id=?', [due, cust]);
        await t.insert('payments', {'branch_id': Session.branch, 'customer_id': cust, 'user_id': Session.id, 'amount': due, 'created_at': nowIso(), 'kind': 'cancel', 'sale_id': id, 'note': reason});
      }
      await t.update('sales', {'status': 'cancelled', 'cancel_reason': reason}, where: 'id=?', whereArgs: [id]);
    });
    await log('বিল বাতিল #$id ($reason)');
    return null;
  }

  // ---------- Reports ----------
  static Future<Rec> pnl(String from, {int? uid}) async {
    final b = Session.branch;
    final w = uid == null ? '' : ' AND s.user_id=$uid';
    final wr = uid == null ? '' : ' AND r.user_id=$uid';
    final wp = uid == null ? '' : ' AND user_id=$uid';
    final a = (await q("SELECT COUNT(*) c, COALESCE(SUM(total),0) t, COALESCE(SUM(discount),0) d, COALESCE(SUM(due),0) due FROM sales s WHERE s.branch_id=? AND s.status<>'cancelled' AND s.created_at>=?$w", [b, from])).first;
    final ip = n((await q("SELECT COALESCE(SUM((si.price-si.cost)*si.qty),0) p FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.branch_id=? AND s.status<>'cancelled' AND s.created_at>=?$w", [b, from])).first['p']);
    final ra = n((await q('SELECT COALESCE(SUM(r.amount),0) a FROM returns r WHERE r.branch_id=? AND r.created_at>=?$wr', [b, from])).first['a']);
    final rp = n((await q('SELECT COALESCE(SUM((ri.price-ri.cost)*ri.qty),0) p FROM return_items ri JOIN returns r ON r.id=ri.return_id WHERE r.branch_id=? AND r.created_at>=?$wr', [b, from])).first['p']);
    final col = n((await q("SELECT COALESCE(SUM(amount),0) a FROM payments WHERE branch_id=? AND kind='cash' AND created_at>=?$wp", [b, from])).first['a']);
    double ex = 0, loss = 0;
    if (uid == null) {
      ex = n((await q('SELECT COALESCE(SUM(amount),0) a FROM expenses WHERE branch_id=? AND created_at>=?', [b, from])).first['a']);
      loss = n((await q('SELECT COALESCE(SUM(-qty*cost),0) a FROM stock_adjust WHERE branch_id=? AND qty<0 AND created_at>=?', [b, from])).first['a']);
    }
    final gross = ip - n(a['d']) - rp;
    return {
      'count': a['c'], 'sales': n(a['t']) - ra, 'discount': n(a['d']), 'due_given': n(a['due']),
      'returns': ra, 'gross': gross, 'collected': col, 'expenses': ex, 'loss': loss, 'net': gross - ex - loss,
    };
  }

  static Future<List<Rec>> methods(String from, {int? uid}) {
    final w = uid == null ? '' : ' AND s.user_id=$uid';
    return q("SELECT method, COUNT(*) c, SUM(total) t FROM sales s WHERE s.branch_id=? AND s.status<>'cancelled' AND s.created_at>=?$w GROUP BY method", [Session.branch, from]);
  }

  static Future<List<Rec>> topProducts(String from, {int? uid}) {
    final w = uid == null ? '' : ' AND s.user_id=$uid';
    return q("SELECT si.name, SUM(si.qty) q, SUM(si.price*si.qty) r FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.branch_id=? AND s.status<>'cancelled' AND s.created_at>=?$w GROUP BY si.product_id, si.name ORDER BY q DESC LIMIT 5", [Session.branch, from]);
  }

  static Future<List<Rec>> perUser(String from) => q(
      "SELECT u.name, COUNT(*) c, SUM(s.total) t FROM sales s JOIN users u ON u.id=s.user_id WHERE s.branch_id=? AND s.status<>'cancelled' AND s.created_at>=? GROUP BY s.user_id ORDER BY t DESC",
      [Session.branch, from]);

  static Future<Rec> supplierPeriod(String from) async {
    final p = (await q('SELECT COALESCE(SUM(total),0) t, COALESCE(SUM(paid),0) p FROM purchases WHERE branch_id=? AND created_at>=?', [Session.branch, from])).first;
    final sp = n((await q('SELECT COALESCE(SUM(amount),0) a FROM supplier_payments WHERE branch_id=? AND created_at>=?', [Session.branch, from])).first['a']);
    return {'bought': n(p['t']), 'paid': n(p['p']) + sp};
  }

  // ---------- Dashboard ----------
  static Future<List<Rec>> lowStock() => q('SELECT name, stock, unit FROM products WHERE branch_id=? AND active=1 AND stock<=min_stock ORDER BY stock LIMIT 5', [Session.branch]);

  static Future<List<Rec>> expiring() => q(
      "SELECT name, expiry FROM products WHERE branch_id=? AND active=1 AND expiry IS NOT NULL AND expiry<>'' AND expiry<=? ORDER BY expiry LIMIT 5",
      [Session.branch, DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10)]);

  static Future<double> totalDue() async =>
      n((await q('SELECT COALESCE(SUM(due),0) d FROM customers WHERE branch_id=?', [Session.branch])).first['d']);

  static Future<int> dueCount() async =>
      (await q('SELECT COUNT(*) c FROM customers WHERE branch_id=? AND due>0', [Session.branch])).first['c'] as int;

  static Future<List<Rec>> daily(String from) => q(
      "SELECT substr(created_at,1,10) d, SUM(total) t FROM sales WHERE branch_id=? AND status<>'cancelled' AND created_at>=? GROUP BY d", [Session.branch, from]);

  // ---------- Expenses ----------
  static Future<List<Rec>> expenses(String from) => q('SELECT e.*, u.name uname FROM expenses e LEFT JOIN users u ON u.id=e.user_id WHERE e.branch_id=? AND e.created_at>=? ORDER BY e.id DESC', [Session.branch, from]);

  static Future<void> addExpense(String cat, double amt, String note) async {
    await (await i).insert('expenses', {'branch_id': Session.branch, 'company_id': Session.company, 'user_id': Session.id, 'category': cat, 'amount': amt, 'note': note, 'created_at': nowIso()});
    await log('খরচ: $cat ${money(amt)}');
  }

  static Future<void> deleteExpense(int id) async {
    await (await i).delete('expenses', where: 'id=?', whereArgs: [id]);
    await log('খরচ মুছেছে #$id');
  }

  // ---------- Cash closing ----------
  static Future<Rec> cashToday() async {
    final from = '${nowIso().substring(0, 10)}T00:00:00';
    Future<double> sum(String sql) async => n((await q(sql, [Session.branch, from])).first['v']);
    final cashSales = await sum("SELECT COALESCE(SUM(paid),0) v FROM sales WHERE branch_id=? AND created_at>=? AND status<>'cancelled' AND method IN ('ক্যাশ','নগদ','বাকি')");
    final collected = await sum("SELECT COALESCE(SUM(amount),0) v FROM payments WHERE branch_id=? AND created_at>=? AND kind='cash'");
    final refunds = await sum('SELECT COALESCE(SUM(cash_refund),0) v FROM returns WHERE branch_id=? AND created_at>=?');
    final exp = await sum('SELECT COALESCE(SUM(amount),0) v FROM expenses WHERE branch_id=? AND created_at>=?');
    final sup1 = await sum('SELECT COALESCE(SUM(paid),0) v FROM purchases WHERE branch_id=? AND created_at>=?');
    final sup2 = await sum('SELECT COALESCE(SUM(amount),0) v FROM supplier_payments WHERE branch_id=? AND created_at>=?');
    return {
      'cashSales': cashSales, 'collected': collected, 'refunds': refunds, 'expenses': exp, 'supplier': sup1 + sup2,
      'expected': cashSales + collected - refunds - exp - sup1 - sup2,
    };
  }

  static Future<void> saveCashClose(double expected, double actual, String note) async {
    await (await i).insert('cash_close', {'branch_id': Session.branch, 'company_id': Session.company, 'user_id': Session.id, 'day': nowIso().substring(0, 10), 'expected': expected, 'actual': actual, 'diff': actual - expected, 'note': note, 'created_at': nowIso()});
    await log('ক্যাশ ক্লোজিং: পার্থক্য ${money(actual - expected)}');
  }

  static Future<List<Rec>> cashCloses() => q('SELECT c.*, u.name uname FROM cash_close c LEFT JOIN users u ON u.id=c.user_id WHERE c.branch_id=? ORDER BY c.id DESC LIMIT 30', [Session.branch]);

  // ---------- Suppliers & Purchases ----------
  static Future<List<Rec>> suppliers() => q(
      'SELECT s.*, COALESCE((SELECT SUM(total) FROM purchases p WHERE p.supplier_id=s.id),0) bought, COALESCE((SELECT SUM(paid) FROM purchases p WHERE p.supplier_id=s.id),0)+COALESCE((SELECT SUM(amount) FROM supplier_payments sp WHERE sp.supplier_id=s.id),0) paid_total FROM suppliers s WHERE s.branch_id=? ORDER BY s.due DESC, s.name',
      [Session.branch]);

  static Future<Rec?> supplier(int id) async {
    final r = await q(
        'SELECT s.*, COALESCE((SELECT SUM(total) FROM purchases p WHERE p.supplier_id=s.id),0) bought, COALESCE((SELECT SUM(paid) FROM purchases p WHERE p.supplier_id=s.id),0)+COALESCE((SELECT SUM(amount) FROM supplier_payments sp WHERE sp.supplier_id=s.id),0) paid_total FROM suppliers s WHERE s.id=?',
        [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<void> addSupplier(String name, String phone) async {
    await (await i).insert('suppliers', {'branch_id': Session.branch, 'company_id': Session.company, 'name': name, 'phone': phone});
    await log('সরবরাহকারী যোগ: $name');
  }

  static Future<void> savePurchase(int sid, List<PItem> items, double paid) async {
    final d = await i;
    final total = items.fold<double>(0, (s, x) => s + x.qty * x.cost);
    final pd = paid > total ? total : paid;
    final due = total - pd;
    await d.transaction((t) async {
      final id = await t.insert('purchases', {'branch_id': Session.branch, 'company_id': Session.company, 'supplier_id': sid, 'user_id': Session.id, 'total': total, 'paid': pd, 'due': due, 'created_at': nowIso()});
      for (final x in items) {
        await t.insert('purchase_items', {'purchase_id': id, 'product_id': x.pid, 'name': x.name, 'qty': x.qty, 'cost': x.cost});
        await t.rawUpdate('UPDATE products SET stock=stock+?, cost=? WHERE id=?', [x.qty, x.cost, x.pid]);
      }
      if (due > 0) await t.rawUpdate('UPDATE suppliers SET due=due+? WHERE id=?', [due, sid]);
    });
    await log('ক্রয় ${money(total)}');
  }

  static Future<void> paySupplier(int id, double amt) async {
    final d = await i;
    await d.transaction((t) async {
      await t.rawUpdate('UPDATE suppliers SET due=due-? WHERE id=?', [amt, id]);
      await t.insert('supplier_payments', {'branch_id': Session.branch, 'company_id': Session.company, 'supplier_id': id, 'user_id': Session.id, 'amount': amt, 'created_at': nowIso()});
    });
    await log('সরবরাহকারীকে পরিশোধ ${money(amt)}');
  }

  static Future<double> supplierDue() async =>
      n((await q('SELECT COALESCE(SUM(due),0) d FROM suppliers WHERE branch_id=?', [Session.branch])).first['d']);

  static Future<List<Rec>> supplierLedger(int id) async {
    final pu = await q('SELECT id, created_at, total, paid, due FROM purchases WHERE supplier_id=?', [id]);
    final pa = await q('SELECT id, created_at, amount FROM supplier_payments WHERE supplier_id=?', [id]);
    final out = <Rec>[];
    for (final p in pu) {
      out.add({'type': 'purchase', 'date': p['created_at'], 'pid': p['id'], 'total': n(p['total']), 'paid': n(p['paid']), 'effect': n(p['due'])});
    }
    for (final p in pa) {
      out.add({'type': 'pay', 'date': p['created_at'], 'amount': n(p['amount']), 'effect': -n(p['amount'])});
    }
    out.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    double run = 0;
    for (final e in out) {
      run += n(e['effect']);
      e['bal'] = run;
    }
    return out;
  }

  static Future<List<Rec>> purchaseItems(int pid) => q('SELECT * FROM purchase_items WHERE purchase_id=?', [pid]);

  // ---------- Restore ----------
  static Future<bool> restore(String src) async {
    final f = File(src);
    final head = await f.openRead(0, 15).fold<List<int>>([], (a, b) => a..addAll(b));
    if (String.fromCharCodes(head) != 'SQLite format 3') return false;
    final path = pth.join(await getDatabasesPath(), 'smartstorehub.db');
    await _d?.close();
    _d = null;
    final cur = File(path);
    if (await cur.exists()) await cur.copy('$path.bak');
    await f.copy(path);
    final d = await i;
    await _v2(d);
    await _v3(d);
    return true;
  }

  // ---------- Users ----------
  static Future<List<Rec>> users() => q('SELECT * FROM users WHERE branch_id=? AND deleted=0 ORDER BY role, name', [Session.branch]);

  static Future<String?> addUser(String name, String username, String pw, String role) async {
    try {
      final u = username.toLowerCase();
      await (await i).insert('users', {'name': name, 'username': u, 'pass_hash': hashPw(u, pw), 'role': role, 'branch_id': Session.branch, 'company_id': Session.company});
      await log('ইউজার তৈরি: $u ($role)');
      return null;
    } catch (_) {
      return 'এই ইউজারনেম আগে থেকেই আছে';
    }
  }

  static Future<String?> deleteUser(int id) async {
    if (id == Session.id) return 'নিজেকে মুছা যাবে না';
    final r = await q('SELECT role FROM users WHERE id=?', [id]);
    if (r.isEmpty) return 'ইউজার পাওয়া যায়নি';
    if (r.first['role'] == 'admin') return 'এডমিন মুছা যাবে না';
    await (await i).rawUpdate("UPDATE users SET deleted=1, active=0, username=username||'#del'||id WHERE id=?", [id]);
    await log('ইউজার মুছেছে #$id');
    return null;
  }

  static Future<void> setActive(int id, bool a) async {
    await (await i).update('users', {'active': a ? 1 : 0}, where: 'id=?', whereArgs: [id]);
    await log('ইউজার ${a ? 'চালু' : 'বন্ধ'} #$id');
  }

  static Future<void> resetPw(int id, String username, String pw) async {
    await (await i).update('users', {'pass_hash': hashPw(username, pw)}, where: 'id=?', whereArgs: [id]);
    await log('পাসওয়ার্ড রিসেট #$id');
  }

  static Future<bool> changePw(String old, String nw) async {
    final r = await q('SELECT id FROM users WHERE id=? AND pass_hash=?', [Session.id, hashPw(Session.username, old)]);
    if (r.isEmpty) return false;
    await resetPw(Session.id, Session.username, nw);
    return true;
  }

  static Future<List<Rec>> logs() => q(
      'SELECT a.*, u.name uname FROM activity a LEFT JOIN users u ON u.id=a.user_id WHERE a.branch_id=? ORDER BY a.id DESC LIMIT 100',
      [Session.branch]);
}
