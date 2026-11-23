import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ============================================================
//  GreenCart - simple cart app (FakeStore API)
//  Dependency: flutter pub add http
// ============================================================

void main() {
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
  final DateTime date;
  final List<CartItem> items;
  final double total;
  final String paymentMethod;

  Order({
    required this.id,
    required this.date,
    required this.items,
    required this.total,
    required this.paymentMethod,
  });
}

// ------------------------------------------------------------
// STATE (simple ChangeNotifier, tanpa package tambahan)
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
  List<Order> get orders => List.unmodifiable(_orders.reversed);

  void add(Order o) {
    _orders.add(o);
    notifyListeners();
  }
}

final cart = CartController();
final orderStore = OrderController();
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
      ),
      home: const HomeShell(),
    );
  }
}

// ------------------------------------------------------------
// SHELL: AppBar + Drawer + halaman
// ------------------------------------------------------------
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _titles = ['Products', 'My Cart', 'Order History'];

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
              OrdersPage(),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, Colors.green.shade800],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.eco, color: Color(0xFF2E9E5B), size: 32),
                  ),
                  SizedBox(height: 14),
                  Text('GreenCart',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Simple shopping, powered by FakeStore API',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  item(Icons.storefront_outlined, 'Products', 0),
                  ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) => item(
                      Icons.shopping_cart_outlined,
                      'My Cart',
                      1,
                      trailing: cart.count > 0
                          ? CircleAvatar(
                              radius: 11,
                              backgroundColor: scheme.primary,
                              child: Text('${cart.count}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white)),
                            )
                          : null,
                    ),
                  ),
                  item(Icons.receipt_long_outlined, 'Order History', 2),
                ],
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('v1.0.0 • Demo only, payment is simulated',
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
    _future = fetchProducts();
  }

  void _reload() => setState(() => _future = fetchProducts());

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
            await _future;
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
                  sliver: SliverLayoutBuilder(
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
                  ),
                ),
            ],
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
                child: Center(
                  child: Image.network(
                    product.image,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, p) => p == null
                        ? child
                        : const Center(
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))),
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.black26,
                        size: 40),
                  ),
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
                  Chip(
                    label: Text(titleCase(p.category)),
                    visualDensity: VisualDensity.compact,
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
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _cardNo = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();

  PayMethod _method = PayMethod.card;
  bool _express = false;

  double get _shipping => _express ? 8.0 : 3.0;
  double get _total => cart.subtotal + _shipping;

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

    // Dialog loading "memproses pembayaran"
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
                  labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) =>
                  (v == null || v.trim().length < 3) ? 'Isi nama lengkap' : null,
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
              validator: (v) =>
                  (v == null || v.trim().length < 8) ? 'Isi alamat lengkap' : null,
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
              validator: (v) =>
                  (v == null || v.length != 16) ? 'Nomor kartu 16 digit' : null,
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
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.6) : Colors.white,
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
                        navIndex.value = 2;
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
// ORDER HISTORY PAGE
// ------------------------------------------------------------
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: orderStore,
      builder: (context, _) {
        final orders = orderStore.orders;
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