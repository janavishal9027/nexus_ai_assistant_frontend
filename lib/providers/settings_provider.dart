import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

/// Chat density — how much air sits between messages.
enum ChatDensity { comfortable, compact }

/// A chat background. Built-ins are gradients so they cost no assets and look
/// right in both light and dark; `custom` is an image the user picked.
///
/// Each built-in is half of a *colour theme*: it has a matching accent (see
/// [SettingsProvider.accentFor]) that is applied with it, so bubbles never end
/// up teal on a blue background.
enum Wallpaper { none, dusk, forest, ocean, ember, rose, mono, custom }

/// Appearance settings (Settings → Personalization).
///
/// **Local-first.** [load] is awaited before `runApp`, so the very first frame
/// is already the user's theme — no flash of the wrong colours. Every setter
/// writes SharedPreferences immediately and pushes to the backend in the
/// background; a sync failure is swallowed, because a network blip must never
/// change how the app looks.
///
/// The backend copy exists only so a second device matches. [syncFromServer] is
/// called after login and adopts the server's values wholesale — last write
/// wins, which is the right trade for a text-size slider.
class SettingsProvider extends ChangeNotifier {
  // ── Defaults. Must match backend routes/appearance.py::DEFAULTS. ──────────
  static const Color defaultAccent = Color(0xFF10A37F);
  static const double minTextSize = 11, maxTextSize = 24, defaultTextSize = 15;
  static const double minRadius = 0, maxRadius = 28, defaultRadius = 16;

  /// The accent swatches offered in the picker. The first is the brand teal.
  /// Every accent a wallpaper pairs with must appear here, or selecting that
  /// theme would leave the picker showing nothing as chosen.
  static const List<Color> accentChoices = [
    Color(0xFF10A37F), // teal (default) — none, forest
    Color(0xFF3B82F6), // blue           — ocean
    Color(0xFF8B5CF6), // violet         — dusk
    Color(0xFFEC4899), // pink           — rose
    Color(0xFFF59E0B), // amber          — ember
    Color(0xFF64748B), // slate          — mono
    Color(0xFFEF4444), // red
    Color(0xFF14B8A6), // cyan
  ];

  /// The accent that belongs with a wallpaper — the other half of the colour
  /// theme. Choosing a wallpaper applies this, so the bubbles agree with the
  /// background instead of fighting it (teal bubbles on the blue Ocean
  /// background was the tell). The accent picker still overrides it afterwards.
  ///
  /// `custom` returns null: an arbitrary photo has no knowable matching hue, so
  /// whatever accent the user already had is kept.
  static Color? accentFor(Wallpaper w) => switch (w) {
        Wallpaper.none => defaultAccent,
        Wallpaper.dusk => const Color(0xFF8B5CF6),   // violet
        Wallpaper.forest => defaultAccent,           // teal
        Wallpaper.ocean => const Color(0xFF3B82F6),  // blue
        Wallpaper.ember => const Color(0xFFF59E0B),  // amber
        Wallpaper.rose => const Color(0xFFEC4899),   // pink
        Wallpaper.mono => const Color(0xFF64748B),   // slate
        Wallpaper.custom => null,
      };

  static const _kThemeMode = 'appearance_theme_mode';
  static const _kAccent = 'appearance_accent';
  static const _kTextSize = 'appearance_text_size';
  static const _kRadius = 'appearance_corner_radius';
  static const _kDensity = 'appearance_density';
  static const _kReduceAnim = 'appearance_reduce_animations';
  static const _kWallpaper = 'appearance_wallpaper';
  static const _kWallpaperPath = 'appearance_wallpaper_path';

  ThemeMode _themeMode = ThemeMode.dark;
  Color _accent = defaultAccent;
  double _textSize = defaultTextSize;
  double _cornerRadius = defaultRadius;
  ChatDensity _density = ChatDensity.comfortable;
  bool _reduceAnimations = false;
  Wallpaper _wallpaper = Wallpaper.none;
  String? _wallpaperPath; // device-local; never synced (see syncFromServer)

  ThemeMode get themeMode => _themeMode;
  Color get accent => _accent;
  double get textSize => _textSize;
  double get cornerRadius => _cornerRadius;
  ChatDensity get density => _density;
  bool get reduceAnimations => _reduceAnimations;
  Wallpaper get wallpaper => _wallpaper;
  String? get wallpaperPath => _wallpaperPath;

  /// Vertical gap between message bubbles.
  double get messageGap => _density == ChatDensity.compact ? 2 : 6;

  /// Duration helper — collapses to zero when the user asked for less motion,
  /// so callers don't each need to branch.
  Duration motion(Duration d) => _reduceAnimations ? Duration.zero : d;

  bool get hasWallpaper =>
      _wallpaper != Wallpaper.none &&
      !(_wallpaper == Wallpaper.custom && (_wallpaperPath ?? '').isEmpty);

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Read the saved settings. Awaited before runApp so the first frame is right.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _themeMode = _themeModeFrom(p.getString(_kThemeMode));
      final a = p.getInt(_kAccent);
      if (a != null) _accent = Color(a);
      _textSize = (p.getDouble(_kTextSize) ?? defaultTextSize)
          .clamp(minTextSize, maxTextSize);
      _cornerRadius =
          (p.getDouble(_kRadius) ?? defaultRadius).clamp(minRadius, maxRadius);
      _density = (p.getString(_kDensity) == 'compact')
          ? ChatDensity.compact
          : ChatDensity.comfortable;
      _reduceAnimations = p.getBool(_kReduceAnim) ?? false;
      _wallpaper = _wallpaperFrom(p.getString(_kWallpaper));
      _wallpaperPath = p.getString(_kWallpaperPath);
    } catch (_) {
      // Corrupt/unavailable prefs → ship the defaults rather than fail to boot.
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kThemeMode, _themeMode.name);
      await p.setInt(_kAccent, _accent.toARGB32());
      await p.setDouble(_kTextSize, _textSize);
      await p.setDouble(_kRadius, _cornerRadius);
      await p.setString(_kDensity, _density.name);
      await p.setBool(_kReduceAnim, _reduceAnimations);
      await p.setString(_kWallpaper, _wallpaper.name);
      if (_wallpaperPath == null) {
        await p.remove(_kWallpaperPath);
      } else {
        await p.setString(_kWallpaperPath, _wallpaperPath!);
      }
    } catch (_) {/* cosmetic — never surface */}
  }

  /// Push to the backend so other devices match. Fire-and-forget by design:
  /// the local write already happened and is what this device renders.
  void _push() {
    ApiService.setAppearance({
      'theme_mode': _themeMode.name,
      'accent': '#${_accent.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
      'text_size': _textSize.round(),
      'corner_radius': _cornerRadius.round(),
      'density': _density.name,
      'reduce_animations': _reduceAnimations,
      'wallpaper': _wallpaper.name,
    });
  }

  Future<void> _commit() async {
    notifyListeners();
    await _save();
    _push();
  }

  /// Adopt the server's settings (call after login). Silent on failure — an
  /// unreachable server just means this device keeps what it has.
  ///
  /// A `custom` wallpaper is deliberately NOT adopted: the image lives only on
  /// the device that chose it, so honouring it here would show this device a
  /// broken/missing background. It falls back to none.
  Future<void> syncFromServer() async {
    final data = await ApiService.getAppearance();
    if (data == null || data.isEmpty) return;
    try {
      _themeMode = _themeModeFrom(data['theme_mode'] as String?);
      final hex = (data['accent'] as String?) ?? '';
      final parsed = _colorFromHex(hex);
      if (parsed != null) _accent = parsed;
      final ts = (data['text_size'] as num?)?.toDouble();
      if (ts != null) _textSize = ts.clamp(minTextSize, maxTextSize);
      final cr = (data['corner_radius'] as num?)?.toDouble();
      if (cr != null) _cornerRadius = cr.clamp(minRadius, maxRadius);
      _density = (data['density'] == 'compact')
          ? ChatDensity.compact
          : ChatDensity.comfortable;
      _reduceAnimations = data['reduce_animations'] == true;
      final w = _wallpaperFrom(data['wallpaper'] as String?);
      _wallpaper = (w == Wallpaper.custom && (_wallpaperPath ?? '').isEmpty)
          ? Wallpaper.none
          : w;
    } catch (_) {
      return;
    }
    notifyListeners();
    await _save();
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  Future<void> setThemeMode(ThemeMode m) async {
    if (m == _themeMode) return;
    _themeMode = m;
    await _commit();
  }

  Future<void> setAccent(Color c) async {
    if (c.toARGB32() == _accent.toARGB32()) return;
    _accent = c;
    await _commit();
  }

  /// Live-drag friendly: updates the UI without hammering prefs/network.
  void previewTextSize(double v) {
    _textSize = v.clamp(minTextSize, maxTextSize);
    notifyListeners();
  }

  void previewCornerRadius(double v) {
    _cornerRadius = v.clamp(minRadius, maxRadius);
    notifyListeners();
  }

  /// Call on slider release — one write, one sync, instead of one per pixel.
  Future<void> commitPreview() => _commit();

  Future<void> setDensity(ChatDensity d) async {
    if (d == _density) return;
    _density = d;
    await _commit();
  }

  Future<void> setReduceAnimations(bool v) async {
    if (v == _reduceAnimations) return;
    _reduceAnimations = v;
    await _commit();
  }

  /// Apply a colour theme: the wallpaper AND its matching accent, so the two
  /// always agree. Pass [matchAccent] false to change only the background.
  Future<void> setWallpaper(Wallpaper w, {String? path, bool matchAccent = true}) async {
    _wallpaper = w;
    if (w == Wallpaper.custom) {
      _wallpaperPath = path ?? _wallpaperPath;
      if ((_wallpaperPath ?? '').isEmpty) _wallpaper = Wallpaper.none;
    }
    if (matchAccent) {
      final paired = accentFor(_wallpaper);
      if (paired != null) _accent = paired;
    }
    await _commit();
  }

  /// Back to the shipped look.
  Future<void> resetToDefaults() async {
    _themeMode = ThemeMode.dark;
    _accent = defaultAccent;
    _textSize = defaultTextSize;
    _cornerRadius = defaultRadius;
    _density = ChatDensity.comfortable;
    _reduceAnimations = false;
    _wallpaper = Wallpaper.none;
    _wallpaperPath = null;
    await _commit();
  }

  // ── Parsing helpers ───────────────────────────────────────────────────────

  static ThemeMode _themeModeFrom(String? s) => switch (s) {
        'system' => ThemeMode.system,
        'light' => ThemeMode.light,
        _ => ThemeMode.dark,
      };

  static Wallpaper _wallpaperFrom(String? s) => Wallpaper.values.firstWhere(
        (w) => w.name == s,
        orElse: () => Wallpaper.none,
      );

  static Color? _colorFromHex(String hex) {
    final h = hex.replaceFirst('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  /// The gradient for a built-in wallpaper, or null for none/custom.
  /// Tuned to sit behind opaque bubbles without fighting them for attention.
  static LinearGradient? gradientFor(Wallpaper w, bool isDark) {
    List<Color>? c = switch (w) {
      Wallpaper.dusk => isDark
          ? [const Color(0xFF1A1033), const Color(0xFF0D0D0D)]
          : [const Color(0xFFEDE9FE), const Color(0xFFF8FAFC)],
      Wallpaper.forest => isDark
          ? [const Color(0xFF06231B), const Color(0xFF0D0D0D)]
          : [const Color(0xFFDCFCE7), const Color(0xFFF8FAFC)],
      Wallpaper.ocean => isDark
          ? [const Color(0xFF072034), const Color(0xFF0D0D0D)]
          : [const Color(0xFFDBEAFE), const Color(0xFFF8FAFC)],
      Wallpaper.ember => isDark
          ? [const Color(0xFF2A1206), const Color(0xFF0D0D0D)]
          : [const Color(0xFFFFEDD5), const Color(0xFFF8FAFC)],
      Wallpaper.rose => isDark
          ? [const Color(0xFF2B0A1E), const Color(0xFF0D0D0D)]
          : [const Color(0xFFFCE7F3), const Color(0xFFF8FAFC)],
      Wallpaper.mono => isDark
          ? [const Color(0xFF23272E), const Color(0xFF0D0D0D)]
          : [const Color(0xFFE5E7EB), const Color(0xFFF8FAFC)],
      _ => null,
    };
    if (c == null) return null;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: c,
    );
  }

  static String labelFor(Wallpaper w) => switch (w) {
        Wallpaper.none => 'None',
        Wallpaper.dusk => 'Dusk',
        Wallpaper.forest => 'Forest',
        Wallpaper.ocean => 'Ocean',
        Wallpaper.ember => 'Ember',
        Wallpaper.rose => 'Rose',
        Wallpaper.mono => 'Mono',
        Wallpaper.custom => 'Custom',
      };
}
