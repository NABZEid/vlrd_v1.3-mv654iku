// VILLIARD v1.3 - game billiard bergaya 8 Ball Pool (Flutter)
// Fitur: lobi bergaya 8 Ball Pool, profil (username, avatar, level, statistik),
// skin cue (beli & pakai), skin meja otomatis per arena, 6 arena,
// uang awal Rp 2.000.000, fisika bola, aturan 8-ball, lawan AI,
// kontrol drag-to-aim + power slider kiri, ball-in-hand.
// Fitur tambahan (inject coins, autoplay, pantulan, auto queue, long line)
// dikontrol dari aplikasi pendamping Bloader lewat jembatan lokal 127.0.0.1.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show ContentType, HttpRequest, HttpServer, InternetAddress;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ======================================================================
// KONSTANTA MEJA
// ======================================================================
const double kW = 800; // lebar area main
const double kH = 400; // tinggi area main
const double kR = 10.5; // jari-jari bola
const double kRail = 38; // tebal kayu

const List<Offset> kPockets = [
  Offset(0, 0),
  Offset(kW / 2, -5),
  Offset(kW, 0),
  Offset(0, kH),
  Offset(kW / 2, kH + 5),
  Offset(kW, kH),
];

double pocketRadius(int i) => (i == 1 || i == 4) ? 22 : 25;

const List<Color> kBallColors = [
  Color(0xFFF5F5F5), // 0 putih
  Color(0xFFF2C500), // 1
  Color(0xFF1F4FD8), // 2
  Color(0xFFD62828), // 3
  Color(0xFF6A1B9A), // 4
  Color(0xFFF57C00), // 5
  Color(0xFF1B8A3A), // 6
  Color(0xFF8B1E2D), // 7
  Color(0xFF111111), // 8
  Color(0xFFF2C500), // 9
  Color(0xFF1F4FD8), // 10
  Color(0xFFD62828), // 11
  Color(0xFF6A1B9A), // 12
  Color(0xFFF57C00), // 13
  Color(0xFF1B8A3A), // 14
  Color(0xFF8B1E2D), // 15
];

// ======================================================================
// ARENA
// ======================================================================
// Skin meja: setiap arena punya tampilan meja sendiri.
class TableSkin {
  final String title;
  final Color railTop, railBottom, trim, sight;
  // motif kain: 0 polos, 1 garis, 2 berlian, 3 bintang, 4 lingkaran, 5 diagonal
  final int pattern;
  const TableSkin(this.title, this.railTop, this.railBottom, this.trim,
      this.sight, this.pattern);
}

const List<String> kPatternNames = [
  'Polos',
  'Garis',
  'Berlian',
  'Bintang',
  'Lingkaran',
  'Diagonal',
];

class Venue {
  final String name, country, flag, ai;
  final int fee;
  final Color felt, accent;
  final double aiError; // makin kecil makin jago
  final TableSkin skin;
  const Venue(this.name, this.country, this.flag, this.ai, this.fee, this.felt,
      this.accent, this.aiError, this.skin);
}

const List<Venue> kVenues = [
  Venue(
      'Bandung',
      'Indonesia',
      '🇮🇩',
      'Asep',
      50000,
      Color(0xFF1E7A46),
      Color(0xFF4ADE80),
      0.060,
      TableSkin('Meja Kayu Jati', Color(0xFF8A5A2B), Color(0xFF4A2C14),
          Color(0xFF4ADE80), Color(0xFFF5E6C8), 0)),
  Venue(
      'Jakarta',
      'Indonesia',
      '🇮🇩',
      'Bang Jago',
      100000,
      Color(0xFF1D5FB4),
      Color(0xFF60A5FA),
      0.045,
      TableSkin('Meja Metro Baja', Color(0xFF4B5563), Color(0xFF1F2937),
          Color(0xFF60A5FA), Color(0xFFE5E7EB), 1)),
  Venue(
      'Bekasi',
      'Indonesia',
      '🇮🇩',
      'Ujang',
      200000,
      Color(0xFF0F766E),
      Color(0xFF2DD4BF),
      0.035,
      TableSkin('Meja Walnut Teal', Color(0xFF6B4423), Color(0xFF2E1B0E),
          Color(0xFF2DD4BF), Color(0xFFF5E6C8), 2)),
  Venue(
      'Singapore',
      'Singapore',
      '🇸🇬',
      'Mr. Tan',
      500000,
      Color(0xFFA3262F),
      Color(0xFFF87171),
      0.025,
      TableSkin('Meja Lakuer Merah', Color(0xFF2B2B2B), Color(0xFF0A0A0A),
          Color(0xFFF87171), Color(0xFFFDE68A), 3)),
  Venue(
      'Thailand',
      'Thailand',
      '🇹🇭',
      'Somchai',
      1000000,
      Color(0xFF5B2A86),
      Color(0xFFC084FC),
      0.016,
      TableSkin('Meja Ungu Royal', Color(0xFF5B2A86), Color(0xFF24103A),
          Color(0xFFC084FC), Color(0xFFFDE68A), 4)),
  Venue(
      'Malaysia',
      'Malaysia',
      '🇲🇾',
      'Encik Amir',
      2000000,
      Color(0xFF0B2E6B),
      Color(0xFFFACC15),
      0.008,
      TableSkin('Meja Emas Sultan', Color(0xFFE5B73B), Color(0xFF8A6A12),
          Color(0xFFFFFFFF), Color(0xFF0B2E6B), 5)),
];

// ======================================================================
// UANG
// ======================================================================
String rp(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return 'Rp ${v < 0 ? '-' : ''}$b';
}

class Wallet {
  static const int startCoins = 2000000; // uang pertama 2M
  static final ValueNotifier<int> coins = ValueNotifier<int>(startCoins);
  static SharedPreferences? _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    coins.value = _p!.getInt('coins') ?? startCoins;
  }

  static Future<void> add(int d) async {
    coins.value += d;
    await _p?.setInt('coins', coins.value);
  }
}

// ======================================================================
// SKIN CUE
// ======================================================================
class CueSkin {
  final String id, name, desc;
  final int price, level; // harga & level minimal
  final List<Color> shaft; // 3 warna: ujung -> pangkal
  final Color ring, tip;
  final bool glow;
  const CueSkin(this.id, this.name, this.desc, this.price, this.level,
      this.shaft, this.ring, this.tip,
      {this.glow = false});
}

const List<CueSkin> kCues = [
  CueSkin('classic', 'Klasik', 'Kayu maple standar', 0, 1,
      [Color(0xFFF3D9A4), Color(0xFFB9803F), Color(0xFF3A2312)],
      Color(0xFFC9A227), Color(0xFF3B82F6)),
  CueSkin('ebony', 'Eboni', 'Hitam elegan dengan cincin emas', 250000, 2,
      [Color(0xFFD9C7A0), Color(0xFF2B2B2B), Color(0xFF0A0A0A)],
      Color(0xFFD4AF37), Color(0xFF22C55E)),
  CueSkin('ruby', 'Ruby', 'Merah menyala', 500000, 3,
      [Color(0xFFFDE2E2), Color(0xFFDC2626), Color(0xFF450A0A)],
      Color(0xFFFACC15), Color(0xFFEF4444)),
  CueSkin('ocean', 'Samudra', 'Biru laut dalam', 750000, 5,
      [Color(0xFFE0F2FE), Color(0xFF0284C7), Color(0xFF0C2A4A)],
      Color(0xFF22D3EE), Color(0xFF38BDF8)),
  CueSkin('gold', 'Emas Sultan', 'Berkilau keemasan', 2500000, 8,
      [Color(0xFFFFF7CC), Color(0xFFF5B301), Color(0xFF7A4B00)],
      Color(0xFFFFFFFF), Color(0xFF111111),
      glow: true),
  CueSkin('galaxy', 'Galaksi', 'Ungu kosmik bercahaya', 4000000, 12,
      [Color(0xFFF5D0FE), Color(0xFF9333EA), Color(0xFF1E1B4B)],
      Color(0xFF22D3EE), Color(0xFFF472B6),
      glow: true),
];

// Menggambar cue dari [tip] (ujung pukul) ke arah berlawanan [dir].
void drawCue(Canvas c, CueSkin s, Offset tip, Offset dir,
    {double length = 480,
    double wTip = 2.2,
    double wEnd = 5,
    bool shadow = true}) {
  final perp = Offset(-dir.dy, dir.dx);
  final end = tip - dir * length;
  final path = Path()
    ..moveTo(tip.dx + perp.dx * wTip, tip.dy + perp.dy * wTip)
    ..lineTo(end.dx + perp.dx * wEnd, end.dy + perp.dy * wEnd)
    ..lineTo(end.dx - perp.dx * wEnd, end.dy - perp.dy * wEnd)
    ..lineTo(tip.dx - perp.dx * wTip, tip.dy - perp.dy * wTip)
    ..close();
  if (shadow) {
    c.drawPath(path.shift(const Offset(3, 4)),
        Paint()..color = Colors.black.withAlpha(70));
  }
  if (s.glow) {
    c.drawPath(
        path,
        Paint()
          ..color = s.ring.withAlpha(140)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }
  c.drawPath(
      path,
      Paint()
        ..shader =
            ui.Gradient.linear(tip, end, s.shaft, const [0.0, 0.55, 1.0]));
  final band = max(1.5, length * 0.009);
  for (final f in const [0.70, 0.745]) {
    final m = tip - dir * (length * f);
    final w = wTip + (wEnd - wTip) * f;
    c.drawLine(m + perp * w, m - perp * w,
        Paint()
          ..color = s.ring
          ..strokeWidth = band);
  }
  c.drawLine(
      tip,
      tip - dir * max(4.0, length * 0.02),
      Paint()
        ..color = s.tip
        ..strokeWidth = wTip * 2.1);
}

// ======================================================================
// PROFIL PEMAIN
// ======================================================================
const List<String> kAvatars = ['😎', '🤠', '🦊', '🐯', '🐼', '👑', '🔥', '🚀'];
const List<Color> kAvatarColors = [
  Color(0xFF3B82F6),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFF22C55E),
  Color(0xFFCA8A04),
  Color(0xFFDC2626),
  Color(0xFF8B5CF6),
];

String? validateName(String raw) {
  final s = raw.trim();
  if (s.length < 3) return 'Minimal 3 karakter';
  if (s.length > 14) return 'Maksimal 14 karakter';
  if (!RegExp(r'^[A-Za-z0-9_ ]+$').hasMatch(s)) {
    return 'Hanya huruf, angka, spasi, dan _';
  }
  return null;
}

class ProfileStore extends ChangeNotifier {
  ProfileStore._();
  static final ProfileStore i = ProfileStore._();

  static const int xpPerLevel = 100;
  static const int xpWin = 40, xpLose = 10;

  SharedPreferences? _p;
  String name = '';
  int avatar = 0, wins = 0, losses = 0, xp = 0;
  String cueId = 'classic';
  Set<String> owned = {'classic'};

  bool get isNew => name.isEmpty;
  int get level => 1 + xp ~/ xpPerLevel;
  double get levelProgress => (xp % xpPerLevel) / xpPerLevel;
  int get games => wins + losses;
  int get winRate => games == 0 ? 0 : (wins * 100 / games).round();
  CueSkin get cue =>
      kCues.firstWhere((c) => c.id == cueId, orElse: () => kCues.first);

  Future<void> init() async {
    final p = _p = await SharedPreferences.getInstance();
    name = p.getString('p_name') ?? '';
    avatar = (p.getInt('p_avatar') ?? 0) % kAvatars.length;
    wins = p.getInt('p_wins') ?? 0;
    losses = p.getInt('p_losses') ?? 0;
    xp = p.getInt('p_xp') ?? 0;
    cueId = p.getString('p_cue') ?? 'classic';
    owned = (p.getStringList('p_owned') ?? <String>['classic']).toSet()
      ..add('classic');
  }

  Future<void> _save() async {
    final p = _p;
    if (p == null) return;
    await p.setString('p_name', name);
    await p.setInt('p_avatar', avatar);
    await p.setInt('p_wins', wins);
    await p.setInt('p_losses', losses);
    await p.setInt('p_xp', xp);
    await p.setString('p_cue', cueId);
    await p.setStringList('p_owned', owned.toList());
  }

  Future<void> setProfile(String newName, int newAvatar) async {
    name = newName.trim();
    avatar = newAvatar % kAvatars.length;
    notifyListeners();
    await _save();
  }

  // Catat hasil pertandingan. Mengembalikan true jika naik level.
  Future<bool> record(bool win) async {
    final before = level;
    if (win) {
      wins++;
      xp += xpWin;
    } else {
      losses++;
      xp += xpLose;
    }
    notifyListeners();
    await _save();
    return level > before;
  }

  Future<void> equip(String id) async {
    if (!owned.contains(id)) return;
    cueId = id;
    notifyListeners();
    await _save();
  }

  Future<bool> buy(CueSkin c) async {
    if (owned.contains(c.id) ||
        level < c.level ||
        Wallet.coins.value < c.price) {
      return false;
    }
    await Wallet.add(-c.price);
    owned.add(c.id);
    cueId = c.id;
    notifyListeners();
    await _save();
    return true;
  }
}

// ======================================================================
// MOD (fitur tambahan)
// ======================================================================
class Mod extends ChangeNotifier {
  Mod._();
  static final Mod i = Mod._();
  static const int injectAmount = 1000000;

  SharedPreferences? _p;
  bool autoplay = false, autoQueue = false, longLine = false, autoBounce = false;

  bool get anyOn => autoplay || autoQueue || longLine || autoBounce;

  Future<void> init() async {
    final p = _p = await SharedPreferences.getInstance();
    autoplay = p.getBool('m_auto') ?? false;
    autoQueue = p.getBool('m_queue') ?? false;
    longLine = p.getBool('m_long') ?? false;
    autoBounce = p.getBool('m_bounce') ?? false;
    if (autoBounce) autoplay = true;
  }

  void set({bool? autoplay, bool? autoQueue, bool? longLine, bool? autoBounce}) {
    if (autoplay != null) {
      this.autoplay = autoplay;
      if (!autoplay) this.autoBounce = false;
    }
    if (autoBounce != null) {
      this.autoBounce = autoBounce;
      if (autoBounce) this.autoplay = true;
    }
    if (autoQueue != null) this.autoQueue = autoQueue;
    if (longLine != null) this.longLine = longLine;
    notifyListeners();
    final p = _p;
    if (p != null) {
      p.setBool('m_auto', this.autoplay);
      p.setBool('m_queue', this.autoQueue);
      p.setBool('m_long', this.longLine);
      p.setBool('m_bounce', this.autoBounce);
    }
  }
}

// ======================================================================
// JEMBATAN BLOADER (hanya loopback 127.0.0.1, wajib token)
// ======================================================================
class Bridge {
  static const int port = 38417;
  static const String token = 'BLDR-7f3a91c2-VLRD-ONLY';
  static HttpServer? _s;

  static Future<void> start() async {
    if (_s != null) return;
    try {
      _s = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } catch (_) {
      return;
    }
    _s!.listen(_handle, onError: (_) {});
  }

  static Map<String, dynamic> _state() => {
        'app': 'villiard',
        'autoplay': Mod.i.autoplay,
        'autoBounce': Mod.i.autoBounce,
        'autoQueue': Mod.i.autoQueue,
        'longLine': Mod.i.longLine,
        'coins': Wallet.coins.value,
      };

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.headers.value('x-bloader-token') != token) {
        res.statusCode = 403;
        await res.close();
        return;
      }
      Map<String, dynamic> out;
      switch (req.uri.path) {
        case '/hello':
        case '/state':
          out = _state();
          break;
        case '/set':
          final txt = await utf8.decoder.bind(req).join();
          final j = jsonDecode(txt);
          if (j is Map<String, dynamic>) {
            bool? b(String k) => j[k] is bool ? j[k] as bool : null;
            Mod.i.set(
              autoplay: b('autoplay'),
              autoBounce: b('autoBounce'),
              autoQueue: b('autoQueue'),
              longLine: b('longLine'),
            );
          }
          out = _state();
          break;
        case '/coins':
          await Wallet.add(Mod.injectAmount);
          out = _state();
          break;
        default:
          res.statusCode = 404;
          await res.close();
          return;
      }
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(out));
    } catch (_) {
      res.statusCode = 500;
    }
    await res.close();
  }
}

// ======================================================================
// MAIN
// ======================================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Wallet.init();
  await ProfileStore.i.init();
  await Mod.i.init();
  await Bridge.start();
  runApp(const VilliardApp());
}

class VilliardApp extends StatelessWidget {
  const VilliardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Villiard',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF1E88FF),
      ),
      home: const SplashScreen(),
    );
  }
}

// ======================================================================
// SPLASH
// ======================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LobbyScreen()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B1A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 220),
            const SizedBox(height: 8),
            const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// WIDGET BERSAMA
// ======================================================================
class _Avatar extends StatelessWidget {
  final int index;
  final double size;
  final bool selected;
  const _Avatar({required this.index, this.size = 40, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final i = index % kAvatars.length;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kAvatarColors[i],
        border: Border.all(
            color: selected ? Colors.white : Colors.white30,
            width: selected ? 3 : 1.5),
      ),
      child: Text(kAvatars[i], style: TextStyle(fontSize: size * 0.55)),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }
}

class _CoinPill extends StatelessWidget {
  const _CoinPill();
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Wallet.coins,
      builder: (_, c, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c < kVenues.first.fee)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: () => Wallet.add(500000),
                child: const Text('Bonus Rp 500.000'),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(rp(c),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFFFACC15))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Pratinjau cue horizontal.
class _CuePainter extends CustomPainter {
  final CueSkin s;
  _CuePainter(this.s);
  @override
  void paint(Canvas c, Size size) {
    drawCue(c, s, Offset(size.width - 4, size.height / 2), const Offset(1, 0),
        length: max(10.0, size.width - 12),
        wTip: 2.2,
        wEnd: 5,
        shadow: false);
  }

  @override
  bool shouldRepaint(covariant _CuePainter old) => old.s != s;
}

// Ikon cue miring untuk tombol menu.
class _CueIconPainter extends CustomPainter {
  final CueSkin s;
  _CueIconPainter(this.s);
  @override
  void paint(Canvas c, Size size) {
    drawCue(c, s, Offset(size.width - 3, 3), Offset(0.7071, -0.7071),
        length: size.width * 1.3,
        wTip: 1.4,
        wEnd: 3,
        shadow: false);
  }

  @override
  bool shouldRepaint(covariant _CueIconPainter old) => old.s != s;
}

// ======================================================================
// EDITOR PROFIL (username + avatar)
// ======================================================================
Future<void> showProfileEditor(BuildContext context, {bool first = false}) {
  final ctrl = TextEditingController(text: ProfileStore.i.name);
  var av = ProfileStore.i.avatar;
  String? err;
  return showDialog<void>(
    context: context,
    barrierDismissible: !first,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setS) => PopScope(
        canPop: !first,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0E1A33),
          title: Text(first ? 'Selamat datang! 👋' : 'Ubah profil'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  maxLength: 14,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    hintText: 'Contoh: RajaBiliar',
                    errorText: err,
                    counterText: '',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Pilih avatar',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < kAvatars.length; i++)
                      GestureDetector(
                        onTap: () => setS(() => av = i),
                        child: _Avatar(index: i, size: 44, selected: av == i),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (!first)
              TextButton(
                  onPressed: () => Navigator.pop(dctx),
                  child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                final e = validateName(ctrl.text);
                if (e != null) {
                  setS(() => err = e);
                  return;
                }
                await ProfileStore.i.setProfile(ctrl.text, av);
                if (dctx.mounted) Navigator.pop(dctx);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ======================================================================
// LOBI (gaya 8 Ball Pool)
// ======================================================================
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ProfileStore.i.isNew) {
        showProfileEditor(context, first: true);
      }
    });
  }

  Future<void> _play(Venue v) async {
    if (Wallet.coins.value < v.fee) return;
    await Wallet.add(-v.fee);
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GameScreen(venue: v)));
  }

  void _open(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF050B1A), Color(0xFF0A1F44)]),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    _ProfileChip(
                        onTap: () => _open(const ProfileScreen())),
                    Expanded(
                      child: Center(
                          child: Image.asset('assets/logo.png', height: 46)),
                    ),
                    const _CoinPill(),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MenuButton(
                                label: 'Profil',
                                onTap: () => _open(const ProfileScreen()),
                                child: AnimatedBuilder(
                                  animation: ProfileStore.i,
                                  builder: (_, __) => Text(
                                      kAvatars[ProfileStore.i.avatar],
                                      style: const TextStyle(fontSize: 26)),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _MenuButton(
                                label: 'Cue',
                                onTap: () =>
                                    _open(const CollectionScreen(initialTab: 0)),
                                child: AnimatedBuilder(
                                  animation: ProfileStore.i,
                                  builder: (_, __) => CustomPaint(
                                    size: const Size(34, 34),
                                    painter: _CueIconPainter(ProfileStore.i.cue),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _MenuButton(
                                label: 'Meja',
                                onTap: () =>
                                    _open(const CollectionScreen(initialTab: 1)),
                                child: const Icon(Icons.table_restaurant,
                                    color: Colors.white70, size: 28),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          const Text('PILIH ARENA',
                              style: TextStyle(
                                  letterSpacing: 3,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white70)),
                          Expanded(
                            child: ValueListenableBuilder<int>(
                              valueListenable: Wallet.coins,
                              builder: (_, coins, __) => ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.fromLTRB(4, 10, 16, 14),
                                itemCount: kVenues.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (ctx, i) {
                                  final v = kVenues[i];
                                  return _VenueCard(
                                    venue: v,
                                    enabled: coins >= v.fee,
                                    onTap: () => _play(v),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final Widget child;
  final VoidCallback onTap;
  const _MenuButton(
      {required this.label, required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF3B82F6).withAlpha(170), width: 1.5),
            ),
            child: child,
          ),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ProfileChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProfileStore.i,
      builder: (_, __) {
        final p = ProfileStore.i;
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Avatar(index: p.avatar, size: 38),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(p.isNew ? 'Pemain' : p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Lv ${p.level}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFACC15))),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 70,
                          height: 5,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: p.levelProgress,
                              backgroundColor: Colors.white12,
                              color: const Color(0xFFFACC15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VenueCard extends StatelessWidget {
  final Venue venue;
  final bool enabled;
  final VoidCallback onTap;
  const _VenueCard(
      {required this.venue, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = venue;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(v.felt, Colors.white, 0.1)!,
                Color.lerp(v.felt, Colors.black, 0.6)!
              ]),
          border: Border.all(color: v.accent, width: 2),
          boxShadow: [BoxShadow(color: v.accent.withAlpha(90), blurRadius: 14)],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(v.flag, style: const TextStyle(fontSize: 26)),
                const Spacer(),
                Text('vs ${v.ai}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(v.name.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: CustomPaint(
                    size: Size.infinite, painter: _MiniTablePainter(v)),
              ),
            ),
            Text(v.skin.title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: v.accent)),
            Text('Taruhan ${rp(v.fee)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text('Hadiah ${rp(v.fee * 2)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: v.accent)),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: enabled ? onTap : null,
                child: Text(enabled ? 'MAIN' : 'Uang kurang'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// LAYAR PROFIL
// ======================================================================
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Widget _stat(String label, String value, [Color? color]) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A33),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: color ?? Colors.white)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07122A),
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: const Color(0xFF050B1A),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: _CoinPill()),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: ProfileStore.i,
          builder: (ctx, _) {
            final p = ProfileStore.i;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: _Panel(
                      child: Column(
                        children: [
                          _Avatar(index: p.avatar, size: 84),
                          const SizedBox(height: 10),
                          Text(p.isNew ? 'Pemain' : p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('Level ${p.level}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFACC15))),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: p.levelProgress,
                              minHeight: 8,
                              backgroundColor: Colors.white12,
                              color: const Color(0xFFFACC15),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                              '${p.xp % ProfileStore.xpPerLevel}/${ProfileStore.xpPerLevel} XP',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white60)),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => showProfileEditor(ctx),
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Ubah profil'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _stat('Menang', '${p.wins}',
                                const Color(0xFF4ADE80)),
                            const SizedBox(width: 8),
                            _stat('Kalah', '${p.losses}',
                                const Color(0xFFF87171)),
                            const SizedBox(width: 8),
                            _stat('Main', '${p.games}'),
                            const SizedBox(width: 8),
                            _stat('Win rate', '${p.winRate}%',
                                const Color(0xFFFACC15)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Panel(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Cue dipakai',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white60)),
                                    Text(p.cue.name,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 30,
                                      child: CustomPaint(
                                          size: Size.infinite,
                                          painter: _CuePainter(p.cue)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.tonal(
                                onPressed: () => Navigator.of(ctx).push(
                                    MaterialPageRoute(
                                        builder: (_) => const CollectionScreen(
                                            initialTab: 0))),
                                child: const Text('Ganti'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ======================================================================
// KOLEKSI: CUE & MEJA
// ======================================================================
class CollectionScreen extends StatelessWidget {
  final int initialTab;
  const CollectionScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: const Color(0xFF07122A),
        appBar: AppBar(
          title: const Text('Koleksi'),
          backgroundColor: const Color(0xFF050B1A),
          actions: const [
            Padding(padding: EdgeInsets.only(right: 12), child: _CoinPill()),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Cue'), Tab(text: 'Meja')]),
        ),
        body: const SafeArea(
          child: TabBarView(children: [_CueTab(), _TableTab()]),
        ),
      ),
    );
  }
}

class _CueTab extends StatelessWidget {
  const _CueTab();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProfileStore.i,
      builder: (_, __) => ValueListenableBuilder<int>(
        valueListenable: Wallet.coins,
        builder: (ctx, coins, __) {
          final p = ProfileStore.i;
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: kCues.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = kCues[i];
              final owned = p.owned.contains(c.id);
              final equipped = p.cueId == c.id;
              final locked = !owned && p.level < c.level;
              final Widget btn;
              if (equipped) {
                btn = FilledButton.tonal(
                    onPressed: null, child: const Text('Dipakai'));
              } else if (owned) {
                btn = FilledButton(
                    onPressed: () => p.equip(c.id), child: const Text('Pakai'));
              } else if (locked) {
                btn = FilledButton(
                    onPressed: null, child: Text('Level ${c.level}'));
              } else {
                btn = FilledButton(
                  onPressed: coins >= c.price ? () => p.buy(c) : null,
                  child: Text(rp(c.price)),
                );
              }
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1A33),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: equipped ? const Color(0xFFFACC15) : Colors.white12,
                      width: equipped ? 2 : 1),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      height: 34,
                      child: CustomPaint(painter: _CuePainter(c)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                          Text(
                              locked
                                  ? 'Terbuka di Level ${c.level}'
                                  : c.desc,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white60)),
                        ],
                      ),
                    ),
                    btn,
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TableTab extends StatelessWidget {
  const _TableTab();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: kVenues.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
                'Skin meja otomatis menyesuaikan arena tempat kamu bermain.',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          );
        }
        final v = kVenues[i - 1];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1A33),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: v.accent.withAlpha(140)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 170,
                height: 94,
                child: CustomPaint(painter: _MiniTablePainter(v)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.skin.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Arena ${v.name} ${v.flag}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: v.accent)),
                    Text('Motif kain: ${kPatternNames[v.skin.pattern]}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white60)),
                    Text('Taruhan ${rp(v.fee)}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white60)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================
// ENGINE GAME
// ======================================================================
enum Phase { aiming, moving, placing, over }

class Ball {
  final int id;
  Offset p;
  Offset v = Offset.zero;
  bool pocketed = false;
  Ball(this.id, this.p);
  bool get stripe => id >= 9;
}

bool ownBall(int id, int g) => g == 0 ? (id >= 1 && id <= 7) : id >= 9;

class Plan {
  final double angle, power, score;
  Plan(this.angle, this.power, this.score);
}

class Ray {
  final Offset end;
  final int? hit;
  final Offset? objDir;
  final Offset? cueDir;
  Ray(this.end, this.hit, this.objDir, this.cueDir);
}

class Game extends ChangeNotifier {
  final Venue venue;
  final void Function(int winner) onEnd;
  final Random rnd = Random();

  late List<Ball> balls;
  int turn = 0; // 0 = kamu, 1 = AI
  List<int?> group = [null, null]; // 0 = solid, 1 = stripe
  Phase phase = Phase.aiming;
  double angle = 0, power = 0;
  String message = '';
  bool breakShot = true;
  bool aiHand = false;
  int? firstHit;
  List<int> potted = [];
  bool cuePotted = false;
  int? winner;
  Timer? _t;
  bool _disposed = false;
  Offset? _last;

  Game(this.venue, this.onEnd) {
    Mod.i.addListener(_onMod);
    reset();
  }

  @override
  void dispose() {
    _disposed = true;
    Mod.i.removeListener(_onMod);
    _t?.cancel();
    super.dispose();
  }

  // ---------------- setup ----------------
  void reset() {
    _t?.cancel();
    balls = [Ball(0, Offset(kW * 0.25, kH / 2))];
    final solids = <int>[1, 2, 3, 4, 5, 6, 7]..shuffle(rnd);
    final stripes = <int>[9, 10, 11, 12, 13, 14, 15]..shuffle(rnd);
    final slots = List<int>.filled(15, 0);
    slots[4] = 8;
    slots[10] = solids.removeLast();
    slots[14] = stripes.removeLast();
    final rest = <int>[...solids, ...stripes]..shuffle(rnd);
    var k = 0;
    for (var i = 0; i < 15; i++) {
      if (slots[i] == 0) slots[i] = rest[k++];
    }
    final apexX = kW * 0.72;
    final dx = kR * 2 * 0.866 + 0.3;
    final byId = <int, Ball>{};
    var idx = 0;
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c <= r; c++) {
        byId[slots[idx]] = Ball(slots[idx],
            Offset(apexX + r * dx, kH / 2 + (c - r / 2) * (kR * 2 + 0.3)));
        idx++;
      }
    }
    for (var id = 1; id <= 15; id++) {
      balls.add(byId[id]!);
    }
    turn = 0;
    group = [null, null];
    phase = Phase.aiming;
    angle = 0;
    power = 0;
    message = 'BREAK! Tarik power ke bawah lalu lepas';
    breakShot = true;
    aiHand = false;
    winner = null;
    firstHit = null;
    potted = [];
    cuePotted = false;
    if (Mod.i.autoplay) _scheduleAuto();
    notifyListeners();
  }

  // ---------------- kontrol manusia ----------------
  void setPower(double dp) {
    if (turn != 0 || phase != Phase.aiming) return;
    power = (power + dp).clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  void releasePower() {
    if (turn != 0 || phase != Phase.aiming) return;
    if (power > 0.04) {
      shoot(angle, power);
    } else {
      power = 0;
      notifyListeners();
    }
  }

  void panStart(Offset p) {
    _last = p;
    if (phase == Phase.placing && turn == 0) _place(p);
  }

  void panUpdate(Offset p) {
    if (turn != 0) return;
    if (phase == Phase.placing) {
      _place(p);
      return;
    }
    if (phase != Phase.aiming || _last == null) return;
    final c = balls[0].p;
    final v0 = _last! - c;
    final v1 = p - c;
    _last = p;
    if (v0.distance < 25 || v1.distance < 25) return;
    var d = atan2(v1.dy, v1.dx) - atan2(v0.dy, v0.dx);
    while (d > pi) {
      d -= 2 * pi;
    }
    while (d < -pi) {
      d += 2 * pi;
    }
    angle += d;
    notifyListeners();
  }

  void _place(Offset p) {
    final c = Offset(p.dx.clamp(kR, kW - kR).toDouble(),
        p.dy.clamp(kR, kH - kR).toDouble());
    if (_free(c, 0)) {
      balls[0].p = c;
      notifyListeners();
    }
  }

  void confirmPlace() {
    if (phase == Phase.placing) {
      phase = Phase.aiming;
      message = '';
      notifyListeners();
    }
  }

  bool _free(Offset p, int skipId) {
    if (p.dx < kR || p.dx > kW - kR || p.dy < kR || p.dy > kH - kR) {
      return false;
    }
    for (final b in balls) {
      if (b.pocketed || b.id == skipId) continue;
      if ((b.p - p).distance < 2 * kR + 0.5) return false;
    }
    return true;
  }

  Offset _findFree(Offset s, int skipId) {
    var p = s;
    for (var i = 0; i < 60; i++) {
      if (_free(p, skipId)) return p;
      p = Offset(s.dx + (i + 1) * kR * 0.8,
          s.dy + ((i % 2 == 0) ? 1 : -1) * (i % 7) * kR * 0.5);
    }
    return s;
  }

  // ---------------- tembak ----------------
  void shoot(double a, double p) {
    balls[0].v = Offset(cos(a), sin(a)) * (150 + p * 1850);
    angle = a;
    power = 0;
    firstHit = null;
    potted = [];
    cuePotted = false;
    message = '';
    phase = Phase.moving;
    notifyListeners();
  }

  // ---------------- fisika ----------------
  void step(double dt) {
    if (phase != Phase.moving) return;
    const sub = 10;
    final h = dt / sub;
    for (var i = 0; i < sub; i++) {
      _sim(h);
    }
    if (!balls.any((b) => !b.pocketed && b.v != Offset.zero)) {
      _resolve();
    }
    notifyListeners();
  }

  void _sim(double h) {
    for (final b in balls) {
      if (b.pocketed || b.v == Offset.zero) continue;
      final p = b.p + b.v * h;
      var v = b.v;
      final sp = v.distance;
      final ns = sp * exp(-0.9 * h) - 25 * h;
      v = ns <= 6 ? Offset.zero : v * (ns / sp);

      var inPocket = false;
      for (var i = 0; i < 6; i++) {
        if ((p - kPockets[i]).distance < pocketRadius(i)) {
          b.pocketed = true;
          b.v = Offset.zero;
          b.p = kPockets[i];
          if (b.id == 0) {
            cuePotted = true;
          } else {
            potted.add(b.id);
          }
          inPocket = true;
          break;
        }
      }
      if (inPocket) continue;

      var x = p.dx, y = p.dy, vx = v.dx, vy = v.dy;
      if (x < kR) {
        x = kR;
        vx = vx.abs() * 0.8;
      } else if (x > kW - kR) {
        x = kW - kR;
        vx = -vx.abs() * 0.8;
      }
      if (y < kR) {
        y = kR;
        vy = vy.abs() * 0.8;
      } else if (y > kH - kR) {
        y = kH - kR;
        vy = -vy.abs() * 0.8;
      }
      b.p = Offset(x, y);
      b.v = Offset(vx, vy);
    }

    for (var i = 0; i < balls.length; i++) {
      final a = balls[i];
      if (a.pocketed) continue;
      for (var j = i + 1; j < balls.length; j++) {
        final b = balls[j];
        if (b.pocketed) continue;
        final d = b.p - a.p;
        final dist = d.distance;
        if (dist >= 2 * kR || dist == 0) continue;
        final n = d / dist;
        final push = (2 * kR - dist) / 2;
        a.p -= n * push;
        b.p += n * push;
        final rvv = b.v - a.v;
        final rv = rvv.dx * n.dx + rvv.dy * n.dy;
        if (rv < 0) {
          final j2 = -(1 + 0.96) * rv / 2;
          a.v -= n * j2;
          b.v += n * j2;
          if (i == 0 && firstHit == null) firstHit = b.id;
        }
      }
    }
  }

  // ---------------- aturan 8-ball ----------------
  void _resolve() {
    final me = turn, opp = 1 - turn;
    final g = group[me];

    // bola 8 masuk saat break -> dikembalikan
    if (breakShot && potted.contains(8)) {
      potted.remove(8);
      final e = balls[8];
      e.pocketed = false;
      e.v = Offset.zero;
      e.p = _findFree(Offset(kW * 0.72, kH / 2), 8);
    }

    final remainingBefore = g == null
        ? 99
        : balls
            .where((b) =>
                b.id != 0 &&
                b.id != 8 &&
                ownBall(b.id, g) &&
                (!b.pocketed || potted.contains(b.id)))
            .length;
    final cleared = g != null && remainingBefore == 0;

    var foul = false;
    var reason = '';
    if (cuePotted) {
      foul = true;
      reason = 'Bola putih masuk';
    } else if (firstHit == null) {
      foul = true;
      reason = 'Tidak menyentuh bola';
    } else {
      final fh = firstHit!;
      if (g == null) {
        if (fh == 8) {
          foul = true;
          reason = 'Salah sasaran (bola 8)';
        }
      } else if (cleared) {
        if (fh != 8) {
          foul = true;
          reason = 'Harus kena bola 8';
        }
      } else if (!ownBall(fh, g)) {
        foul = true;
        reason = 'Salah sasaran';
      }
    }

    // bola 8 masuk
    if (potted.contains(8)) {
      winner = (!foul && cleared) ? me : opp;
      phase = Phase.over;
      message = winner == 0 ? 'Kamu menang!' : 'Lawan menang';
      notifyListeners();
      onEnd(winner!);
      return;
    }

    // tentukan grup
    if (g == null && !foul) {
      for (final id in potted) {
        if (id != 8) {
          final grp = id <= 7 ? 0 : 1;
          group[me] = grp;
          group[opp] = 1 - grp;
          break;
        }
      }
    }
    final gg = group[me];
    final keep = !foul && gg != null && potted.any((id) => ownBall(id, gg));

    breakShot = false;
    aiHand = false;
    if (foul) {
      turn = opp;
      balls[0].v = Offset.zero;
      if (cuePotted) {
        balls[0].pocketed = false;
        balls[0].p = _findFree(Offset(kW * 0.25, kH / 2), 0);
      }
      if (turn == 0) {
        phase = Phase.placing;
      } else {
        phase = Phase.aiming;
        aiHand = true;
      }
    } else {
      if (!keep) turn = opp;
      phase = Phase.aiming;
    }
    message = '${foul ? 'FOUL! $reason. ' : ''}'
        '${turn == 0 ? 'Giliranmu${phase == Phase.placing ? ' - letakkan bola putih' : ''}' : 'Giliran lawan'}';
    power = 0;
    if (turn == 1) {
      _scheduleAI();
    } else if (Mod.i.autoplay) {
      _scheduleAuto();
    }
  }

  // ---------------- AI ----------------
  void _scheduleAI() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1100), _aiPlay);
  }

  void _aiPlay() {
    if (_disposed || phase != Phase.aiming || turn != 1) return;
    if (aiHand) {
      _aiPlace();
      aiHand = false;
    }
    final plan = _plan(balls[0].p);
    angle = plan.angle;
    power = plan.power;
    notifyListeners();
    _t = Timer(const Duration(milliseconds: 900), () {
      if (_disposed || phase != Phase.aiming || turn != 1) return;
      final a = angle + (rnd.nextDouble() - 0.5) * 2 * venue.aiError;
      final p = power;
      shoot(a, p);
    });
  }

  void _aiPlace([int who = 1]) {
    final cands = <Offset>[balls[0].p];
    for (var i = 0; i < 16; i++) {
      cands.add(Offset(kR + rnd.nextDouble() * (kW - 2 * kR),
          kR + rnd.nextDouble() * (kH - 2 * kR)));
    }
    var bs = double.infinity;
    var bp = balls[0].p;
    for (final c in cands) {
      if (!_free(c, 0)) continue;
      final s = _plan(c, who).score;
      if (s < bs) {
        bs = s;
        bp = c;
      }
    }
    balls[0].p = bp;
  }

  bool _segClear(Offset a, Offset b, Set<int> ignore) {
    for (final ball in balls) {
      if (ball.pocketed || ignore.contains(ball.id)) continue;
      if (_distSeg(ball.p, a, b) < 2 * kR - 1) return false;
    }
    return true;
  }

  double _distSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / l2;
    t = t.clamp(0.0, 1.0).toDouble();
    return (p - (a + ab * t)).distance;
  }

  Plan _plan(Offset cue, [int who = 1]) {
    final g = group[who];
    final cleared = g != null &&
        !balls.any((b) =>
            b.id != 0 && b.id != 8 && !b.pocketed && ownBall(b.id, g));
    bool legal(int id) =>
        g == null ? id != 8 : (cleared ? id == 8 : ownBall(id, g));
    final targets =
        balls.where((b) => b.id != 0 && !b.pocketed && legal(b.id)).toList();

    Plan? best;
    for (final t in targets) {
      for (var i = 0; i < 6; i++) {
        final pk = kPockets[i];
        final tp = pk - t.p;
        final tpd = tp.distance;
        if (tpd < 1) continue;
        final dirTP = tp / tpd;
        final ghost = t.p - dirTP * (2 * kR);
        if (ghost.dx < kR ||
            ghost.dx > kW - kR ||
            ghost.dy < kR ||
            ghost.dy > kH - kR) {
          continue;
        }
        final cg = ghost - cue;
        final cgd = cg.distance;
        if (cgd < 2) continue;
        final dirCG = cg / cgd;
        final cosCut = dirCG.dx * dirTP.dx + dirCG.dy * dirTP.dy;
        if (cosCut < 0.35) continue;
        if (!_segClear(cue, ghost, {0, t.id})) continue;
        if (!_segClear(t.p, pk, {0, t.id})) continue;
        final score = cgd + tpd * 1.2 + (1 - cosCut) * 400;
        if (best == null || score < best.score) {
          best = Plan(atan2(cg.dy, cg.dx),
              (0.3 + (cgd + tpd) / 900).clamp(0.3, 0.95).toDouble(), score);
        }
      }
    }
    if (who == 0 && Mod.i.autoBounce && best == null) {
      best = _bankPlan(cue, targets);
    }
    if (best != null) return best;

    Ball? near;
    var nd = double.infinity;
    for (final t in targets) {
      final d = (t.p - cue).distance;
      if (d < nd) {
        nd = d;
        near = t;
      }
    }
    if (near == null) return Plan(0, 0.5, 1e9);
    final v = near.p - cue;
    return Plan(atan2(v.dy, v.dx), 0.55, 1e6 + nd);
  }

  // ---------------- MOD: autoplay ----------------
  void _onMod() {
    if (_disposed) return;
    if (turn == 0 && (phase == Phase.aiming || phase == Phase.placing)) {
      if (Mod.i.autoplay) {
        _scheduleAuto();
      } else {
        _t?.cancel();
      }
    }
    notifyListeners();
  }

  void _scheduleAuto() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 900), _autoPlay);
  }

  void _autoPlay() {
    if (_disposed || !Mod.i.autoplay || turn != 0 || winner != null) return;
    if (phase == Phase.placing) {
      _aiPlace(0);
      phase = Phase.aiming;
      message = '';
      notifyListeners();
    }
    if (phase != Phase.aiming) return;
    final Plan plan;
    if (breakShot) {
      final c = balls[0].p;
      final tgt = Offset(kW * 0.72, kH / 2) - c;
      plan = Plan(atan2(tgt.dy, tgt.dx), 1.0, 0);
    } else {
      plan = _plan(balls[0].p, 0);
    }
    angle = plan.angle;
    power = plan.power;
    notifyListeners();
    _t = Timer(const Duration(milliseconds: 800), () {
      if (_disposed ||
          !Mod.i.autoplay ||
          turn != 0 ||
          phase != Phase.aiming) {
        return;
      }
      shoot(plan.angle, plan.power);
    });
  }

  // ---------------- MOD: bank shot (pantulan) ----------------
  bool _inb(Offset g) =>
      g.dx >= kR && g.dx <= kW - kR && g.dy >= kR && g.dy <= kH - kR;

  // cermin titik p terhadap dinding w (0 kiri, 1 kanan, 2 atas, 3 bawah)
  Offset _mirror(Offset p, int w) {
    switch (w) {
      case 0:
        return Offset(2 * kR - p.dx, p.dy);
      case 1:
        return Offset(2 * (kW - kR) - p.dx, p.dy);
      case 2:
        return Offset(p.dx, 2 * kR - p.dy);
      default:
        return Offset(p.dx, 2 * (kH - kR) - p.dy);
    }
  }

  // titik pantul garis a -> bm (bm sudah dicermin) di dinding w
  Offset? _wallHit(Offset a, Offset bm, int w) {
    final vertical = w < 2;
    final wall = w == 0
        ? kR
        : w == 1
            ? kW - kR
            : w == 2
                ? kR
                : kH - kR;
    final da = vertical ? bm.dx - a.dx : bm.dy - a.dy;
    if (da.abs() < 1e-6) return null;
    final t = (wall - (vertical ? a.dx : a.dy)) / da;
    if (t <= 0.02 || t >= 0.98) return null;
    final h = a + (bm - a) * t;
    if (vertical) {
      if (h.dy < kR || h.dy > kH - kR) return null;
    } else {
      if (h.dx < kR || h.dx > kW - kR) return null;
    }
    return h;
  }

  Plan? _bankPlan(Offset cue, List<Ball> targets) {
    Plan? best;
    for (final t in targets) {
      for (var i = 0; i < 6; i++) {
        final pk = kPockets[i];

        // 1) bola target memantul satu kali lalu masuk lubang
        for (var w = 0; w < 4; w++) {
          final h = _wallHit(t.p, _mirror(pk, w), w);
          if (h == null) continue;
          final th = h - t.p;
          final dirTP = th / th.distance;
          final ghost = t.p - dirTP * (2 * kR);
          if (!_inb(ghost)) continue;
          final cg = ghost - cue;
          final cgd = cg.distance;
          if (cgd < 2) continue;
          final cosCut = (cg.dx * dirTP.dx + cg.dy * dirTP.dy) / cgd;
          if (cosCut < 0.5) continue;
          if (!_segClear(cue, ghost, {0, t.id})) continue;
          if (!_segClear(t.p, h, {0, t.id})) continue;
          if (!_segClear(h, pk, {0, t.id})) continue;
          final path = th.distance + (pk - h).distance;
          final score = cgd + path * 1.5 + (1 - cosCut) * 400 + 150;
          if (best == null || score < best.score) {
            best = Plan(atan2(cg.dy, cg.dx),
                (0.45 + (cgd + path) / 800).clamp(0.45, 1.0).toDouble(), score);
          }
        }

        // 2) bola putih memantul dulu, baru kena target ke lubang
        final tp = pk - t.p;
        final tpd = tp.distance;
        if (tpd < 1) continue;
        final dirTP2 = tp / tpd;
        final ghost2 = t.p - dirTP2 * (2 * kR);
        if (!_inb(ghost2)) continue;
        if (!_segClear(t.p, pk, {0, t.id})) continue;
        for (var w = 0; w < 4; w++) {
          final gm = _mirror(ghost2, w);
          final h = _wallHit(cue, gm, w);
          if (h == null) continue;
          final last = ghost2 - h;
          final ld = last.distance;
          if (ld < 2) continue;
          final cosCut = (last.dx * dirTP2.dx + last.dy * dirTP2.dy) / ld;
          if (cosCut < 0.4) continue;
          if (!_segClear(cue, h, {0})) continue;
          if (!_segClear(h, ghost2, {0, t.id})) continue;
          final run = (h - cue).distance + ld;
          final score = run * 1.3 + tpd * 1.2 + (1 - cosCut) * 400 + 200;
          if (best == null || score < best.score) {
            best = Plan(atan2(gm.dy - cue.dy, gm.dx - cue.dx),
                (0.5 + (run + tpd) / 800).clamp(0.5, 1.0).toDouble(), score);
          }
        }
      }
    }
    return best;
  }

  // ---------------- garis bidik ----------------
  Ray rayCast() {
    final c = balls[0].p;
    final d = Offset(cos(angle), sin(angle));
    var tMin = double.infinity;
    int? hit;
    if (d.dx > 1e-9) {
      tMin = min(tMin, (kW - kR - c.dx) / d.dx);
    } else if (d.dx < -1e-9) {
      tMin = min(tMin, (kR - c.dx) / d.dx);
    }
    if (d.dy > 1e-9) {
      tMin = min(tMin, (kH - kR - c.dy) / d.dy);
    } else if (d.dy < -1e-9) {
      tMin = min(tMin, (kR - c.dy) / d.dy);
    }
    for (final b in balls) {
      if (b.id == 0 || b.pocketed) continue;
      final f = c - b.p;
      final bq = f.dx * d.dx + f.dy * d.dy;
      final cq = f.dx * f.dx + f.dy * f.dy - 4 * kR * kR;
      final disc = bq * bq - cq;
      if (disc < 0) continue;
      final t = -bq - sqrt(disc);
      if (t > 0 && t < tMin) {
        tMin = t;
        hit = b.id;
      }
    }
    final end = c + d * tMin;
    if (hit == null) return Ray(end, null, null, null);
    final n = balls[hit].p - end;
    final nn = n / n.distance;
    final dot = d.dx * nn.dx + d.dy * nn.dy;
    final cd = d - nn * dot;
    return Ray(end, hit, nn, cd.distance > 1e-6 ? cd : null);
  }
}

// ======================================================================
// PAINTER MEJA
// ======================================================================
class TableXf {
  final double s, ox, oy;
  const TableXf(this.s, this.ox, this.oy);
  factory TableXf.of(Size z) {
    final s = min(z.width / (kW + 2 * kRail), z.height / (kH + 2 * kRail));
    return TableXf(s, (z.width - (kW + 2 * kRail) * s) / 2,
        (z.height - (kH + 2 * kRail) * s) / 2);
  }
  Offset toTable(Offset l) =>
      Offset((l.dx - ox) / s - kRail, (l.dy - oy) / s - kRail);
}

// Gambar dasar meja (kayu, kain, motif, lubang) sesuai skin arena.
// Koordinat: titik (0,0) = pojok kiri-atas area main.
final Map<String, TextPainter> _watermarks = {};
TextPainter _watermark(Venue v) => _watermarks.putIfAbsent(v.name, () {
      final t = TextPainter(
        text: TextSpan(
            text: v.name.toUpperCase(),
            style: TextStyle(
                color: Colors.white.withAlpha(26),
                fontSize: 46,
                fontWeight: FontWeight.w900,
                letterSpacing: 8)),
        textDirection: TextDirection.ltr,
      );
      t.layout();
      return t;
    });

void _sparkle(Canvas c, Offset o, double r, Paint p) {
  final path = Path()
    ..moveTo(o.dx, o.dy - r)
    ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
    ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
    ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
    ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
    ..close();
  c.drawPath(path, p);
}

void _tablePattern(Canvas c, int pattern) {
  if (pattern == 0) return;
  final line = Paint()
    ..color = Colors.white.withAlpha(16)
    ..strokeWidth = 1.4
    ..style = PaintingStyle.stroke;
  final fill = Paint()..color = Colors.white.withAlpha(22);
  switch (pattern) {
    case 1:
      for (var x = 20.0; x < kW; x += 40) {
        c.drawLine(Offset(x, 0), Offset(x, kH), line);
      }
      break;
    case 2:
      for (var k = -kH; k < kW; k += 50) {
        c.drawLine(Offset(k, 0), Offset(k + kH, kH), line);
        c.drawLine(Offset(k + kH, 0), Offset(k, kH), line);
      }
      break;
    case 3:
      for (var j = 0; j < 4; j++) {
        for (var i = 0; i < 7; i++) {
          final x = 60.0 + i * 120 + (j.isOdd ? 60 : 0);
          final y = 50.0 + j * 100;
          if (x > kW - 20) continue;
          _sparkle(c, Offset(x, y), 9, fill);
        }
      }
      break;
    case 4:
      for (var r = 60.0; r <= 300; r += 60) {
        c.drawCircle(Offset(kW / 2, kH / 2), r, line);
      }
      break;
    case 5:
      for (var k = -kH; k < kW; k += 36) {
        c.drawLine(Offset(k, kH), Offset(k + kH, 0), line);
      }
      break;
  }
}

void drawTableBase(Canvas c, Venue v, {bool watermark = true}) {
  final sk = v.skin;

  // kayu
  final outer = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-kRail, -kRail, kW + 2 * kRail, kH + 2 * kRail),
      const Radius.circular(30));
  c.drawRRect(
      outer.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black54
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
  c.drawRRect(
      outer,
      Paint()
        ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sk.railTop, sk.railBottom]).createShader(outer.outerRect));
  c.drawRRect(
      outer.deflate(4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = sk.trim.withAlpha(200));

  // titik bidik (diamond) di kayu
  final sightPaint = Paint()..color = sk.sight.withAlpha(215);
  void dia(Offset o) {
    const r = 3.4;
    c.drawPath(
        Path()
          ..moveTo(o.dx, o.dy - r)
          ..lineTo(o.dx + r, o.dy)
          ..lineTo(o.dx, o.dy + r)
          ..lineTo(o.dx - r, o.dy)
          ..close(),
        sightPaint);
  }

  for (var i = 1; i < 8; i++) {
    if (i == 4) continue;
    final x = kW * i / 8;
    dia(Offset(x, -kRail / 2));
    dia(Offset(x, kH + kRail / 2));
  }
  for (var i = 1; i < 4; i++) {
    final y = kH * i / 4;
    dia(Offset(-kRail / 2, y));
    dia(Offset(kW + kRail / 2, y));
  }

  // bantalan + kain
  c.drawRect(const Rect.fromLTWH(-14, -14, kW + 28, kH + 28),
      Paint()..color = Color.lerp(v.felt, Colors.black, 0.35)!);
  const feltRect = Rect.fromLTWH(0, 0, kW, kH);
  c.drawRect(
      feltRect,
      Paint()
        ..shader = RadialGradient(radius: 0.9, colors: [
          Color.lerp(v.felt, Colors.white, 0.14)!,
          v.felt,
          Color.lerp(v.felt, Colors.black, 0.25)!
        ]).createShader(feltRect));

  // motif kain + nama arena
  c.save();
  c.clipRect(feltRect);
  _tablePattern(c, sk.pattern);
  if (watermark) {
    final t = _watermark(v);
    t.paint(c, Offset((kW - t.width) / 2, (kH - t.height) / 2));
  }
  c.restore();

  // lubang
  for (var i = 0; i < 6; i++) {
    c.drawCircle(kPockets[i], pocketRadius(i) + 4,
        Paint()..color = Color.lerp(sk.railBottom, Colors.black, 0.6)!);
    c.drawCircle(
        kPockets[i], pocketRadius(i) - 1, Paint()..color = Colors.black);
  }

  // garis & titik
  final faint = Paint()
    ..color = Colors.white.withAlpha(45)
    ..strokeWidth = 1.2;
  c.drawLine(Offset(kW * 0.25, 6), Offset(kW * 0.25, kH - 6), faint);
  c.drawCircle(Offset(kW * 0.25, kH / 2), 2.5, faint);
  c.drawCircle(Offset(kW * 0.72, kH / 2), 2.5, faint);
}

// Pratinjau meja kecil (untuk lobi & koleksi).
class _MiniTablePainter extends CustomPainter {
  final Venue v;
  _MiniTablePainter(this.v);

  @override
  void paint(Canvas c, Size size) {
    final s = min(size.width / (kW + 2 * kRail), size.height / (kH + 2 * kRail));
    if (s <= 0) return;
    c.translate((size.width - (kW + 2 * kRail) * s) / 2,
        (size.height - (kH + 2 * kRail) * s) / 2);
    c.scale(s);
    c.translate(kRail, kRail);
    drawTableBase(c, v);
  }

  @override
  bool shouldRepaint(covariant _MiniTablePainter old) => old.v != v;
}

class TablePainter extends CustomPainter {
  final Game g;
  TablePainter(this.g) : super(repaint: g);

  static final Map<int, TextPainter> _tps = {};
  TextPainter _tp(int id) => _tps.putIfAbsent(id, () {
        final t = TextPainter(
          text: TextSpan(
              text: '$id',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: kR * 0.62,
                  fontWeight: FontWeight.w900)),
          textDirection: TextDirection.ltr,
        );
        t.layout();
        return t;
      });

  @override
  void paint(Canvas c, Size size) {
    final xf = TableXf.of(size);
    c.save();
    c.translate(xf.ox, xf.oy);
    c.scale(xf.s);
    c.translate(kRail, kRail);
    final v = g.venue;

    drawTableBase(c, v);

    // garis bidik (di bawah bola)
    final aiming = g.phase == Phase.aiming;
    if (aiming && g.turn == 0) _guide(c);

    // bola
    for (final b in g.balls) {
      if (!b.pocketed && b.id != 0) _ball(c, b);
    }
    final cue = g.balls[0];
    if (!cue.pocketed) {
      _ball(c, cue);
      if (g.phase == Phase.placing) {
        c.drawCircle(
            cue.p,
            kR + 5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.white.withAlpha(220));
      }
    }

    if (aiming) _stick(c);
    c.restore();
  }

  // garis lurus yang memantul di bantalan
  void _trace(Canvas c, Offset s, Offset d, double len, Paint p, int bounces) {
    var pos = s;
    var dir = d;
    var left = len;
    for (var i = 0; i <= bounces && left > 0; i++) {
      final tx = dir.dx > 1e-9
          ? (kW - kR - pos.dx) / dir.dx
          : dir.dx < -1e-9
              ? (kR - pos.dx) / dir.dx
              : double.infinity;
      final ty = dir.dy > 1e-9
          ? (kH - kR - pos.dy) / dir.dy
          : dir.dy < -1e-9
              ? (kR - pos.dy) / dir.dy
              : double.infinity;
      final t = max(0.0, min(tx, ty));
      final seg = min(t, left);
      final end = pos + dir * seg;
      c.drawLine(pos, end, p);
      left -= seg;
      if (seg < t) break;
      dir = tx <= ty ? Offset(-dir.dx, dir.dy) : Offset(dir.dx, -dir.dy);
      pos = end;
    }
  }

  void _guide(Canvas c) {
    final r = g.rayCast();
    final cue = g.balls[0].p;
    final d = Offset(cos(g.angle), sin(g.angle));
    final long = Mod.i.longLine;
    final line = Paint()
      ..color = Colors.white.withAlpha(210)
      ..strokeWidth = 1.6;
    final soft = Paint()
      ..color = Colors.white.withAlpha(110)
      ..strokeWidth = 1.4;
    if (long && r.hit == null) {
      _trace(c, cue + d * kR, d, 1600, line, 3);
    } else {
      c.drawLine(cue + d * kR, r.end, line);
    }
    c.drawCircle(
        r.end,
        kR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withAlpha(220));
    if (r.hit != null) {
      final b = g.balls[r.hit!].p;
      if (long) {
        _trace(c, b, r.objDir!, 520, line, 2);
      } else {
        c.drawLine(b, b + r.objDir! * 70, line);
      }
      final cd = r.cueDir;
      if (cd != null) {
        if (long) {
          _trace(c, r.end, cd / cd.distance, 300, soft, 1);
        } else {
          c.drawLine(r.end, r.end + cd * 55, soft);
        }
      }
    }
  }

  void _stick(Canvas c) {
    final cue = g.balls[0].p;
    final dir = Offset(cos(g.angle), sin(g.angle));
    final pull = 14 + g.power * 90;
    final tip = cue - dir * (kR + pull);
    drawCue(c, g.turn == 0 ? ProfileStore.i.cue : kCues.first, tip, dir);
  }

  void _ball(Canvas c, Ball b) {
    final p = b.p;
    final rect = Rect.fromCircle(center: p, radius: kR);
    final color = kBallColors[b.id];
    c.drawCircle(p + const Offset(2, 3), kR,
        Paint()..color = Colors.black.withAlpha(90));

    final light = Color.lerp(color, Colors.white, 0.55)!;
    final dark = Color.lerp(color, Colors.black, 0.5)!;
    if (b.stripe) {
      c.drawCircle(
          p,
          kR,
          Paint()
            ..shader = const RadialGradient(
                center: Alignment(-0.35, -0.4),
                radius: 1,
                colors: [
                  Colors.white,
                  Color(0xFFE6E6E6),
                  Color(0xFF9A9A9A)
                ],
                stops: [0, 0.55, 1]).createShader(rect));
      c.save();
      c.clipPath(Path()..addOval(rect));
      c.drawRect(
          Rect.fromLTWH(p.dx - kR, p.dy - kR * 0.58, kR * 2, kR * 1.16),
          Paint()
            ..shader = RadialGradient(
                center: const Alignment(-0.35, -0.2),
                radius: 1.2,
                colors: [light, color, dark]).createShader(rect));
      c.restore();
    } else {
      c.drawCircle(
          p,
          kR,
          Paint()
            ..shader = RadialGradient(
                center: const Alignment(-0.35, -0.4),
                radius: 1,
                colors: [light, color, dark],
                stops: const [0, 0.55, 1]).createShader(rect));
    }
    if (b.id != 0) {
      c.drawCircle(p, kR * 0.46, Paint()..color = Colors.white);
      final t = _tp(b.id);
      t.paint(c, p - Offset(t.width / 2, t.height / 2));
    }
    c.drawCircle(p + Offset(-kR * 0.35, -kR * 0.4), kR * 0.2,
        Paint()..color = Colors.white.withAlpha(150));
  }

  @override
  bool shouldRepaint(covariant TablePainter old) => true;
}

// ======================================================================
// POWER SLIDER
// ======================================================================
class PowerBar extends StatelessWidget {
  final double value;
  final bool enabled;
  final Color accent;
  final ValueChanged<double> onDelta;
  final VoidCallback onRelease;
  const PowerBar(
      {super.key,
      required this.value,
      required this.enabled,
      required this.accent,
      required this.onDelta,
      required this.onRelease});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final h = box.maxHeight;
      return Opacity(
        opacity: enabled ? 1 : 0.45,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate:
              enabled ? (d) => onDelta(d.delta.dy / (h - 30)) : null,
          onVerticalDragEnd: enabled ? (_) => onRelease() : null,
          onVerticalDragCancel: enabled ? onRelease : null,
          child: CustomPaint(
              size: Size(box.maxWidth, h),
              painter: _PowerPainter(value, accent)),
        ),
      );
    });
  }
}

class _PowerPainter extends CustomPainter {
  final double v;
  final Color accent;
  _PowerPainter(this.v, this.accent);

  @override
  void paint(Canvas c, Size s) {
    final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width / 2 - 11, 0, 22, s.height),
        const Radius.circular(11));
    c.drawRRect(track, Paint()..color = Colors.black54);
    c.save();
    c.clipRRect(track);
    final fillH = 15 + v * (s.height - 30);
    c.drawRect(
        Rect.fromLTWH(s.width / 2 - 11, 0, 22, fillH),
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Color(0xFF22C55E),
                Color(0xFFFACC15),
                Color(0xFFEF4444)
              ]).createShader(Rect.fromLTWH(0, 0, s.width, s.height)));
    c.restore();
    c.drawRRect(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white30);
    final hy = 15 + v * (s.height - 30);
    c.drawCircle(Offset(s.width / 2, hy), 14, Paint()..color = Colors.white);
    c.drawCircle(
        Offset(s.width / 2, hy),
        14,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = accent);
  }

  @override
  bool shouldRepaint(covariant _PowerPainter o) => o.v != v;
}

// ======================================================================
// LAYAR GAME
// ======================================================================
class GameScreen extends StatefulWidget {
  final Venue venue;
  const GameScreen({super.key, required this.venue});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final Game game;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    game = Game(widget.venue, _onEnd);
    _ticker = createTicker((e) {
      final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
      _last = e;
      game.step(dt.toDouble());
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    game.dispose();
    super.dispose();
  }

  Future<void> _onEnd(int w) async {
    final fee = widget.venue.fee;
    if (w == 0) Wallet.add(fee * 2);
    final up = await ProfileStore.i.record(w == 0);
    if (!mounted) return;
    final xpGain = w == 0 ? ProfileStore.xpWin : ProfileStore.xpLose;
    final lvl = up ? '\nNaik ke Level ${ProfileStore.i.level}! 🎉' : '';
    if (Mod.i.autoQueue && Wallet.coins.value >= fee) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1400),
        content: Text(
            '${w == 0 ? 'Menang' : 'Kalah'} - queue otomatis... Saldo ${rp(Wallet.coins.value)}'),
      ));
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      if (Mod.i.autoQueue && Wallet.coins.value >= fee) {
        await Wallet.add(-fee);
        game.reset();
        return;
      }
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1A33),
        title: Text(w == 0 ? 'MENANG! 🏆' : 'KALAH 😢',
            textAlign: TextAlign.center),
        content: Text(
          w == 0
              ? 'Hadiah ${rp(fee * 2)}\n(untung ${rp(fee)})\n\nSaldo: ${rp(Wallet.coins.value)}\n+$xpGain XP$lvl'
              : 'Taruhan ${rp(fee)} hangus.\n\nSaldo: ${rp(Wallet.coins.value)}\n+$xpGain XP$lvl',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dctx);
              Navigator.pop(context);
            },
            child: const Text('Lobi'),
          ),
          FilledButton(
            onPressed: Wallet.coins.value >= fee
                ? () async {
                    Navigator.pop(dctx);
                    await Wallet.add(-fee);
                    game.reset();
                  }
                : null,
            child: Text('Main lagi (${rp(fee)})'),
          ),
        ],
      ),
    );
  }

  void _confirmExit() {
    if (game.phase == Phase.over) {
      Navigator.pop(context);
      return;
    }
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1A33),
        title: const Text('Keluar dari meja?'),
        content: Text('Taruhan ${rp(widget.venue.fee)} akan hangus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Lanjut main')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dctx);
              Navigator.pop(context);
            },
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  Widget _dots(int? grp) {
    if (grp == null) {
      return const Text('Meja terbuka',
          style: TextStyle(fontSize: 10, color: Colors.white60));
    }
    final ids = grp == 0
        ? <int>[1, 2, 3, 4, 5, 6, 7]
        : <int>[9, 10, 11, 12, 13, 14, 15];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final id in [...ids, 8])
          Container(
            margin: const EdgeInsets.only(right: 2),
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: game.balls[id].pocketed
                  ? Colors.white12
                  : kBallColors[id],
              border: id >= 9
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _chip(int idx) {
    final v = widget.venue;
    final active = game.turn == idx && game.phase != Phase.over;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: active ? v.accent : Colors.white24, width: active ? 2 : 1),
        boxShadow: active
            ? [BoxShadow(color: v.accent.withAlpha(120), blurRadius: 12)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(idx == 0 ? kAvatars[ProfileStore.i.avatar] : v.flag,
              style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 84),
                child: Text(
                    idx == 0
                        ? (ProfileStore.i.isNew ? 'Kamu' : ProfileStore.i.name)
                        : v.ai,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              _dots(game.group[idx]),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.venue;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.2,
              colors: [
                Color.lerp(v.felt, Colors.black, 0.75)!,
                const Color(0xFF03060F)
              ],
            ),
          ),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: game,
              builder: (ctx, _) {
                final canAim = game.turn == 0 && game.phase == Phase.aiming;
                return Stack(
                  children: [
                    // meja
                    Positioned(
                      left: 76,
                      right: 8,
                      top: 52,
                      bottom: 4,
                      child: LayoutBuilder(builder: (c, box) {
                        final size = box.biggest;
                        final xf = TableXf.of(size);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (d) =>
                              game.panStart(xf.toTable(d.localPosition)),
                          onPanUpdate: (d) =>
                              game.panUpdate(xf.toTable(d.localPosition)),
                          child: CustomPaint(
                              size: size, painter: TablePainter(game)),
                        );
                      }),
                    ),
                    // power slider
                    Positioned(
                      left: 10,
                      top: 56,
                      bottom: 10,
                      width: 56,
                      child: PowerBar(
                        value: game.power,
                        enabled: canAim,
                        accent: v.accent,
                        onDelta: game.setPower,
                        onRelease: game.releasePower,
                      ),
                    ),
                    // top bar
                    Positioned(
                      top: 2,
                      left: 4,
                      right: 8,
                      height: 48,
                      child: Row(
                        children: [
                          IconButton(
                              onPressed: _confirmExit,
                              icon: const Icon(Icons.arrow_back_ios_new)),
                          _chip(0),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${v.flag} ${v.name.toUpperCase()}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 1.5,
                                        color: Colors.white70)),
                                Text(rp(v.fee * 2),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFFACC15))),
                              ],
                            ),
                          ),
                          _chip(1),
                        ],
                      ),
                    ),
                    // pesan
                    if (game.message.isNotEmpty)
                      Positioned(
                        top: 54,
                        left: 80,
                        right: 12,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(170),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: v.accent.withAlpha(180)),
                            ),
                            child: Text(game.message,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    // tombol letakkan bola
                    if (game.phase == Phase.placing && game.turn == 0)
                      Positioned(
                        right: 20,
                        bottom: 14,
                        child: FilledButton.icon(
                          onPressed: game.confirmPlace,
                          icon: const Icon(Icons.check),
                          label: const Text('Letakkan bola'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
