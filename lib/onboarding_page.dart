// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_device_page.dart';
import 'home_page.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _kBg     = Color(0xFF0a1628);
const _kAccent = Color(0xFF38d9a9);

// ── Slide data model ───────────────────────────────────────────────────────────

class _SlideData {
  final Color iconBg;
  final Color iconColor;
  final IconData? icon;
  final bool useLogo;
  final String title;
  final String description;

  const _SlideData({
    required this.iconBg,
    required this.iconColor,
    this.icon,
    this.useLogo = false,
    required this.title,
    required this.description,
  });
}

const _kSlides = [
  _SlideData(
    iconBg: Color(0xFF0f2847),
    iconColor: _kAccent,
    useLogo: true,
    title: 'Bem-vindo ao AVERIS',
    description:
        'Monitoriza o consumo de energia da tua casa em tempo real e começa a poupar desde o primeiro dia.',
  ),
  _SlideData(
    iconBg: Color(0xFF0d2040),
    iconColor: Color(0xFF378add),
    icon: Icons.show_chart,
    title: 'Consumo em tempo real',
    description:
        'Vê a potência de cada dispositivo atualizada a cada 3 segundos. Gráficos claros e métricas detalhadas.',
  ),
  _SlideData(
    iconBg: Color(0xFF130f30),
    iconColor: Color(0xFF7f77dd),
    icon: Icons.emoji_events,
    title: 'Ganha XP ao poupar',
    description:
        'Cada dia que consomes menos do que a tua média ganhas pontos XP. Sobe de nível e torna-te um Lenda.',
  ),
  _SlideData(
    iconBg: Color(0xFF201408),
    iconColor: Color(0xFFf4a234),
    icon: Icons.power_outlined,
    title: 'Adiciona o teu primeiro Shelly',
    description:
        'Liga o Shelly Plug S Gen 3 à tomada e a app guia-te pelo processo. Em menos de 2 minutos estás a monitorizar.',
  ),
];

// ══════════════════════════════════════════════════════════════════════════════
// OnboardingPage
// ══════════════════════════════════════════════════════════════════════════════

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _skip(BuildContext ctx) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'onboardingDone': true});
    }
    if (!ctx.mounted) return;
    Navigator.of(ctx).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (_) => false,
    );
  }

  Future<void> _addDevice(BuildContext ctx) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'onboardingDone': true});
    }
    if (!ctx.mounted) return;
    final nav = Navigator.of(ctx);
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (_) => false,
    );
    nav.push(MaterialPageRoute(builder: (_) => const AddDevicePage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _current = i),
                itemCount: _kSlides.length,
                itemBuilder: (_, i) => _OnboardingSlide(
                  data: _kSlides[i],
                  isActive: _current == i,
                ),
              ),
            ),

            // ── Dots ────────────────────────────────────────────────────────
            OnboardingDots(current: _current, count: _kSlides.length),
            const SizedBox(height: 28),

            // ── Buttons ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_current < _kSlides.length - 1) ...[
                    // slides 0–2
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: const Color(0xFF04342c),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _current == 0 ? 'Começar →' : 'Continuar →',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _skip(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0x66FFFFFF),
                      ),
                      child: const Text(
                        'Saltar introdução',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ] else ...[
                    // slide 3 (last)
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => _addDevice(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: const Color(0xFF04342c),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Adicionar dispositivo',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _skip(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0x66FFFFFF),
                      ),
                      child: const Text(
                        'Fazer mais tarde',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _OnboardingSlide
// ══════════════════════════════════════════════════════════════════════════════

class _OnboardingSlide extends StatelessWidget {
  final _SlideData data;
  final bool isActive;

  const _OnboardingSlide({
    required this.data,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated icon
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: isActive ? 1.0 : 0.92),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (_, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: data.iconBg,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: data.iconColor.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: data.useLogo
                  ? CustomPaint(painter: _AverisLogoPainter(data.iconColor))
                  : Icon(data.icon, color: data.iconColor, size: 44),
            ),
          ),

          const SizedBox(height: 36),

          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),

          const SizedBox(height: 14),

          Text(
            data.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OnboardingDots
// ══════════════════════════════════════════════════════════════════════════════

class OnboardingDots extends StatelessWidget {
  final int current;
  final int count;

  const OnboardingDots({
    super.key,
    required this.current,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? _kAccent
                : Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _AverisLogoPainter — bars + lightning bolt for slide 1
// ══════════════════════════════════════════════════════════════════════════════

class _AverisLogoPainter extends CustomPainter {
  final Color color;
  const _AverisLogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final barPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const heightRatios = [0.38, 0.62, 0.82, 0.50];
    final barW = w * 0.13;
    final gap  = w * 0.065;
    final totalBarsW = barW * 4 + gap * 3;
    var barX = (w - totalBarsW) / 2;
    final baseY = h * 0.85;

    for (final ratio in heightRatios) {
      final barH = h * 0.50 * ratio;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, baseY - barH, barW, barH),
          const Radius.circular(2.5),
        ),
        barPaint,
      );
      barX += barW + gap;
    }

    final boltPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cx = w * 0.50;
    final s  = w * 0.10;
    final ty = h * 0.09;

    final bolt = Path()
      ..moveTo(cx + s, ty)
      ..lineTo(cx - s * 0.15, ty + s * 1.6)
      ..lineTo(cx + s * 0.35, ty + s * 1.6)
      ..lineTo(cx - s, ty + s * 3.2)
      ..lineTo(cx + s * 0.15, ty + s * 1.3)
      ..lineTo(cx - s * 0.35, ty + s * 1.3)
      ..close();
    canvas.drawPath(bolt, boltPaint);
  }

  @override
  bool shouldRepaint(covariant _AverisLogoPainter old) => old.color != color;
}
