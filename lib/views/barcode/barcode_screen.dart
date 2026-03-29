import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../controllers/log_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/food_item.dart';
import '../../models/product_match.dart';
import '../../services/analytics_service.dart';
import '../../services/haptic_service.dart';
import '../../services/ocr_extraction_service.dart';
import '../../services/product_identification_service.dart';
import '../../widgets/sheet_handle.dart';

// ─── Public entry-point ───────────────────────────────────────────────────────

class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

enum _ScreenState { scanning, loading, notFound, labelScan }

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
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

    final result =
        await ref.read(productIdentificationProvider).identifyByBarcode(raw);
    if (!mounted) return;

    if (!result.resolved) {
      // Stay on notFound so the user can try the label-scan fallback.
      setState(() => _ui = _ScreenState.notFound);
      return;
    }

    await _showProductSheet(result);
  }

  // ── Label scan (OCR fallback) ──────────────────────────────────────────────

  Future<void> _onScanLabel() async {
    HapticService.selection();
    setState(() => _ui = _ScreenState.labelScan);

    final xfile = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 80);

    if (!mounted) return;

    if (xfile == null) {
      setState(() => _ui = _ScreenState.notFound);
      return;
    }

    final bytes = await xfile.readAsBytes();
    final extraction = await OcrExtractionService.extractFromImage(bytes);
    if (!mounted) return;

    if (extraction == null || !extraction.hasUsableData) {
      setState(() => _ui = _ScreenState.notFound);
      return;
    }

    final service = ref.read(productIdentificationProvider);
    ProductIdentificationResult result;

    // If Gemini spotted a barcode in the photo, try that first.
    if (extraction.barcode != null) {
      result = await service.identifyByBarcode(extraction.barcode!);
      if (result.resolved) {
        if (!mounted) return;
        await _showProductSheet(result);
        return;
      }
    }

    // Fall back to brand + name + size text matching.
    result = await service.identifyByText(
      extraction.productName ?? '',
      brand: extraction.brand,
      sizeMl: extraction.sizeMl,
    );
    if (!mounted) return;

    if (!result.resolved) {
      setState(() => _ui = _ScreenState.notFound);
      return;
    }

    await _showProductSheet(result);
  }

  // ── Product sheet ──────────────────────────────────────────────────────────

  Future<void> _showProductSheet(ProductIdentificationResult result) async {
    final logged = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductSheet(result: result),
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

  // ── Build ──────────────────────────────────────────────────────────────────

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

          // Status label / spinner / action buttons
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
      _ScreenState.notFound => Column(
          key: const ValueKey('notFound'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Product not found',
              style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.danger, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _OutlineButton(
                  icon: Icons.document_scanner_rounded,
                  label: 'Scan label',
                  onTap: _onScanLabel,
                ),
                const SizedBox(width: 12),
                _OutlineButton(
                  icon: Icons.refresh_rounded,
                  label: 'Try again',
                  onTap: _resumeScanning,
                ),
              ],
            ),
          ],
        ),
      _ScreenState.labelScan => const Column(
          key: ValueKey('labelScan'),
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
              'Reading label…',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  fontWeight: FontWeight.w400),
            ),
          ],
        ),
    };
  }
}

// ─── Product confirmation sheet ───────────────────────────────────────────────

class _ProductSheet extends ConsumerStatefulWidget {
  final ProductIdentificationResult result;
  const _ProductSheet({required this.result});

  @override
  ConsumerState<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends ConsumerState<_ProductSheet> {
  double _multiplier = 1.0;
  bool _saving = false;

  FoodItem get _item => widget.result.item!;

  int get _kcal => (_item.calories * _multiplier).round();

  double? _scale(double? v) => v != null ? v * _multiplier : null;

  Future<void> _log() async {
    setState(() => _saving = true);

    final scaled = FoodItem(
      name: _item.name,
      portionSize: _item.portionSize * _multiplier,
      portionUnit: _item.portionUnit,
      calories: _kcal,
      protein: _scale(_item.protein),
      carbs: _scale(_item.carbs),
      fat: _scale(_item.fat),
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
            _item.name,
            style: AppTextStyles.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(_item.portionLabel,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),

          // Fallback source badge — only shown when not an exact OFF match
          if (widget.result.matchSource != MatchSource.offExact) ...[
            const SizedBox(height: 6),
            _SourceBadge(source: widget.result.matchSource),
          ],

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
          if (_item.protein != null ||
              _item.carbs != null ||
              _item.fat != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (_item.protein != null)
                  _MacroTag(
                    label: 'P',
                    value: _scale(_item.protein)!,
                    color: const Color(0xFF4ECDC4),
                  ),
                if (_item.carbs != null) ...[
                  const SizedBox(width: 8),
                  _MacroTag(
                    label: 'C',
                    value: _scale(_item.carbs)!,
                    color: const Color(0xFFFFD166),
                  ),
                ],
                if (_item.fat != null) ...[
                  const SizedBox(width: 8),
                  _MacroTag(
                    label: 'F',
                    value: _scale(_item.fat)!,
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
            onPressed: _saving
                ? null
                : () {
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

// ─── Source badge ─────────────────────────────────────────────────────────────

class _SourceBadge extends StatelessWidget {
  final MatchSource source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final label = switch (source) {
      MatchSource.offNormalized => 'Matched via barcode variant',
      MatchSource.localBarcode => 'Matched from product database',
      MatchSource.localAlias => 'Matched via product alias',
      MatchSource.ocrMatch => 'Matched via label scan',
      _ => null,
    };
    if (label == null) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(Icons.info_outline_rounded,
            size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary)),
      ],
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

class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OutlineButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
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
