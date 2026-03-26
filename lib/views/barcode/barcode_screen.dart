import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../controllers/log_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/food_item.dart';
import '../../services/analytics_service.dart';
import '../../services/haptic_service.dart';
import '../../widgets/sheet_handle.dart';

// ─── Public entry-point ───────────────────────────────────────────────────────

class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

enum _ScreenState { scanning, loading, notFound }

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  late final MobileScannerController _scanner;
  var _ui = _ScreenState.scanning;
  // Prevents re-entry while an API call or sheet is in flight.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.all],
    );
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  // ── Barcode detected ───────────────────────────────────────────────────────

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    _handled = true;
    HapticService.medium();
    AnalyticsService.track('barcode_scanned');
    await _scanner.stop();
    if (!mounted) return;
    setState(() => _ui = _ScreenState.loading);

    final item = await _fetchProduct(raw);
    if (!mounted) return;

    if (item == null) {
      setState(() => _ui = _ScreenState.notFound);
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _resumeScanning();
      return;
    }

    final logged = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductSheet(item: item),
    );

    if (!mounted) return;
    if (logged == true) {
      Navigator.of(context).pop(); // back to camera — chip already updated
    } else {
      await _resumeScanning();
    }
  }

  Future<void> _resumeScanning() async {
    _handled = false;
    await _scanner.start();
    if (mounted) setState(() => _ui = _ScreenState.scanning);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),

          // Dark overlay with transparent scan-window cutout
          Positioned.fill(child: CustomPaint(painter: _ScanOverlayPainter())),

          // Back button
          Positioned(
            top: topPad + 12,
            left: 16,
            child: _CircleButton(
              icon: Icons.close_rounded,
              onTap: () {
                HapticService.selection();
                Navigator.of(context).pop();
              },
            ),
          ),

          // Title
          Positioned(
            top: topPad + 18,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Scan Barcode',
                style: AppTextStyles.titleMedium.copyWith(color: Colors.white),
              ),
            ),
          ),

          // Status label / spinner
          Positioned(
            bottom: botPad + 48,
            left: 24,
            right: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _buildStatus(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    return switch (_ui) {
      _ScreenState.scanning => Text(
          'Point at a food product barcode',
          key: const ValueKey('scanning'),
          style: AppTextStyles.bodyMedium.copyWith(color: Colors.white60),
          textAlign: TextAlign.center,
        ),
      _ScreenState.loading => const Column(
          key: ValueKey('loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2),
            ),
            SizedBox(height: 10),
            Text(
              'Looking up product…',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  fontWeight: FontWeight.w400),
            ),
          ],
        ),
      _ScreenState.notFound => Text(
          'Product not found — try again',
          key: const ValueKey('notFound'),
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.danger, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
    };
  }
}

// ─── Open Food Facts lookup ───────────────────────────────────────────────────

/// Calls the Open Food Facts v2 API and parses the product into a [FoodItem].
/// Returns null if the barcode is not found or has no calorie data.
Future<FoodItem?> _fetchProduct(String barcode) async {
  try {
    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$barcode.json'
      '?fields=product_name,brands,nutriments,serving_quantity,serving_size',
    );
    final response =
        await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final body = json.decode(response.body) as Map<String, dynamic>;
    if (body['status'] != 1) return null;

    final product = body['product'] as Map<String, dynamic>? ?? {};
    return _parseProduct(product);
  } catch (_) {
    return null;
  }
}

FoodItem? _parseProduct(Map<String, dynamic> p) {
  final name = (p['product_name'] as String?)?.trim() ?? '';
  if (name.isEmpty) return null;

  final brands = (p['brands'] as String? ?? '').trim();
  final displayName = brands.isNotEmpty ? '$name · $brands' : name;

  final n = p['nutriments'] as Map<String, dynamic>? ?? {};

  // Prefer per-serving, fall back to per-100g
  final kcalServing = (n['energy-kcal_serving'] as num?)?.toInt();
  final kcalPer100 = (n['energy-kcal_100g'] as num?)?.toInt()
      ?? (n['energy-kcal'] as num?)?.toInt();
  final servingQty = (p['serving_quantity'] as num?)?.toDouble() ?? 100.0;

  late final int kcal;
  late final String portionUnit;
  late final double portionSize;

  if (kcalServing != null && kcalServing > 0) {
    kcal = kcalServing;
    portionUnit = 'serving';
    portionSize = 1.0;
  } else if (kcalPer100 != null && kcalPer100 > 0) {
    kcal = ((kcalPer100 * servingQty) / 100).round();
    portionUnit = 'g';
    portionSize = servingQty;
  } else {
    return null;
  }

  if (kcal <= 0) return null;

  double? nutrient(String key) {
    final serving = (n['${key}_serving'] as num?)?.toDouble();
    if (serving != null && serving >= 0) return serving;
    final per100 = (n['${key}_100g'] as num?)?.toDouble();
    if (per100 != null && per100 >= 0) {
      return per100 * servingQty / 100;
    }
    return null;
  }

  return FoodItem(
    name: displayName,
    portionSize: portionSize,
    portionUnit: portionUnit,
    calories: kcal,
    protein: nutrient('proteins'),
    carbs: nutrient('carbohydrates'),
    fat: nutrient('fat'),
    confidenceScore: 1.0,
  );
}

// ─── Product confirmation sheet ───────────────────────────────────────────────

class _ProductSheet extends ConsumerStatefulWidget {
  final FoodItem item;
  const _ProductSheet({required this.item});

  @override
  ConsumerState<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends ConsumerState<_ProductSheet> {
  double _multiplier = 1.0;
  bool _saving = false;

  int get _kcal => (widget.item.calories * _multiplier).round();

  double? _scale(double? v) => v != null ? v * _multiplier : null;

  Future<void> _log() async {
    setState(() => _saving = true);

    final scaled = FoodItem(
      name: widget.item.name,
      portionSize: widget.item.portionSize * _multiplier,
      portionUnit: widget.item.portionUnit,
      calories: _kcal,
      protein: _scale(widget.item.protein),
      carbs: _scale(widget.item.carbs),
      fat: _scale(widget.item.fat),
      confidenceScore: 1.0,
    );

    final log = await directLogMeal(ref, items: [scaled]);
    if (mounted) Navigator.of(context).pop(log != null);
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, botPad + 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 20),

          // Product name + portion
          Text(
            widget.item.name,
            style: AppTextStyles.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(widget.item.portionLabel,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),

          const SizedBox(height: 20),

          // Calorie headline
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$_kcal',
                  style: AppTextStyles.calorieDisplay
                      .copyWith(color: AppColors.accent)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('kcal', style: AppTextStyles.bodyMedium),
              ),
            ],
          ),

          // Macro chips
          if (widget.item.protein != null ||
              widget.item.carbs != null ||
              widget.item.fat != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (widget.item.protein != null)
                  _MacroTag(
                    label: 'P',
                    value: _scale(widget.item.protein)!,
                    color: const Color(0xFF4ECDC4),
                  ),
                if (widget.item.carbs != null) ...[
                  const SizedBox(width: 8),
                  _MacroTag(
                    label: 'C',
                    value: _scale(widget.item.carbs)!,
                    color: const Color(0xFFFFD166),
                  ),
                ],
                if (widget.item.fat != null) ...[
                  const SizedBox(width: 8),
                  _MacroTag(
                    label: 'F',
                    value: _scale(widget.item.fat)!,
                    color: const Color(0xFFFF6B6B),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 20),

          // Portion multiplier chips
          Text('Portion', style: AppTextStyles.caption),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final mult in [0.5, 1.0, 1.5, 2.0, 3.0])
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticService.selection();
                      setState(() => _multiplier = mult);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _multiplier == mult
                            ? AppColors.accent
                            : AppColors.card,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$mult×',
                        style: AppTextStyles.caption.copyWith(
                          color: _multiplier == mult
                              ? Colors.black
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _saving ? null : () {
              HapticService.heavy();
              _log();
            },
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Log meal'),
          ),
        ],
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _MacroTag extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MacroTag(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label ${value.toStringAsFixed(1)}g',
        style: AppTextStyles.caption
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

// ─── Scan window overlay painter ─────────────────────────────────────────────

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanW = size.width * 0.76;
    const scanH = 160.0;
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: scanW,
      height: scanH,
    );

    // Dark overlay with transparent hole
    final outer = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(10)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    // Accent corner brackets
    final p = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const arm = 22.0;
    final l = scanRect.left;
    final t = scanRect.top;
    final r = scanRect.right;
    final b = scanRect.bottom;

    // Top-left
    canvas.drawLine(Offset(l, t + arm), Offset(l, t), p);
    canvas.drawLine(Offset(l, t), Offset(l + arm, t), p);
    // Top-right
    canvas.drawLine(Offset(r - arm, t), Offset(r, t), p);
    canvas.drawLine(Offset(r, t), Offset(r, t + arm), p);
    // Bottom-left
    canvas.drawLine(Offset(l, b - arm), Offset(l, b), p);
    canvas.drawLine(Offset(l, b), Offset(l + arm, b), p);
    // Bottom-right
    canvas.drawLine(Offset(r - arm, b), Offset(r, b), p);
    canvas.drawLine(Offset(r, b), Offset(r, b - arm), p);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter _) => false;
}
