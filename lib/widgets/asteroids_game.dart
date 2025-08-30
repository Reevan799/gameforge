import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class AsteroidsGame extends StatefulWidget {
  const AsteroidsGame({super.key});

  @override
  State<AsteroidsGame> createState() => _AsteroidsGameState();
}

class _AsteroidsGameState extends State<AsteroidsGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _timer;

  List<Asteroid> asteroids = [];
  List<Bullet> bullets = [];
  List<HitParticle> hitParticles = [];
  Ship ship = Ship();
  bool gameOver = false;

  int score = 0;
  int highScore = 0;

  // Invulnerability / blinking
  bool invulnerable = true;
  int invulnTicks = 120; // doubled (~4 seconds at 30ms ticks)
  bool shipVisible = true;
  Timer? _blinkTimer;

  // Developed by DareWorld opacity
  double dareOpacity = 1.0;
  Timer? _dareFadeTimer;

  // asteroid spawn manager
  Timer? _asteroidSpawnTimer;

  final Random _rand = Random();

  @override
  void initState() {
    super.initState();
    _startGame();
  }

  void _startGame() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(hours: 1),
    )..repeat();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      setState(() {
        _updateGame();
      });
    });

    _asteroidSpawnTimer?.cancel();
    _asteroidSpawnTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (gameOver) {
        t.cancel();
      } else {
        if (asteroids.length < 7) {
          setState(() {
            asteroids.add(Asteroid.fromOutside(color: Colors.deepPurpleAccent));
          });
        }
      }
    });

    // clear/reset
    asteroids.clear();
    bullets.clear();
    hitParticles.clear();
    ship = Ship();
    gameOver = false;
    score = 0;

    // invulnerability
    invulnerable = true;
    invulnTicks = 120;
    shipVisible = true;
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (invulnerable && !gameOver) {
        setState(() => shipVisible = !shipVisible);
      } else {
        shipVisible = true;
        t.cancel();
      }
    });

    // initial asteroids
    for (int i = 0; i < 3; i++) {
      asteroids.add(Asteroid.fromOutside(color: Colors.deepPurpleAccent));
    }

    // DareWorld fade
    dareOpacity = 1.0;
    _dareFadeTimer?.cancel();
    Future.delayed(const Duration(seconds: 2), () {
      _dareFadeTimer = Timer.periodic(const Duration(milliseconds: 120), (t) {
        setState(() {
          dareOpacity -= 0.05;
          if (dareOpacity <= 0) {
            dareOpacity = 0;
            t.cancel();
          }
        });
      });
    });
  }

  // -------------------
  // Geometry helpers
  // -------------------
  bool pointOnSegment(Offset p, Offset p1, Offset p2, {double eps = 0.0001}) {
    final minX = min(p1.dx, p2.dx) - eps;
    final maxX = max(p1.dx, p2.dx) + eps;
    final minY = min(p1.dy, p2.dy) - eps;
    final maxY = max(p1.dy, p2.dy) + eps;
    if (p.dx < minX || p.dx > maxX || p.dy < minY || p.dy > maxY) return false;
    final cross =
        (p.dy - p1.dy) * (p2.dx - p1.dx) - (p.dx - p1.dx) * (p2.dy - p1.dy);
    return cross.abs() <= eps;
  }

  bool pointInPolygon(Offset point, List<Offset> polygon) {
    for (int i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if (pointOnSegment(point, a, b, eps: 0.5)) return true;
    }
    int intersections = 0;
    for (int i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if ((a.dy > point.dy) != (b.dy > point.dy)) {
        final atX = a.dx + (point.dy - a.dy) * (b.dx - a.dx) / (b.dy - a.dy);
        if (point.dx < atX) intersections++;
      }
    }
    return (intersections % 2) == 1;
  }

  bool _segmentsIntersect(Offset p1, Offset p2, Offset q1, Offset q2) {
    double o1 = _orient(p1, p2, q1);
    double o2 = _orient(p1, p2, q2);
    double o3 = _orient(q1, q2, p1);
    double o4 = _orient(q1, q2, p2);
    if (o1 * o2 < 0 && o3 * o4 < 0) return true;
    if (o1 == 0 && _onSegment(p1, p2, q1)) return true;
    if (o2 == 0 && _onSegment(p1, p2, q2)) return true;
    if (o3 == 0 && _onSegment(q1, q2, p1)) return true;
    if (o4 == 0 && _onSegment(q1, q2, p2)) return true;
    return false;
  }

  double _orient(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }

  bool _onSegment(Offset a, Offset b, Offset p) {
    return (p.dx >= min(a.dx, b.dx) - 0.0001 &&
        p.dx <= max(a.dx, b.dx) + 0.0001 &&
        p.dy >= min(a.dy, b.dy) - 0.0001 &&
        p.dy <= max(a.dy, b.dy) + 0.0001);
  }

  bool polygonsIntersect(List<Offset> poly1, List<Offset> poly2) {
    for (int i = 0; i < poly1.length; i++) {
      final a1 = poly1[i];
      final a2 = poly1[(i + 1) % poly1.length];
      for (int j = 0; j < poly2.length; j++) {
        final b1 = poly2[j];
        final b2 = poly2[(j + 1) % poly2.length];
        if (_segmentsIntersect(a1, a2, b1, b2)) return true;
      }
    }
    if (pointInPolygon(poly1[0], poly2)) return true;
    if (pointInPolygon(poly2[0], poly1)) return true;
    return false;
  }

  // -------------------
  // Main update loop
  // -------------------
  void _updateGame() {
    if (gameOver) return;

    final screenW = MediaQuery.of(context).size.width;
    final screenH =
        MediaQuery.of(context).size.height - MediaQuery.of(context).padding.bottom;

    ship.update(screenH);

    for (var bullet in bullets) {
      bullet.update(screenH);
    }
    bullets.removeWhere((b) => b.isDead);

    for (var asteroid in asteroids) {
      asteroid.update();
      if (asteroid.position.dx < -100 ||
          asteroid.position.dx > screenW + 100 ||
          asteroid.position.dy < -100 ||
          asteroid.position.dy > screenH + 100) {
        asteroid.isDead = true;
      }
    }

    for (var p in hitParticles) {
      p.update();
    }
    hitParticles.removeWhere((p) => p.isDead);

    List<Asteroid> newAsteroids = [];
    for (var bullet in bullets) {
      for (var asteroid in asteroids) {
        final poly = asteroid.getVertices();
        bool hit = false;

        for (int i = 0; i < poly.length && !hit; i++) {
          final a = poly[i];
          final b = poly[(i + 1) % poly.length];
          if (pointOnSegment(bullet.position, a, b, eps: 1.5)) hit = true;
        }
        if (!hit && pointInPolygon(bullet.position, poly)) hit = true;

        if (hit) {
          bullet.isDead = true;
          asteroid.isDead = true;
          score += 10;

          final rand = Random();
          int burstCount = 4 + rand.nextInt(3);
          for (int i = 0; i < burstCount; i++) {
            hitParticles.add(HitParticle(asteroid.position, asteroid.color));
          }

          if (asteroid.size > 20) {
            if (asteroid.color == Colors.deepPurpleAccent) {
              newAsteroids.add(asteroid.split(Colors.green));
              newAsteroids.add(asteroid.split(Colors.green));
            } else if (asteroid.color == Colors.green) {
              newAsteroids.add(asteroid.split(Colors.red));
              newAsteroids.add(asteroid.split(Colors.red));
            }
          }
        }
      }
    }

    asteroids.addAll(newAsteroids);
    asteroids.removeWhere((a) => a.isDead);

    while (asteroids.length < 3) {
      asteroids.add(Asteroid.fromOutside());
    }

    if (!invulnerable) {
      final shipPoly = ship.getPolygon();
      for (var asteroid in asteroids) {
        final asteroidPoly = asteroid.getVertices();
        if (polygonsIntersect(shipPoly, asteroidPoly)) {
          final rand = Random();
          int burstCount = 4 + rand.nextInt(3);
          for (int i = 0; i < burstCount; i++) {
            hitParticles.add(HitParticle(ship.position, Colors.red));
          }
          _timer?.cancel();
          _controller.stop();
          gameOver = true;
          if (score > highScore) highScore = score;
          break;
        }
      }
    } else {
      invulnTicks--;
      if (invulnTicks <= 0) {
        invulnerable = false;
        shipVisible = true;
        _blinkTimer?.cancel();
      }
    }
  }

  void _fireBullet() {
    if (gameOver) return;
    setState(() {
      bullets.add(Bullet(ship.position));
      ship.slideDown();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    _blinkTimer?.cancel();
    _dareFadeTimer?.cancel();
    _asteroidSpawnTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (gameOver) {
          _startGame();
        } else {
          _fireBullet();
        }
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: MediaQuery.of(context).size,
            painter: GamePainter(
              ship,
              asteroids,
              bullets,
              hitParticles,
              gameOver,
              score,
              highScore,
              invulnerable,
              shipVisible,
              dareOpacity,
            ),
          );
        },
      ),
    );
  }
}

// ===== Ship =====
class Ship {
  Offset position;
  double targetY;
  double speedFactor = 0.0;
  double initialAccel = 0.02;

  Ship({Offset? position})
      : position = position ?? const Offset(200, 600),
        targetY = (position ?? const Offset(200, 600)).dy;

  void slideDown() {
    targetY += 80;
  }

  void update(double screenH) {
    speedFactor += initialAccel;
    if (speedFactor > 1.0) speedFactor = 1.0;

    position =
        Offset(position.dx, position.dy + (targetY - position.dy) * 0.08 * speedFactor);

    final bottomLimit = screenH;
    if (position.dy >= bottomLimit) {
      position = Offset(position.dx, 0);
      targetY = 0;
    }
    if (position.dy < 0) {
      position = Offset(position.dx, 0);
      targetY = 0;
    }
  }

  List<Offset> getPolygon() {
    return [
      Offset(position.dx, position.dy - 15),
      Offset(position.dx - 12, position.dy + 12),
      Offset(position.dx + 12, position.dy + 12),
    ];
  }

  Path getPath() {
    final path = Path();
    final poly = getPolygon();
    path.moveTo(poly[0].dx, poly[0].dy);
    for (int i = 1; i < poly.length; i++) path.lineTo(poly[i].dx, poly[i].dy);
    path.close();
    return path;
  }
}

// ===== Bullet =====
class Bullet {
  Offset position;
  double speed = -10;
  bool isDead = false;
  bool hasRespawned = false;

  Bullet(this.position);

  void update(double screenH) {
    position = Offset(position.dx, position.dy + speed);
    if (position.dy < 0) {
      if (!hasRespawned) {
        position = Offset(position.dx, screenH);
        hasRespawned = true;
      } else {
        isDead = true;
      }
    }
  }
}

// ===== Asteroid =====
class Asteroid {
  Offset position;
  double size;
  Offset velocity;
  bool isDead = false;
  List<double> offsets = [];
  Color color;
  static final Random _rand = Random();

  Asteroid(this.position, this.size, this.velocity, this.color) {
    int sides = _rand.nextInt(5) + 5;
    offsets = List.generate(sides, (_) => 0.7 + _rand.nextDouble() * 0.6);
  }

  factory Asteroid.fromOutside({Color color = Colors.deepPurpleAccent}) {
    final screenW = 400.0;
    final screenH = 700.0;
    int side = _rand.nextInt(4);
    late Offset pos;
    late Offset velocity;
    switch (side) {
      case 0:
        pos = Offset(-50, _rand.nextDouble() * screenH);
        velocity = Offset(2 + _rand.nextDouble() * 2, _rand.nextDouble() * 2 - 1);
        break;
      case 1:
        pos = Offset(screenW + 50, _rand.nextDouble() * screenH);
        velocity = Offset(-2 - _rand.nextDouble() * 2, _rand.nextDouble() * 2 - 1);
        break;
      case 2:
        pos = Offset(_rand.nextDouble() * screenW, -50);
        velocity = Offset(_rand.nextDouble() * 2 - 1, 2 + _rand.nextDouble() * 2);
        break;
      case 3:
      default:
        pos = Offset(_rand.nextDouble() * screenW, screenH + 50);
        velocity = Offset(_rand.nextDouble() * 2 - 1, -2 - _rand.nextDouble() * 2);
        break;
    }
    return Asteroid(pos, 40 + _rand.nextDouble() * 30, velocity, color);
  }

  void update() {
    position += velocity;
  }

  Asteroid split(Color newColor) {
    final angle = _rand.nextDouble() * 2 * pi;
    final velocity = Offset(cos(angle) * 2, sin(angle) * 2);
    return Asteroid(position, size / 2, velocity, newColor);
  }

  List<Offset> getVertices() {
    int sides = offsets.length;
    List<Offset> verts = [];
    for (int i = 0; i < sides; i++) {
      double angle = (2 * pi / sides) * i;
      double r = size * offsets[i];
      verts.add(Offset(position.dx + cos(angle) * r, position.dy + sin(angle) * r));
    }
    return verts;
  }

  Path getPath() {
    Path path = Path();
    final verts = getVertices();
    if (verts.isEmpty) return path;
    path.moveTo(verts[0].dx, verts[0].dy);
    for (int i = 1; i < verts.length; i++) path.lineTo(verts[i].dx, verts[i].dy);
    path.close();
    return path;
  }
}

// ===== HitParticle =====
class HitParticle {
  Offset position;
  Offset velocity;
  Color color;
  double life = 1.0;
  bool isDead = false;
  static final Random _rand = Random();

  HitParticle(this.position, this.color)
      : velocity = Offset(
            (_rand.nextDouble() - 0.5) * 6, (_rand.nextDouble() - 0.5) * 6);

  void update() {
    position += velocity;
    life -= 0.08; // fades faster as requested earlier
    if (life <= 0) isDead = true;
  }
}

// ===== Painter =====
class GamePainter extends CustomPainter {
  final Ship ship;
  final List<Asteroid> asteroids;
  final List<Bullet> bullets;
  final List<HitParticle> hitParticles;
  final bool gameOver;
  final int score;
  final int highScore;
  final bool invulnerable;
  final bool shipVisible;
  final double dareOpacity;

  GamePainter(
    this.ship,
    this.asteroids,
    this.bullets,
    this.hitParticles,
    this.gameOver,
    this.score,
    this.highScore,
    this.invulnerable,
    this.shipVisible,
    this.dareOpacity,
  );

  @override
  void paint(Canvas canvas, Size size) {
    // Paint objects
    final shipPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final bulletPaint = Paint()
      ..color = Colors.grey.shade800.withOpacity(0.3) // increased by 10%
      ..style = PaintingStyle.fill;
    final asteroidPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // HUD Score (center top) - grey and bold with opacity and extra top padding
    final hudStyle = TextStyle(
      color: const Color(0xFF666666).withOpacity(0.85),
      fontSize: 16,
      fontWeight: FontWeight.bold,
      fontFamily: 'DecimaMono',
    );
    final scorePainter = TextPainter(
      text: TextSpan(
        text: "Score: $score    High: $highScore",
        style: hudStyle,
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    scorePainter.layout(maxWidth: size.width);
    // a bit more top padding
    scorePainter.paint(canvas, Offset(size.width / 2 - scorePainter.width / 2, 28));

    // Developed by DareWorld fade bottom -- changed to light grey for visibility on white
    // if (dareOpacity > 0) {
    //   final devPainter = TextPainter(
    //     text: TextSpan(
    //       text: "Developed by DareWorld",
    //       style: TextStyle(
    //         color: const Color.fromARGB(255, 169, 169, 169).withOpacity(dareOpacity), // light grey
    //         fontSize: 18,
    //         fontFamily: 'DecimaMono',
    //       ),
    //     ),
    //     textAlign: TextAlign.center,
    //     textDirection: TextDirection.ltr,
    //   );
    //   devPainter.layout(maxWidth: size.width);
    //   devPainter.paint(canvas, Offset(size.width / 2 - devPainter.width / 2, size.height - 28));
    // }
    
          if (dareOpacity > 0) {
        final devPainter = TextPainter(
          text: TextSpan(
            text: "Developed by DareWorld 😎",
            style: TextStyle(
              color: const Color.fromARGB(255, 169, 169, 169).withOpacity(dareOpacity), // light grey
              fontSize: size.width * 0.045, // responsive font size (4.5% of width)
              fontFamily: 'DecimaMono',
              fontWeight: FontWeight.bold, // bold text
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        devPainter.layout(maxWidth: size.width);

        // Draw with bottom padding (2% of screen height)
        devPainter.paint(
          canvas,
          Offset(
            size.width / 2 - devPainter.width / 2,
            size.height - devPainter.height - (size.height * 0.02),
          ),
        );
      }


    // Draw ship (triangle). If invulnerable, blink visibility handled by state
    if (shipVisible) {
      canvas.drawPath(ship.getPath(), shipPaint);
    }

    // Draw bullets (slightly transparent)
    for (var b in bullets) {
      canvas.drawCircle(b.position, 3, bulletPaint);
    }

    // Draw asteroids (jagged polygons)
    for (var a in asteroids) {
      asteroidPaint.color = a.color;
      canvas.drawPath(a.getPath(), asteroidPaint);
    }

    // Draw hit particles
    for (var p in hitParticles) {
      final paint = Paint()
        ..color = p.color.withOpacity(p.life)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p.position, 3, paint);
    }

    // Game Over UI: dark grey title and play again below (use DecimaMono)
    if (gameOver) {
      final titlePainter = TextPainter(
        text: TextSpan(
          text: "Game Over",
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            fontFamily: 'DecimaMono',
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      titlePainter.layout(maxWidth: size.width);
      titlePainter.paint(canvas, Offset(size.width / 2 - titlePainter.width / 2, size.height / 2 - 70));

      // SLOW pulsing Play Again - compute small scale factor using time
      // slower frequency than before for gentle pulse
      final double t = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final double pulse = 1.0 + 0.08 * sin(t * 1.4); // slower frequency, slightly larger amplitude

      final playPainter = TextPainter(
        text: TextSpan(
          text: "Play Again",
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 20,
            fontWeight: FontWeight.normal,
            fontFamily: 'DecimaMono',
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      playPainter.layout(maxWidth: size.width);

      // center and scale
      canvas.save();
      final dx = size.width / 2;
      final dy = size.height / 2 - 20 + playPainter.height / 2;
      canvas.translate(dx, dy);
      canvas.scale(pulse, pulse);
      // draw at -width/2, -height/2 because we translated to center
      playPainter.paint(canvas, Offset(-playPainter.width / 2, -playPainter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
