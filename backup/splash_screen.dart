import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:package_info_plus/package_info_plus.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const SplashScreen({Key? key, required this.nextScreen}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _mainController;
  late AnimationController _weldingController; // New controller for welding effect
  late AnimationController _pulseController;
  late AnimationController _waveController;

  // Main animations
  late Animation<double> _fadeInAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  // Text animations
  late Animation<double> _titleOpacityAnimation;
  late Animation<Offset> _titleSlideAnimation;
  late Animation<double> _subtitleOpacityAnimation;
  late Animation<Offset> _subtitleSlideAnimation;

  // Logo animations
  late Animation<double> _logoGlowAnimation;
  late Animation<double> _logoBouncingAnimation;

  // Welding circle animations
  late Animation<double> _weldingRotationAnimation;

  // Spark particles
  List<SparkParticle> _sparkParticles = [];
  bool _sparksInitialized = false;

  // App version
  String _appVersion = '1.0.0'; // Default value

  // Purple theme colors
  final Color primaryPurple = const Color(0xFF8A2BE2); // BlueViolet
  final Color lightPurple = const Color(0xFFB19CD9);   // Light purple
  final Color darkPurple = const Color(0xFF4B0082);    // Indigo
  final Color accentPurple = const Color(0xFFD8BFD8);  // Thistle

  @override
  void initState() {
    super.initState();

    // Load app version
    _loadAppVersion();

    // Initialize main animation controller
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // Initialize welding animation controller
    _weldingController = AnimationController(
      duration: const Duration(milliseconds: 6000), // Slower welding animation
      vsync: this,
    )..repeat();

    // Initialize pulse animation controller
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    // Initialize wave animation controller
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // Main animations
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

    // Text animations
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

    // Logo animations
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

    // Welding circle animation
    _weldingRotationAnimation = Tween<double>(begin: 0.0, end: math.pi * 2).animate(
      CurvedAnimation(
        parent: _weldingController,
        curve: Curves.linear,
      ),
    );

    // Start animations
    _mainController.forward();
    _weldingController.forward();

    // Initialize the spark particles
    _initializeSparkParticles();

    // Navigate to next screen after delay
    Timer(const Duration(seconds: 5), () {
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
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version;
      });
      print('Loaded app version: $_appVersion'); // Debug log
    } catch (e) {
      print('Error loading package info: $e');
      // Keep the default version if there's an error
    }
  }

  void _initializeSparkParticles() {
    _sparkParticles = List.generate(
      40, // Number of sparks
      (index) => SparkParticle(
        angle: math.Random().nextDouble() * 2 * math.pi,
        speed: math.Random().nextDouble() * 3 + 1,
        offset: Offset.zero,
        lifetime: math.Random().nextDouble() * 1.5 + 0.5, // Lifetime between 0.5 and 2 seconds
        color: lightPurple.withOpacity(0.8),
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
          // Main content
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_mainController, _pulseController, _waveController, _weldingController]),
              builder: (context, child) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo animation
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
                                // Background circle with glow
                                Container(
                                  width: 150,
                                  height: 150,
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
                                    borderRadius: BorderRadius.circular(75),
                                    child: Image.asset(
                                      'assets/icon/app_icon.png',
                                      width: 150,
                                      height: 150,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                
                                // Welding particles animation
                                CustomPaint(
                                  size: const Size(180, 180),
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
                    
                    const SizedBox(height: 50),
                    
                    // Title animation
                    FadeTransition(
                      opacity: _titleOpacityAnimation,
                      child: SlideTransition(
                        position: _titleSlideAnimation,
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: [
                                lightPurple,
                                primaryPurple,
                                darkPurple,
                              ],
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
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Subtitle animation
                    FadeTransition(
                      opacity: _subtitleOpacityAnimation,
                      child: SlideTransition(
                        position: _subtitleSlideAnimation,
                        child: Text(
                          'Cinema in Your Pocket. Anytime. Anywhere. Palm Vibe.',
                          style: TextStyle(
                            color: accentPurple,
                            fontSize: 16,
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
          
          // Version display - sleek style at the bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Text(
                'Version $_appVersion',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          
          // Spark particles effect
          AnimatedBuilder(
            animation: _weldingController,
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

  Widget _buildLoadingIndicator() {
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating circle
          RotationTransition(
            turns: Tween(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: _waveController,
                curve: Curves.linear,
              ),
            ),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(lightPurple),
              strokeWidth: 2,
              backgroundColor: Colors.grey.shade800.withOpacity(0.3),
            ),
          ),

          // Pulsing inner circle
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 40 * _logoGlowAnimation.value * 0.7,
                height: 40 * _logoGlowAnimation.value * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryPurple.withOpacity(0.3),
                ),
              );
            },
          ),

          // Static inner circle
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryPurple,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for welding circle
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
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    const segmentCount = 30;
    const segmentLength = 15.0;
    const emptyLength = 10.0;
    
    for (int i = 0; i < segmentCount; i++) {
      final startAngle = (animationValue * 360 + i * (segmentLength + emptyLength)) * math.pi / 180;
      final endAngle = startAngle + segmentLength * math.pi / 180;
      
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
  Offset offset;
  double lifetime;
  Color color;
  double size;

  SparkParticle({
    required this.angle,
    required this.speed,
    required this.offset,
    required this.lifetime,
    required this.color,
    required this.size,
  });
}

// Custom painter for spark particles
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
      // Calculate the offset based on the angle, speed, and animation value
      final distance = particle.speed * animationValue * 30; // Adjust for visual effect
      final offset = Offset(
        center.dx + math.cos(particle.angle) * distance,
        center.dy + math.sin(particle.angle) * distance,
      );

      // Draw the spark particle
      final paint = Paint()
        ..color = particle.color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(offset, particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(SparkParticlePainter oldDelegate) => true;
}
