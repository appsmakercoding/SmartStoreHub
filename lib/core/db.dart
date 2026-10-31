import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
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
}

class CartItem {
  final int id;
  final String name;
  final double price, cost, stock;
  double qty;
  CartItem(this.id, this.name, this.price, this.cost, this.stock, [this.qty = 1]);
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
    final path = join(await getDatabasesPath(), 'smartstorehub.db');
    return openDatabase(path, version: 2, onUpgrade: (d, o, n) async {
      if (o < 2) await _v2(d);
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

  // ---------- Suppliers & Purchases ----------
  static Future<List<Rec>> suppliers() => q('SELECT * FROM suppliers WHERE branch_id=? ORDER BY due DESC, name', [Session.branch]);

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
    await (await i).rawUpdate('UPDATE suppliers SET due=due-? WHERE id=?', [amt, id]);
    await log('সরবরাহকারীকে পরিশোধ ${money(amt)}');
  }

  static Future<double> supplierDue() async =>
      n((await q('SELECT COALESCE(SUM(due),0) d FROM suppliers WHERE branch_id=?', [Session.branch])).first['d']);

  // ---------- Restore ----------
  static Future<bool> restore(String src) async {
    final f = File(src);
    final head = await f.openRead(0, 15).fold<List<int>>([], (a, b) => a..addAll(b));
    if (String.fromCharCodes(head) != 'SQLite format 3') return false;
    final path = join(await getDatabasesPath(), 'smartstorehub.db');
    await _d?.close();
    _d = null;
    final cur = File(path);
    if (await cur.exists()) await cur.copy('$path.bak');
    await f.copy(path);
    final d = await i;
    await _v2(d);
    return true;
  }

  static Future<List<Rec>> q(String sql, [List<Object?>? a]) async => (await i).rawQuery(sql, a);

  // ---------- Auth ----------
  static Future<Rec?> login(String u, String p, String role) async {
    final name = u.toLowerCase();
    final r = await q('SELECT * FROM users WHERE username=? AND pass_hash=? AND role=? AND active=1', [name, hashPw(name, p), role]);
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
  static Future<List<Rec>> products([String s = '']) => q(
      'SELECT * FROM products WHERE branch_id=? AND active=1 AND (name LIKE ? OR barcode LIKE ? OR category LIKE ?) ORDER BY name LIMIT 300',
      [Session.branch, '%$s%', '%$s%', '%$s%']);

  static Future<Rec?> byBarcode(String c) async {
    final r = await q('SELECT * FROM products WHERE branch_id=? AND active=1 AND barcode=?', [Session.branch, c]);
    return r.isEmpty ? null : r.first;
  }

  static Future<void> saveProduct(Rec data, int? id) async {
    final d = await i;
    if (id == null) {
      await d.insert('products', {...data, 'branch_id': Session.branch, 'company_id': Session.company});
      await log('পণ্য যোগ: ${data['name']}');
    } else {
      await d.update('products', data, where: 'id=?', whereArgs: [id]);
      await log('পণ্য আপডেট: ${data['name']}');
    }
  }

  static Future<void> deleteProduct(int id) async {
    await (await i).update('products', {'active': 0}, where: 'id=?', whereArgs: [id]);
    await log('পণ্য মুছেছে #$id');
  }

  // ---------- Customers ----------
  static Future<List<Rec>> customers() =>
      q('SELECT * FROM customers WHERE branch_id=? ORDER BY due DESC, name', [Session.branch]);

  static Future<void> addCustomer(String name, String phone) async {
    await (await i).insert('customers', {'branch_id': Session.branch, 'company_id': Session.company, 'name': name, 'phone': phone});
    await log('গ্রাহক যোগ: $name');
  }

  static Future<void> receive(int id, double amt) async {
    final d = await i;
    await d.transaction((t) async {
      await t.rawUpdate('UPDATE customers SET due=due-? WHERE id=?', [amt, id]);
      await t.insert('payments', {'branch_id': Session.branch, 'customer_id': id, 'user_id': Session.id, 'amount': amt, 'created_at': nowIso()});
    });
    await log('বকেয়া আদায় ${money(amt)}');
  }

  // ---------- Sales ----------
  static Future<int> saveSale(List<CartItem> cart, double discount, double paid, String method, int? cust) async {
    final d = await i;
    final sub = cart.fold<double>(0, (s, c) => s + c.price * c.qty);
    final total = sub - discount;
    final pd = paid > total ? total : paid;
    final due = total - pd;
    late int id;
    await d.transaction((t) async {
      id = await t.insert('sales', {
        'branch_id': Session.branch, 'company_id': Session.company, 'user_id': Session.id, 'customer_id': cust,
        'total': total, 'discount': discount, 'paid': pd, 'due': due, 'method': method, 'created_at': nowIso(),
      });
      for (final c in cart) {
        await t.insert('sale_items', {'sale_id': id, 'product_id': c.id, 'name': c.name, 'qty': c.qty, 'price': c.price, 'cost': c.cost});
        await t.rawUpdate('UPDATE products SET stock=stock-? WHERE id=?', [c.qty, c.id]);
      }
      if (due > 0 && cust != null) {
        await t.rawUpdate('UPDATE customers SET due=due+? WHERE id=?', [due, cust]);
      }
    });
    await log('বিক্রি #$id ${money(total)}');
    return id;
  }

  // ---------- Reports ----------
  static String _w(int? u) => u == null ? '' : ' AND s.user_id=$u';

  static Future<Rec> summary(String from, {int? uid}) async {
    final a = await q(
        'SELECT COUNT(*) c, COALESCE(SUM(total),0) t, COALESCE(SUM(discount),0) d, COALESCE(SUM(due),0) due FROM sales s WHERE s.branch_id=? AND s.created_at>=?${_w(uid)}',
        [Session.branch, from]);
    final p = await q(
        'SELECT COALESCE(SUM((si.price-si.cost)*si.qty),0) p FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.branch_id=? AND s.created_at>=?${_w(uid)}',
        [Session.branch, from]);
    return {...a.first, 'profit': n(p.first['p']) - n(a.first['d'])};
  }

  static Future<List<Rec>> methods(String from, {int? uid}) => q(
      'SELECT method, COUNT(*) c, SUM(total) t FROM sales s WHERE s.branch_id=? AND s.created_at>=?${_w(uid)} GROUP BY method',
      [Session.branch, from]);

  static Future<List<Rec>> topProducts(String from, {int? uid}) => q(
      'SELECT si.name, SUM(si.qty) q, SUM(si.price*si.qty) r FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.branch_id=? AND s.created_at>=?${_w(uid)} GROUP BY si.product_id, si.name ORDER BY q DESC LIMIT 5',
      [Session.branch, from]);

  static Future<List<Rec>> perUser(String from) => q(
      'SELECT u.name, COUNT(*) c, SUM(s.total) t FROM sales s JOIN users u ON u.id=s.user_id WHERE s.branch_id=? AND s.created_at>=? GROUP BY s.user_id ORDER BY t DESC',
      [Session.branch, from]);

  static Future<List<Rec>> recent(String from, {int? uid}) => q(
      'SELECT s.*, u.name uname FROM sales s LEFT JOIN users u ON u.id=s.user_id WHERE s.branch_id=? AND s.created_at>=?${_w(uid)} ORDER BY s.id DESC LIMIT 20',
      [Session.branch, from]);

  // ---------- Dashboard ----------
  static Future<int> lowCount() async => (await q('SELECT COUNT(*) c FROM products WHERE branch_id=? AND active=1 AND stock<=min_stock', [Session.branch])).first['c'] as int;

  static Future<List<Rec>> lowStock() => q('SELECT name, stock FROM products WHERE branch_id=? AND active=1 AND stock<=min_stock ORDER BY stock LIMIT 5', [Session.branch]);

  static Future<List<Rec>> expiring() => q(
      "SELECT name, expiry FROM products WHERE branch_id=? AND active=1 AND expiry IS NOT NULL AND expiry<>'' AND expiry<=? ORDER BY expiry LIMIT 5",
      [Session.branch, DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10)]);

  static Future<double> totalDue() async =>
      n((await q('SELECT COALESCE(SUM(due),0) d FROM customers WHERE branch_id=?', [Session.branch])).first['d']);

  static Future<double> stockValue() async =>
      n((await q('SELECT COALESCE(SUM(stock*cost),0) v FROM products WHERE branch_id=? AND active=1', [Session.branch])).first['v']);

  static Future<List<Rec>> daily(String from) => q(
      'SELECT substr(created_at,1,10) d, SUM(total) t FROM sales WHERE branch_id=? AND created_at>=? GROUP BY d', [Session.branch, from]);

  // ---------- Users ----------
  static Future<List<Rec>> users() => q('SELECT * FROM users WHERE branch_id=? ORDER BY role, name', [Session.branch]);

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
