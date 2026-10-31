import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:package_info_plus/package_info_plus.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const SplashScreen({Key? key, required this.nextScreen}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _weldingController;
  late AnimationController _pulseController;
  late AnimationController _waveController;

  late Animation<double> _fadeInAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  late Animation<double> _titleOpacityAnimation;
  late Animation<Offset> _titleSlideAnimation;
  late Animation<double> _subtitleOpacityAnimation;
  late Animation<Offset> _subtitleSlideAnimation;

  late Animation<double> _logoGlowAnimation;
  late Animation<double> _logoBouncingAnimation;
  late Animation<double> _weldingRotationAnimation;

  List<SparkParticle> _sparkParticles = [];
  String _appVersion = '1.0.0';

  final Color primaryPurple = const Color(0xFF8A2BE2);
  final Color lightPurple = const Color(0xFFB19CD9);
  final Color darkPurple = const Color(0xFF4B0082);
  final Color accentPurple = const Color(0xFFD8BFD8);

  @override
  void initState() {
    super.initState();
    _loadAppVersion();

    _mainController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _weldingController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: math.pi * 2).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOutBack),
      ),
    );

    _titleOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.5, 0.7, curve: Curves.easeIn),
      ),
    );

    _titleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.5, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _subtitleOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.7, 0.9, curve: Curves.easeIn),
      ),
    );

    _subtitleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _logoGlowAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _logoBouncingAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(
        parent: _waveController,
        curve: Curves.easeInOut,
      ),
    );

    _weldingRotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _weldingController,
        curve: Curves.linear,
      ),
    );

    _mainController.forward();
    _initializeSparkParticles();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => widget.nextScreen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var offsetAnimation = animation.drive(tween);
            return SlideTransition(
              position: offsetAnimation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version;
      });
    } catch (e) {}
  }

  void _initializeSparkParticles() {
    _sparkParticles = List.generate(
      50,
      (index) => SparkParticle(
        angle: math.Random().nextDouble() * 2 * math.pi,
        speed: math.Random().nextDouble() * 2 + 1,
        offset: math.Random().nextDouble(),
        color: lightPurple,
        size: math.Random().nextDouble() * 2 + 1,
      ),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _weldingController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_mainController, _pulseController, _waveController, _weldingController]),
              builder: (context, child) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, _logoBouncingAnimation.value),
                      child: FadeTransition(
                        opacity: _fadeInAnimation,
                        child: Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Transform.rotate(
                            angle: _rotationAnimation.value,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryPurple.withOpacity(0.5 * _logoGlowAnimation.value),
                                        blurRadius: 30 * _logoGlowAnimation.value,
                                        spreadRadius: 5 * _logoGlowAnimation.value,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(60),
                                    child: Image.asset(
                                      'assets/icon/app_icon.png',
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                CustomPaint(
                                  size: const Size(150, 150),
                                  painter: WeldingCirclePainter(
                                    animationValue: _weldingRotationAnimation.value,
                                    color: lightPurple.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    FadeTransition(
                      opacity: _titleOpacityAnimation,
                      child: SlideTransition(
                        position: _titleSlideAnimation,
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: [lightPurple, primaryPurple, darkPurple],
                              stops: const [0.0, 0.5, 1.0],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              tileMode: TileMode.clamp,
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'Palm Vibe',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    FadeTransition(
                      opacity: _subtitleOpacityAnimation,
                      child: SlideTransition(
                        position: _subtitleSlideAnimation,
                        child: Text(
                          'Cinema in Your Pocket.',
                          style: TextStyle(
                            color: accentPurple,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Text(
                'Version $_appVersion',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 10,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _weldingRotationAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: SparkParticlePainter(
                  animationValue: _weldingRotationAnimation.value,
                  center: Offset(size.width / 2, size.height / 2),
                  particles: _sparkParticles,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class WeldingCirclePainter extends CustomPainter {
  final double animationValue;
  final Color color;
  
  WeldingCirclePainter({
    required this.animationValue,
    required this.color,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    const segmentCount = 25;
    const segmentLength = 12.0;
    const emptyLength = 8.0;
    
    for (int i = 0; i < segmentCount; i++) {
      final startAngle = (animationValue * 360 + i * (segmentLength + emptyLength)) * math.pi / 180;
      paint.color = color.withOpacity(1.0 - (i / segmentCount));
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentLength * math.pi / 180,
        false,
        paint,
      );
    }
  }
    
  @override
  bool shouldRepaint(WeldingCirclePainter oldDelegate) => animationValue != oldDelegate.animationValue || color != oldDelegate.color;
}

class SparkParticle {
  double angle;
  double speed;
  double offset;
  Color color;
  double size;

  SparkParticle({
    required this.angle,
    required this.speed,
    required this.offset,
    required this.color,
    required this.size,
  });
}

class SparkParticlePainter extends CustomPainter {
  final double animationValue;
  final Offset center;
  final List<SparkParticle> particles;

  SparkParticlePainter({
    required this.animationValue,
    required this.center,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final double progress = (animationValue + particle.offset) % 1.0;
      final double distance = progress * 200 * particle.speed;
      final offset = Offset(
        center.dx + math.cos(particle.angle) * distance,
        center.dy + math.sin(particle.angle) * distance,
      );
      final double opacity = (1.0 - progress).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = particle.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(SparkParticlePainter oldDelegate) => true;
}
