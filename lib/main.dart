import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
//  GreenCart v2 - cart app (FakeStore API)
//  + Login / Register / Logout (lokal), Profile, Wishlist
//
//  Dependencies (pubspec.yaml -> dependencies):
//    http, shared_preferences, crypto
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await auth.init(); // load akun & sesi tersimpan
  runApp(const MyApp());
}

// ------------------------------------------------------------
// MODELS
// ------------------------------------------------------------
class Product {
  final int id;
  final String title;
  final double price;
  final String description;
  final String category;
  final String image;
  final double rating;
  final int ratingCount;

  Product({
    required this.id,
    required this.title,
    required this.price,
    required this.description,
    required this.category,
    required this.image,
    required this.rating,
    required this.ratingCount,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final rating = json['rating'] as Map<String, dynamic>?;
    return Product(
      id: json['id'] as int,
      title: json['title'] as String,
      price: (json['price'] as num).toDouble(),
      description: json['description'] as String,
      category: json['category'] as String,
      image: json['image'] as String,
      rating: (rating?['rate'] as num?)?.toDouble() ?? 0,
      ratingCount: (rating?['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class CartItem {
  final Product product;
  int qty;
  CartItem(this.product, this.qty);
  double get total => product.price * qty;
}

class Order {
  final String id;
  final String userEmail;
  final DateTime date;
  final List<CartItem> items;
  final double total;
  final String paymentMethod;

  Order({
    required this.id,
    required this.userEmail,
    required this.date,
    required this.items,
    required this.total,
    required this.paymentMethod,
  });
}

class AppUser {
  final String name;
  final String email;
  final String phone;
  final String address; // opsional (boleh kosong)
  final String? gender; // opsional
  final int? age; // opsional
  final String salt;
  final String passHash;

  AppUser({
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.gender,
    required this.age,
    required this.salt,
    required this.passHash,
  });

  AppUser withProfile({
    required String name,
    required String phone,
    required String address,
    String? gender,
    int? age,
  }) =>
      AppUser(
        name: name,
        email: email,
        phone: phone,
        address: address,
        gender: gender,
        age: age,
        salt: salt,
        passHash: passHash,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'gender': gender,
        'age': age,
        'salt': salt,
        'passHash': passHash,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
        address: (j['address'] as String?) ?? '',
        gender: j['gender'] as String?,
        age: (j['age'] as num?)?.toInt(),
        salt: j['salt'] as String,
        passHash: j['passHash'] as String,
      );
}

// ------------------------------------------------------------
// STATE (ChangeNotifier sederhana)
// ------------------------------------------------------------
class CartController extends ChangeNotifier {
  final Map<int, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();
  int get count => _items.values.fold(0, (sum, i) => sum + i.qty);
  double get subtotal => _items.values.fold(0.0, (sum, i) => sum + i.total);
  bool get isEmpty => _items.isEmpty;

  void add(Product p) {
    if (_items.containsKey(p.id)) {
      _items[p.id]!.qty++;
    } else {
      _items[p.id] = CartItem(p, 1);
    }
    notifyListeners();
  }

  void decrement(Product p) {
    final item = _items[p.id];
    if (item == null) return;
    if (item.qty > 1) {
      item.qty--;
    } else {
      _items.remove(p.id);
    }
    notifyListeners();
  }

  void remove(Product p) {
    _items.remove(p.id);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

class OrderController extends ChangeNotifier {
  final List<Order> _orders = [];

  List<Order> ordersFor(String? email) =>
      _orders.where((o) => o.userEmail == email).toList().reversed.toList();

  void add(Order o) {
    _orders.add(o);
    notifyListeners();
  }
}

/// Wishlist per-user, disimpan di shared_preferences.
class WishlistController extends ChangeNotifier {
  final Set<int> _ids = {};
  String? _email;

  int get count => _ids.length;
  bool has(int id) => _ids.contains(id);

  String get _key => 'wishlist_$_email';

  Future<void> load(String email) async {
    _email = email;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('wishlist_$email') ?? [];
    _ids
      ..clear()
      ..addAll(list.map(int.parse));
    notifyListeners();
  }

  void unload() {
    _email = null;
    _ids.clear();
    notifyListeners();
  }

  Future<void> toggle(int id) async {
    if (_email == null) return;
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _ids.map((e) => e.toString()).toList());
  }
}

/// Auth lokal (frontend only). Akun disimpan di shared_preferences.
/// Password di-hash (SHA-256 + salt), tapi ini tetap hanya untuk demo:
/// aplikasi sungguhan harus autentikasi lewat backend.
class AuthController extends ChangeNotifier {
  final Map<String, AppUser> _users = {};
  AppUser? _current;

  AppUser? get user => _current;
  bool get isLoggedIn => _current != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('users');
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List<dynamic>) {
          final u = AppUser.fromJson(e as Map<String, dynamic>);
          _users[u.email] = u;
        }
      } catch (_) {
        _users.clear();
      }
    }
    final session = prefs.getString('session');
    if (session != null && _users.containsKey(session)) {
      _current = _users[session];
      await wishlist.load(session);
    }
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  Future<void> _saveUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'users', jsonEncode(_users.values.map((u) => u.toJson()).toList()));
  }

  Future<void> _startSession(AppUser u) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session', u.email);
    await wishlist.load(u.email);
    _current = u;
    notifyListeners();
  }

  /// return null kalau sukses, atau pesan error.
  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    String address = '',
    String? gender,
    int? age,
  }) async {
    final e = email.trim().toLowerCase();
    if (_users.containsKey(e)) return 'Email sudah terdaftar. Silakan login.';
    final salt =
        '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(1 << 31)}';
    final u = AppUser(
      name: name.trim(),
      email: e,
      phone: phone.trim(),
      address: address.trim(),
      gender: gender,
      age: age,
      salt: salt,
      passHash: _hash(password, salt),
    );
    _users[e] = u;
    await _saveUsers();
    await _startSession(u);
    return null;
  }

  Future<String?> login(String email, String password) async {
    final e = email.trim().toLowerCase();
    final u = _users[e];
    if (u == null || u.passHash != _hash(password, u.salt)) {
      return 'Email atau password salah.';
    }
    await _startSession(u);
    return null;
  }

  Future<void> updateProfile(AppUser updated) async {
    _users[updated.email] = updated;
    _current = updated;
    await _saveUsers();
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session');
    cart.clear();
    wishlist.unload();
    navIndex.value = 0;
    _current = null;
    notifyListeners();
  }
}

/// Cache daftar produk supaya tidak fetch ulang tiap pindah halaman.
class ProductStore {
  Future<List<Product>>? _future;

  Future<List<Product>> load({bool force = false}) {
    if (force || _future == null) {
      final f = fetchProducts();
      _future = f;
      f.then((_) {}, onError: (_) {
        if (identical(_future, f)) _future = null; // boleh dicoba lagi
      });
    }
    return _future!;
  }
}

final cart = CartController();
final orderStore = OrderController();
final wishlist = WishlistController();
final auth = AuthController();
final productStore = ProductStore();
final ValueNotifier<int> navIndex = ValueNotifier<int>(0);

// ------------------------------------------------------------
// API
// ------------------------------------------------------------
Future<List<Product>> fetchProducts() async {
  final res = await http
      .get(Uri.parse('https://fakestoreapi.com/products'))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Gagal memuat produk (${res.statusCode})');
  }
  final data = jsonDecode(res.body) as List<dynamic>;
  return data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
}

// ------------------------------------------------------------
// HELPERS
// ------------------------------------------------------------
String money(double v) => '\$${v.toStringAsFixed(2)}';

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

Future<void> confirmLogout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Logout?'),
      content: const Text('Kamu yakin mau keluar dari akun ini?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 42),
            backgroundColor: Colors.redAccent,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Logout'),
        ),
      ],
    ),
  );
  if (ok == true) await auth.logout();
}

// ------------------------------------------------------------
// APP
// ------------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E9E5B),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'GreenCart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF3F8F4),
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.green.shade100),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.green.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.green.shade200),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      // Belum login -> AuthPage, sudah login -> HomeShell
      home: ListenableBuilder(
        listenable: auth,
        builder: (context, _) =>
            auth.isLoggedIn ? const HomeShell() : const AuthPage(),
      ),
    );
  }
}

// ------------------------------------------------------------
// AVATAR (inisial nama, tanpa foto)
// ------------------------------------------------------------
class UserAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const UserAvatar({super.key, required this.name, this.radius = 24});

  static const _colors = [
    Color(0xFF2E9E5B),
    Color(0xFF1F7A8C),
    Color(0xFF6A994E),
    Color(0xFF3A7D44),
    Color(0xFF52796F),
    Color(0xFF8A9A5B),
  ];

  @override
  Widget build(BuildContext context) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.take(2).map((p) => p[0].toUpperCase()).join();
    final color =
        _colors[name.codeUnits.fold<int>(0, (a, b) => a + b) % _colors.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// AUTH PAGE (Login + Register)
// ------------------------------------------------------------
class GenderPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const GenderPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final g in const ['Male', 'Female', 'Other'])
          ChoiceChip(
            label: Text(g),
            selected: value == g,
            // tap lagi untuk membatalkan pilihan (opsional)
            onSelected: (sel) => onChanged(sel ? g : null),
          ),
      ],
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _address = TextEditingController();
  final _age = TextEditingController();

  bool _isLogin = true;
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  String? _gender;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _address, _age]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 500));

    final String? err = _isLogin
        ? await auth.login(_email.text, _password.text)
        : await auth.register(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            phone: _phone.text,
            address: _address.text,
            gender: _gender,
            age: int.tryParse(_age.text),
          );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header hijau
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(24, topPad + 36, 24, 36),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, Colors.green.shade800],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.eco, color: Color(0xFF2E9E5B), size: 40),
                  ),
                  const SizedBox(height: 14),
                  const Text('GreenCart',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    _isLogin ? 'Welcome back!' : 'Create your account',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            // Form
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isLogin ? 'Login' : 'Register',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 16),

                        if (!_isLogin) ...[
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'Full name *',
                                prefixIcon: Icon(Icons.person_outline)),
                            validator: (v) =>
                                (v == null || v.trim().length < 3)
                                    ? 'Isi nama lengkap (min. 3 karakter)'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                        ],

                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                              labelText: 'Email *',
                              prefixIcon: Icon(Icons.mail_outline)),
                          validator: (v) =>
                              (v == null || !_emailRegex.hasMatch(v.trim()))
                                  ? 'Email tidak valid'
                                  : null,
                        ),
                        const SizedBox(height: 12),

                        if (!_isLogin) ...[
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(15),
                            ],
                            decoration: const InputDecoration(
                                labelText: 'Phone number *',
                                prefixIcon: Icon(Icons.phone_outlined)),
                            validator: (v) => (v == null || v.length < 8)
                                ? 'Nomor telepon tidak valid'
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],

                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: _isLogin
                              ? TextInputAction.done
                              : TextInputAction.next,
                          onFieldSubmitted: (_) {
                            if (_isLogin) _submit();
                          },
                          decoration: InputDecoration(
                            labelText: 'Password *',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Isi password';
                            }
                            if (!_isLogin && v.length < 6) {
                              return 'Minimal 6 karakter';
                            }
                            return null;
                          },
                        ),

                        if (!_isLogin) ...[
                          const SizedBox(height: 20),
                          const Text('Optional',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54)),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _address,
                            maxLines: 2,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'Address',
                                alignLabelWithHint: true,
                                prefixIcon: Icon(Icons.location_on_outlined)),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _age,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration: const InputDecoration(
                                labelText: 'Age',
                                prefixIcon: Icon(Icons.cake_outlined)),
                            validator: (v) {
                              if (v == null || v.isEmpty) return null;
                              final n = int.tryParse(v);
                              return (n == null || n < 1 || n > 120)
                                  ? 'Umur tidak valid'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 14),
                          const Text('Gender',
                              style: TextStyle(color: Colors.black54)),
                          const SizedBox(height: 6),
                          GenderPicker(
                            value: _gender,
                            onChanged: (g) => setState(() => _gender = g),
                          ),
                        ],

                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: Colors.red.shade800,
                                          fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white),
                                )
                              : Text(_isLogin ? 'Login' : 'Create Account',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                      _isLogin = !_isLogin;
                                      _error = null;
                                    }),
                            child: Text(_isLogin
                                ? 'Belum punya akun? Register'
                                : 'Sudah punya akun? Login'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// SHELL: AppBar + Drawer + halaman
// ------------------------------------------------------------
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _titles = [
    'Products',
    'My Cart',
    'Wishlist',
    'Order History',
    'My Profile',
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: navIndex,
      builder: (context, index, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_titles[index],
                style: const TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              ListenableBuilder(
                listenable: cart,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    onPressed: () => navIndex.value = 1,
                    icon: Badge(
                      label: Text('${cart.count}'),
                      isLabelVisible: cart.count > 0,
                      child: const Icon(Icons.shopping_cart_outlined),
                    ),
                  ),
                ),
              ),
            ],
          ),
          drawer: _AppDrawer(selected: index),
          body: IndexedStack(
            index: index,
            children: const [
              ProductsPage(),
              CartPage(),
              WishlistPage(),
              OrdersPage(),
              ProfilePage(),
            ],
          ),
        );
      },
    );
  }
}

class _AppDrawer extends StatelessWidget {
  final int selected;
  const _AppDrawer({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget countBadge(int n) => n > 0
        ? CircleAvatar(
            radius: 11,
            backgroundColor: scheme.primary,
            child: Text('$n',
                style: const TextStyle(fontSize: 11, color: Colors.white)),
          )
        : const SizedBox.shrink();

    Widget item(IconData icon, String label, int idx, {Widget? trailing}) {
      return ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: trailing,
        selected: selected == idx,
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () {
          navIndex.value = idx;
          Navigator.pop(context);
        },
      );
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header: avatar + nama + email
            InkWell(
              onTap: () {
                navIndex.value = 4;
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, Colors.green.shade800],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: ListenableBuilder(
                  listenable: auth,
                  builder: (context, _) {
                    final u = auth.user;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                          child: UserAvatar(name: u?.name ?? '?', radius: 28),
                        ),
                        const SizedBox(height: 14),
                        Text(u?.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(u?.email ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  item(Icons.storefront_outlined, 'Products', 0),
                  ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) => item(
                        Icons.shopping_cart_outlined, 'My Cart', 1,
                        trailing: countBadge(cart.count)),
                  ),
                  ListenableBuilder(
                    listenable: wishlist,
                    builder: (context, _) => item(
                        Icons.favorite_border, 'Wishlist', 2,
                        trailing: countBadge(wishlist.count)),
                  ),
                  item(Icons.receipt_long_outlined, 'Order History', 3),
                  item(Icons.person_outline, 'My Profile', 4),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Logout',
                    style: TextStyle(color: Colors.redAccent)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(context); // tutup drawer
                  confirmLogout(context);
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('v2.0.0 • Demo only, payment is simulated',
                  style: TextStyle(color: Colors.black45, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// PRODUCTS PAGE
// ------------------------------------------------------------
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  late Future<List<Product>> _future;
  String _category = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = productStore.load();
  }

  void _reload() => setState(() => _future = productStore.load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 56, color: Colors.black38),
                  const SizedBox(height: 12),
                  const Text('Gagal memuat produk',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(160, 46)),
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba lagi'),
                  ),
                ],
              ),
            ),
          );
        }

        final all = snap.data!;
        final categories = ['all', ...{...all.map((p) => p.category)}];
        final products = all.where((p) {
          final okCat = _category == 'all' || p.category == _category;
          final okQuery =
              p.title.toLowerCase().contains(_query.toLowerCase().trim());
          return okCat && okQuery;
        }).toList();

        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            try {
              await _future;
            } catch (_) {}
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Cari produk...',
                      prefixIcon: Icon(Icons.search),
                      contentPadding: EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final c = categories[i];
                      return ChoiceChip(
                        label: Text(c == 'all' ? 'All' : titleCase(c)),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      );
                    },
                  ),
                ),
              ),
              if (products.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Produk tidak ditemukan')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: ProductGridSliver(products: products),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ProductGridSliver extends StatelessWidget {
  final List<Product> products;
  const ProductGridSliver({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.crossAxisExtent;
        final cols = (w / 190).floor().clamp(2, 5);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 290,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => ProductCard(product: products[i]),
            childCount: products.length,
          ),
        );
      },
    );
  }
}

class HeartButton extends StatelessWidget {
  final Product product;
  const HeartButton({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wishlist,
      builder: (context, _) {
        final fav = wishlist.has(product.id);
        return Material(
          color: Colors.white,
          shape: CircleBorder(side: BorderSide(color: Colors.green.shade100)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              wishlist.toggle(product.id);
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                fav ? Icons.favorite : Icons.favorite_border,
                size: 20,
                color: fav ? Colors.redAccent : Colors.black45,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProductCard extends StatelessWidget {
  final Product product;
  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showProductDetail(context, product),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Image.network(
                          product.image,
                          fit: BoxFit.contain,
                          loadingBuilder: (c, child, p) => p == null
                              ? child
                              : const Center(
                                  child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))),
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.black26,
                              size: 40),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: HeartButton(product: product),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13, height: 1.25)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 16, color: Color(0xFFF5B301)),
                  const SizedBox(width: 2),
                  Text('${product.rating}',
                      style: const TextStyle(fontSize: 12)),
                  Text(' (${product.ratingCount})',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(money(product.price),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: scheme.primary)),
                  ),
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => addToCart(context, product),
                      child: const Icon(Icons.add_shopping_cart, size: 18),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void addToCart(BuildContext context, Product p) {
  HapticFeedback.lightImpact();
  cart.add(p);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      backgroundColor: Colors.green.shade800,
      content: Text('Added: ${p.title}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      action: SnackBarAction(
        label: 'VIEW CART',
        textColor: Colors.white,
        onPressed: () => navIndex.value = 1,
      ),
    ),
  );
}

void showProductDetail(BuildContext context, Product p) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, controller) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  SizedBox(
                    height: 240,
                    child: Image.network(p.image, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Chip(
                        label: Text(titleCase(p.category)),
                        visualDensity: VisualDensity.compact,
                      ),
                      const Spacer(),
                      HeartButton(product: p),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(p.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFF5B301), size: 20),
                      Text(' ${p.rating}  •  ${p.ratingCount} reviews',
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(p.description,
                      style: const TextStyle(height: 1.45, fontSize: 14)),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Text(money(p.price),
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 20),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          addToCart(context, p);
                        },
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Add to Cart'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ------------------------------------------------------------
// WISHLIST PAGE
// ------------------------------------------------------------
class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = productStore.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 56, color: Colors.black38),
                const SizedBox(height: 12),
                const Text('Gagal memuat produk'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                  onPressed: () => setState(
                      () => _future = productStore.load(force: true)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba lagi'),
                ),
              ],
            ),
          );
        }

        return ListenableBuilder(
          listenable: wishlist,
          builder: (context, _) {
            final items =
                snap.data!.where((p) => wishlist.has(p.id)).toList();

            if (items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border,
                        size: 80, color: Colors.green.shade200),
                    const SizedBox(height: 12),
                    const Text('Wishlist masih kosong',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Tap ikon hati di produk untuk menyimpannya',
                        style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(180, 46)),
                      onPressed: () => navIndex.value = 0,
                      child: const Text('Lihat produk'),
                    ),
                  ],
                ),
              );
            }

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: ProductGridSliver(products: items),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ------------------------------------------------------------
// PROFILE PAGE
// ------------------------------------------------------------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([auth, wishlist, cart, orderStore]),
      builder: (context, _) {
        final u = auth.user;
        if (u == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final orderCount = orderStore.ordersFor(u.email).length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Kartu identitas
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    UserAvatar(name: u.name, radius: 44),
                    const SizedBox(height: 14),
                    Text(u.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(u.email,
                        style: const TextStyle(color: Colors.black54)),
                    if (u.gender != null || u.age != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (u.gender != null)
                            Chip(
                              label: Text(u.gender!),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (u.age != null)
                            Chip(
                              label: Text('${u.age} yrs'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Statistik
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: Icons.receipt_long_outlined,
                    value: '$orderCount',
                    label: 'Orders',
                    onTap: () => navIndex.value = 3,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    icon: Icons.favorite_border,
                    value: '${wishlist.count}',
                    label: 'Wishlist',
                    onTap: () => navIndex.value = 2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    icon: Icons.shopping_cart_outlined,
                    value: '${cart.count}',
                    label: 'In cart',
                    onTap: () => navIndex.value = 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Detail
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    _InfoRow(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: u.phone),
                    _InfoRow(
                        icon: Icons.location_on_outlined,
                        label: 'Address',
                        value: u.address.isEmpty ? null : u.address),
                    _InfoRow(
                        icon: Icons.wc_outlined,
                        label: 'Gender',
                        value: u.gender),
                    _InfoRow(
                        icon: Icons.cake_outlined,
                        label: 'Age',
                        value: u.age == null ? null : '${u.age}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfilePage()),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Profile',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
              ),
              onPressed: () => confirmLogout(context),
              icon: const Icon(Icons.logout),
              label: const Text('Logout',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Akun tersimpan lokal di perangkat ini',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.4))),
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  const _InfoRow({required this.icon, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final empty = value == null || value!.isEmpty;
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label,
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
      subtitle: Text(
        empty ? 'Belum diisi' : value!,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: empty ? Colors.black38 : Colors.black87,
          fontStyle: empty ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _age;
  String? _gender;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = auth.user!;
    _name = TextEditingController(text: u.name);
    _phone = TextEditingController(text: u.phone);
    _address = TextEditingController(text: u.address);
    _age = TextEditingController(text: u.age?.toString() ?? '');
    _gender = u.gender;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _age]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    await auth.updateProfile(
      auth.user!.withProfile(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        gender: _gender,
        age: int.tryParse(_age.text),
      ),
    );

    nav.pop();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade800,
        content: const Text('Profil berhasil diperbarui'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = auth.user!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ListenableBuilder(
                listenable: _name,
                builder: (context, _) =>
                    UserAvatar(name: _name.text, radius: 44),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Full name *',
                  prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Isi nama lengkap (min. 3 karakter)'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: u.email,
              enabled: false,
              decoration: const InputDecoration(
                  labelText: 'Email (tidak bisa diubah)',
                  prefixIcon: Icon(Icons.mail_outline)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(15),
              ],
              decoration: const InputDecoration(
                  labelText: 'Phone number *',
                  prefixIcon: Icon(Icons.phone_outlined)),
              validator: (v) => (v == null || v.length < 8)
                  ? 'Nomor telepon tidak valid'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.location_on_outlined)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _age,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: const InputDecoration(
                  labelText: 'Age (optional)',
                  prefixIcon: Icon(Icons.cake_outlined)),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = int.tryParse(v);
                return (n == null || n < 1 || n > 120)
                    ? 'Umur tidak valid'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            const Text('Gender (optional)',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            GenderPicker(
              value: _gender,
              onChanged: (g) => setState(() => _gender = g),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save Changes',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// CART PAGE
// ------------------------------------------------------------
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        if (cart.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 80, color: Colors.green.shade200),
                const SizedBox(height: 12),
                const Text('Keranjang masih kosong',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(180, 46)),
                  onPressed: () => navIndex.value = 0,
                  child: const Text('Mulai belanja'),
                ),
              ],
            ),
          );
        }

        final items = cart.items;
        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _CartTile(item: items[i]),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -4)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal (${cart.count} items)',
                            style: const TextStyle(color: Colors.black54)),
                        Text(money(cart.subtotal),
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CheckoutPage()),
                      ),
                      child: const Text('Checkout',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CartTile extends StatelessWidget {
  final CartItem item;
  const _CartTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Image.network(p.image, fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(money(p.price),
                      style: TextStyle(
                          color: scheme.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _QtyButton(
                          icon: Icons.remove, onTap: () => cart.decrement(p)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('${item.qty}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      _QtyButton(icon: Icons.add, onTap: () => cart.add(p)),
                      const Spacer(),
                      Text(money(item.total),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => cart.remove(p),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

// ------------------------------------------------------------
// CHECKOUT + PAYMENT (simulasi, frontend only)
// ------------------------------------------------------------
enum PayMethod { card, bank, ewallet, cod }

extension PayMethodX on PayMethod {
  String get label => switch (this) {
        PayMethod.card => 'Credit / Debit Card',
        PayMethod.bank => 'Bank Transfer (Virtual Account)',
        PayMethod.ewallet => 'E-Wallet',
        PayMethod.cod => 'Cash on Delivery',
      };
  IconData get icon => switch (this) {
        PayMethod.card => Icons.credit_card,
        PayMethod.bank => Icons.account_balance,
        PayMethod.ewallet => Icons.account_balance_wallet_outlined,
        PayMethod.cod => Icons.payments_outlined,
      };
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  final _cardNo = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();

  PayMethod _method = PayMethod.card;
  bool _express = false;

  double get _shipping => _express ? 8.0 : 3.0;
  double get _total => cart.subtotal + _shipping;

  @override
  void initState() {
    super.initState();
    // Isi otomatis dari profil user
    final u = auth.user;
    _name = TextEditingController(text: u?.name ?? '');
    _phone = TextEditingController(text: u?.phone ?? '');
    _address = TextEditingController(text: u?.address ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _cardNo, _expiry, _cvv]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pay() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 8),
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Memproses pembayaran...',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // tutup dialog

    final order = Order(
      id: 'ORD-${DateTime.now().millisecondsSinceEpoch % 1000000}',
      userEmail: auth.user?.email ?? '',
      date: DateTime.now(),
      items: cart.items.map((i) => CartItem(i.product, i.qty)).toList(),
      total: _total,
      paymentMethod: _method.label,
    );
    orderStore.add(order);
    cart.clear();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SuccessPage(order: order)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Shipping Address'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Isi nama lengkap'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined)),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'Nomor HP tidak valid' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Full address',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.location_on_outlined)),
              validator: (v) => (v == null || v.trim().length < 8)
                  ? 'Isi alamat lengkap'
                  : null,
            ),
            const SizedBox(height: 20),
            _section('Shipping Method'),
            _OptionTile(
              icon: Icons.local_shipping_outlined,
              title: 'Standard (3-5 days)',
              trailing: money(3),
              selected: !_express,
              onTap: () => setState(() => _express = false),
            ),
            const SizedBox(height: 8),
            _OptionTile(
              icon: Icons.bolt,
              title: 'Express (1-2 days)',
              trailing: money(8),
              selected: _express,
              onTap: () => setState(() => _express = true),
            ),
            const SizedBox(height: 20),
            _section('Payment Method'),
            for (final m in PayMethod.values) ...[
              _OptionTile(
                icon: m.icon,
                title: m.label,
                selected: _method == m,
                onTap: () => setState(() => _method = m),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            _paymentDetail(scheme),
            const SizedBox(height: 20),
            _section('Order Summary'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    for (final i in cart.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text('${i.qty}x  ${i.product.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            Text(money(i.total)),
                          ],
                        ),
                      ),
                    const Divider(),
                    _row('Subtotal', money(cart.subtotal)),
                    _row('Shipping', money(_shipping)),
                    const SizedBox(height: 4),
                    _row('Total', money(_total), bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pay,
              icon: const Icon(Icons.lock_outline),
              label: Text(
                _method == PayMethod.cod
                    ? 'Place Order • ${money(_total)}'
                    : 'Pay ${money(_total)}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text('Demo only — no real payment is processed',
                  style: TextStyle(fontSize: 11, color: Colors.black45)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _paymentDetail(ColorScheme scheme) {
    switch (_method) {
      case PayMethod.card:
        return Column(
          children: [
            TextFormField(
              controller: _cardNo,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: const InputDecoration(
                  labelText: 'Card number',
                  hintText: '4242424242424242',
                  prefixIcon: Icon(Icons.credit_card)),
              validator: (v) => (v == null || v.length != 16)
                  ? 'Nomor kartu 16 digit'
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _expiry,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      _ExpiryFormatter(),
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Expiry', hintText: 'MM/YY'),
                    validator: (v) {
                      if (v == null || v.length != 5) return 'MM/YY';
                      final mm = int.tryParse(v.substring(0, 2)) ?? 0;
                      return (mm < 1 || mm > 12) ? 'Bulan salah' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cvv,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(labelText: 'CVV'),
                    validator: (v) =>
                        (v == null || v.length < 3) ? '3-4 digit' : null,
                  ),
                ),
              ],
            ),
          ],
        );
      case PayMethod.bank:
        return _infoBox(
          'Virtual Account akan dibuat setelah kamu menekan tombol Pay.\n'
          'Contoh: 8808 1234 5678 9012 (demo).',
          Icons.info_outline,
          scheme,
        );
      case PayMethod.ewallet:
        return _infoBox(
          'Kamu akan diarahkan ke aplikasi e-wallet untuk konfirmasi (simulasi).',
          Icons.info_outline,
          scheme,
        );
      case PayMethod.cod:
        return _infoBox(
          'Bayar tunai ke kurir saat pesanan sampai.',
          Icons.info_outline,
          scheme,
        );
    }
  }

  Widget _infoBox(String text, IconData icon, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _row(String l, String r, {bool bold = false}) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        fontSize: bold ? 17 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(l, style: style), Text(r, style: style)],
      ),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('/', '');
    final text = digits.length > 2
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.6)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : Colors.green.shade100,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? scheme.primary : Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(trailing!,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? scheme.primary : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// SUCCESS PAGE
// ------------------------------------------------------------
class SuccessPage extends StatelessWidget {
  final Order order;
  const SuccessPage({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (context, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 70),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Payment Successful!',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Terima kasih, pesananmu sedang diproses.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _kv('Order ID', order.id),
                            _kv('Date', formatDate(order.date)),
                            _kv('Payment', order.paymentMethod),
                            const Divider(height: 24),
                            _kv('Total', money(order.total), bold: true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        navIndex.value = 0;
                        Navigator.popUntil(context, (r) => r.isFirst);
                      },
                      child: const Text('Back to Shop'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        navIndex.value = 3;
                        Navigator.popUntil(context, (r) => r.isFirst);
                      },
                      child: const Text('View Order History'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: const TextStyle(color: Colors.black54)),
            const SizedBox(width: 16),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      fontSize: bold ? 17 : 14)),
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------
// ORDER HISTORY PAGE (per user)
// ------------------------------------------------------------
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([orderStore, auth]),
      builder: (context, _) {
        final orders = orderStore.ordersFor(auth.user?.email);
        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 80, color: Colors.green.shade200),
                const SizedBox(height: 12),
                const Text('Belum ada pesanan',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final o = orders[i];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.check_circle_outline),
                  ),
                  title: Text(o.id,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${formatDate(o.date)}  •  ${o.paymentMethod}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: Text(money(o.total),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    for (final it in o.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${it.qty}x  ${it.product.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                            Text(money(it.total),
                                style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}