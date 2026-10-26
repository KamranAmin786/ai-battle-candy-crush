import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(const CandyApp());

class CandyApp extends StatelessWidget {
  const CandyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Candy Match',
      theme: ThemeData(useMaterial3: true),
      home: const GamePage(),
    );
  }
}

const int kSize = 8;
const int kMoves = 30;

const List<List<Color>> kCandyColors = [
  [Color(0xFFFF6B8B), Color(0xFFC2185B)], // strawberry
  [Color(0xFFFFB74D), Color(0xFFE65100)], // orange
  [Color(0xFFFFF176), Color(0xFFF9A825)], // lemon
  [Color(0xFF8BE08F), Color(0xFF2E7D32)], // apple
  [Color(0xFF6EC1FF), Color(0xFF1565C0)], // blueberry
  [Color(0xFFD9A3E8), Color(0xFF6A1B9A)], // grape
];

enum Special { none, stripedH, stripedV, bomb }

class Candy {
  Candy(this.type, [this.special = Special.none]) : id = _nextId++;
  static int _nextId = 0;
  final int id;
  final int type;
  Special special;
}

class Particle {
  Particle(this.pos, this.vel, this.color, this.size, this.star);
  Offset pos;
  Offset vel;
  final Color color;
  final double size;
  final bool star;
  double life = 1;
  double spin = 0;
}

class FloatText {
  FloatText(this.text, this.pos, this.color);
  final String text;
  Offset pos;
  final Color color;
  double life = 1;
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  final _rnd = Random();
  late List<List<Candy?>> _board;
  final Set<int> _popping = {};
  final List<Particle> _particles = [];
  final List<FloatText> _floats = [];
  Point<int>? _selected;
  int _score = 0;
  int _moves = kMoves;
  int _level = 1;
  int _combo = 0;
  bool _busy = false;
  bool _won = false;
  String? _comboText;
  int _comboKey = 0;
  late final Ticker _ticker;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  double _cell = 40;

  int get _target => 1500 + (_level - 1) * 1000;

  @override
  void initState() {
    super.initState();
    _newGame();
    _ticker = createTicker((_) => _tick())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _newGame({bool nextLevel = false}) {
    _board = List.generate(kSize, (_) => List<Candy?>.filled(kSize, null));
    for (var r = 0; r < kSize; r++) {
      for (var c = 0; c < kSize; c++) {
        int t;
        do {
          t = _rnd.nextInt(kCandyColors.length);
        } while ((c >= 2 && _board[r][c - 1]!.type == t && _board[r][c - 2]!.type == t) ||
            (r >= 2 && _board[r - 1][c]!.type == t && _board[r - 2][c]!.type == t));
        _board[r][c] = Candy(t);
      }
    }
    if (nextLevel) {
      _level++;
    } else {
      _level = 1;
    }
    _score = 0;
    _moves = kMoves;
    _selected = null;
    _busy = false;
    _won = false;
  }

  void _tick() {
    if (_particles.isEmpty && _floats.isEmpty) return;
    setState(() {
      for (final p in _particles) {
        p.pos += p.vel;
        p.vel = Offset(p.vel.dx * 0.95, p.vel.dy * 0.95 + 0.32);
        p.life -= 0.025;
        p.spin += 0.2;
      }
      _particles.removeWhere((p) => p.life <= 0);
      for (final f in _floats) {
        f.pos += const Offset(0, -1.2);
        f.life -= 0.02;
      }
      _floats.removeWhere((f) => f.life <= 0);
    });
  }

  /// Finds every run of 3+ and returns the cells plus where specials should be created.
  (Set<Point<int>>, Map<Point<int>, Candy>) _findMatches(Point<int>? swapA, Point<int>? swapB) {
    final matches = <Point<int>>{};
    final created = <Point<int>, Candy>{};

    void handleRun(List<Point<int>> run, bool horizontal) {
      if (run.length < 3) return;
      matches.addAll(run);
      if (run.length >= 4) {
        final type = _board[run.first.x][run.first.y]!.type;
        final spot = run.contains(swapA) ? swapA! : (run.contains(swapB) ? swapB! : run[run.length ~/ 2]);
        created[spot] = run.length >= 5 ? Candy(type, Special.bomb) : Candy(type, horizontal ? Special.stripedV : Special.stripedH);
      }
    }

    for (var r = 0; r < kSize; r++) {
      var run = <Point<int>>[Point(r, 0)];
      for (var c = 1; c <= kSize; c++) {
        final same = c < kSize && _board[r][c] != null && _board[r][c - 1] != null && _board[r][c]!.type == _board[r][c - 1]!.type;
        if (same) {
          run.add(Point(r, c));
        } else {
          handleRun(run, true);
          if (c < kSize) run = [Point(r, c)];
        }
      }
    }
    for (var c = 0; c < kSize; c++) {
      var run = <Point<int>>[Point(0, c)];
      for (var r = 1; r <= kSize; r++) {
        final same = r < kSize && _board[r][c] != null && _board[r - 1][c] != null && _board[r][c]!.type == _board[r - 1][c]!.type;
        if (same) {
          run.add(Point(r, c));
        } else {
          handleRun(run, false);
          if (r < kSize) run = [Point(r, c)];
        }
      }
    }
    return (matches, created);
  }

  /// Adds the cells cleared by any special candies inside [cells], chaining specials.
  Set<Point<int>> _expandSpecials(Set<Point<int>> cells, {int? bombColor}) {
    final result = {...cells};
    final queue = [...cells];
    while (queue.isNotEmpty) {
      final p = queue.removeLast();
      final candy = _board[p.x][p.y];
      if (candy == null) continue;
      final extra = <Point<int>>[];
      switch (candy.special) {
        case Special.stripedH:
          for (var c = 0; c < kSize; c++) {
            extra.add(Point(p.x, c));
          }
        case Special.stripedV:
          for (var r = 0; r < kSize; r++) {
            extra.add(Point(r, p.y));
          }
        case Special.bomb:
          final color = bombColor ?? candy.type;
          for (var r = 0; r < kSize; r++) {
            for (var c = 0; c < kSize; c++) {
              if (_board[r][c]?.type == color) extra.add(Point(r, c));
            }
          }
        case Special.none:
          break;
      }
      for (final e in extra) {
        if (result.add(e)) queue.add(e);
      }
    }
    return result;
  }

  void _swap(Point<int> a, Point<int> b) {
    final t = _board[a.x][a.y];
    _board[a.x][a.y] = _board[b.x][b.y];
    _board[b.x][b.y] = t;
  }

  Future<void> _trySwap(Point<int> a, Point<int> b) async {
    if (_busy || _moves <= 0 || _won) return;
    if ((a.x - b.x).abs() + (a.y - b.y).abs() != 1) return;
    _busy = true;
    setState(() {
      _swap(a, b);
      _selected = null;
    });
    await Future.delayed(const Duration(milliseconds: 220));

    // A color bomb swapped with any candy clears every candy of that color.
    final ca = _board[a.x][a.y]!, cb = _board[b.x][b.y]!;
    if (ca.special == Special.bomb || cb.special == Special.bomb) {
      final bombAt = ca.special == Special.bomb ? a : b;
      final other = ca.special == Special.bomb ? cb : ca;
      setState(() => _moves--);
      _combo = 0;
      await _clear(_expandSpecials({bombAt}, bombColor: other.type)..add(bombAt), {});
      await _resolve(null, null);
      _finishTurn();
      return;
    }

    final (matches, _) = _findMatches(a, b);
    if (matches.isEmpty) {
      setState(() => _swap(a, b));
      _shake.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 220));
      _busy = false;
      return;
    }
    setState(() => _moves--);
    _combo = 0;
    await _resolve(a, b);
    _finishTurn();
  }

  void _finishTurn() {
    _busy = false;
    if (!mounted) return;
    setState(() {
      if (_score >= _target) _won = true;
    });
  }

  Future<void> _resolve(Point<int>? a, Point<int>? b) async {
    var first = true;
    while (true) {
      final (matches, created) = _findMatches(first ? a : null, first ? b : null);
      first = false;
      if (matches.isEmpty) break;
      await _clear(_expandSpecials(matches), created);
    }
  }

  Future<void> _clear(Set<Point<int>> cells, Map<Point<int>, Candy> created) async {
    _combo++;
    final gained = cells.length * 10 * _combo;
    setState(() {
      for (final p in cells) {
        final candy = _board[p.x][p.y];
        if (candy == null) continue;
        _popping.add(candy.id);
        _burst(p, kCandyColors[candy.type][0], candy.special != Special.none);
      }
      _score += gained;
      final center = cells.fold(Offset.zero, (s, p) => s + Offset((p.y + 0.5) * _cell, (p.x + 0.5) * _cell)) / cells.length.toDouble();
      _floats.add(FloatText('+$gained', center, Colors.white));
      if (_combo >= 2) {
        _comboText = const ['', '', 'Sweet!', 'Tasty!', 'Delicious!', 'Divine!'][min(_combo, 5)];
        _comboKey++;
      }
      if (cells.length >= 8) _shake.forward(from: 0);
    });
    await Future.delayed(const Duration(milliseconds: 260));
    setState(() {
      for (final p in cells) {
        final candy = _board[p.x][p.y];
        if (candy != null) _popping.remove(candy.id);
        _board[p.x][p.y] = null;
      }
      created.forEach((p, candy) => _board[p.x][p.y] = candy);
      _collapse();
    });
    await Future.delayed(const Duration(milliseconds: 340));
    final key = _comboKey;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && key == _comboKey) setState(() => _comboText = null);
    });
  }

  void _collapse() {
    for (var c = 0; c < kSize; c++) {
      var write = kSize - 1;
      for (var r = kSize - 1; r >= 0; r--) {
        if (_board[r][c] != null) {
          _board[write][c] = _board[r][c];
          if (write != r) _board[r][c] = null;
          write--;
        }
      }
      for (var r = write; r >= 0; r--) {
        _board[r][c] = Candy(_rnd.nextInt(kCandyColors.length));
      }
    }
  }

  void _burst(Point<int> p, Color color, bool big) {
    final center = Offset((p.y + 0.5) * _cell, (p.x + 0.5) * _cell);
    final n = big ? 18 : 9;
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * 2 * pi;
      final s = 2 + _rnd.nextDouble() * (big ? 7 : 4);
      _particles.add(Particle(center, Offset(cos(a) * s, sin(a) * s - 2.5), i.isEven ? color : Colors.white, 3 + _rnd.nextDouble() * 4, i % 3 == 0));
    }
  }

  Offset? _dragStart;
  Point<int>? _dragCell;

  Point<int> _cellAt(Offset local) => Point((local.dy / _cell).floor().clamp(0, kSize - 1), (local.dx / _cell).floor().clamp(0, kSize - 1));

  @override
  Widget build(BuildContext context) {
    final gameOver = _moves <= 0 && !_busy && !_won;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text('Candy Match',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(blurRadius: 12, color: Colors.black38)])),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _stat('LEVEL', '$_level'),
                  const SizedBox(width: 10),
                  _stat('SCORE', '$_score'),
                  const SizedBox(width: 10),
                  _stat('MOVES', '$_moves'),
                ],
              ),
              const SizedBox(height: 12),
              _targetBar(),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: LayoutBuilder(builder: (context, box) {
                    final side = min(box.maxWidth, box.maxHeight) - 24;
                    _cell = side / kSize;
                    return AnimatedBuilder(
                      animation: _shake,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(sin(_shake.value * pi * 6) * 6 * (1 - _shake.value), 0),
                        child: child,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: side + 12,
                            height: side + 12,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.white54, width: 2),
                            ),
                          ),
                          SizedBox(width: side, height: side, child: _boardView()),
                          if (_comboText != null)
                            IgnorePointer(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(_comboKey),
                                tween: Tween(begin: 0.3, end: 1),
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.elasticOut,
                                builder: (context, s, child) => Transform.rotate(angle: -0.08, child: Transform.scale(scale: s, child: child)),
                                child: Text(_comboText!,
                                    style: const TextStyle(
                                        fontSize: 52,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFFFEB3B),
                                        shadows: [Shadow(blurRadius: 18, color: Color(0xFFFF4081)), Shadow(offset: Offset(3, 4), color: Colors.black45)])),
                              ),
                            ),
                          if (gameOver) _panel('Out of Moves', 'Score: $_score', 'Try Again', () => setState(_newGame)),
                          if (_won) _panel('Level $_level Complete!', 'Score: $_score', 'Next Level', () => setState(() => _newGame(nextLevel: true))),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardView() {
    return GestureDetector(
      onPanStart: (d) {
        _dragStart = d.localPosition;
        _dragCell = _cellAt(d.localPosition);
      },
      onPanUpdate: (d) {
        if (_dragStart == null || _dragCell == null) return;
        final delta = d.localPosition - _dragStart!;
        if (delta.distance > _cell * 0.4) {
          final from = _dragCell!;
          final to = delta.dx.abs() > delta.dy.abs() ? Point(from.x, from.y + (delta.dx > 0 ? 1 : -1)) : Point(from.x + (delta.dy > 0 ? 1 : -1), from.y);
          _dragStart = null;
          if (to.x >= 0 && to.x < kSize && to.y >= 0 && to.y < kSize) _trySwap(from, to);
        }
      },
      onTapUp: (d) {
        final p = _cellAt(d.localPosition);
        if (_selected == null) {
          setState(() => _selected = p);
        } else if (_selected == p) {
          setState(() => _selected = null);
        } else {
          final s = _selected!;
          if ((s.x - p.x).abs() + (s.y - p.y).abs() == 1) {
            _trySwap(s, p);
          } else {
            setState(() => _selected = p);
          }
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var r = 0; r < kSize; r++)
            for (var c = 0; c < kSize; c++)
              if (_board[r][c] != null) _candyWidget(_board[r][c]!, r, c),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ParticlePainter(_particles)))),
          for (final f in _floats)
            Positioned(
              left: f.pos.dx - 40,
              top: f.pos.dy - 16,
              width: 80,
              child: IgnorePointer(
                child: Opacity(
                  opacity: f.life.clamp(0, 1),
                  child: Text(f.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(blurRadius: 6, color: Colors.black54)])),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _candyWidget(Candy candy, int r, int c) {
    final popping = _popping.contains(candy.id);
    final selected = _selected == Point(r, c);
    final colors = candy.special == Special.bomb ? const [Color(0xFF5D4037), Color(0xFF212121)] : kCandyColors[candy.type];
    return AnimatedPositioned(
      key: ValueKey(candy.id),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      left: c * _cell,
      top: r * _cell,
      width: _cell,
      height: _cell,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        builder: (context, appear, child) => AnimatedScale(
          scale: popping ? 0 : (selected ? 1.15 : appear),
          duration: Duration(milliseconds: popping ? 240 : 150),
          child: child,
        ),
        child: Padding(
          padding: EdgeInsets.all(_cell * 0.08),
          child: Container(
            decoration: BoxDecoration(
              shape: candy.type.isEven || candy.special == Special.bomb ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: candy.type.isEven || candy.special == Special.bomb ? null : BorderRadius.circular(_cell * 0.25),
              gradient: RadialGradient(center: const Alignment(-0.35, -0.4), radius: 0.9, colors: colors),
              boxShadow: [
                BoxShadow(color: colors[1].withValues(alpha: 0.6), blurRadius: selected ? 14 : 6, offset: const Offset(0, 3)),
                if (candy.special != Special.none) const BoxShadow(color: Colors.white70, blurRadius: 10),
              ],
              border: selected ? Border.all(color: Colors.white, width: 3) : null,
            ),
            child: CustomPaint(
              painter: _SpecialPainter(candy.special),
              child: Align(
                alignment: const Alignment(-0.4, -0.45),
                child: Container(
                  width: _cell * 0.22,
                  height: _cell * 0.14,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _targetBar() {
    final progress = (_score / _target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TARGET', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 12)),
              Text('$_score / $_target', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 14,
              color: Colors.white24,
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFFEB3B), Color(0xFFFF9800)])),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 2, fontSize: 12)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: Text(value, key: ValueKey(value), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _panel(String title, String subtitle, String button, VoidCallback onTap) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(blurRadius: 30, color: Colors.black38)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF7B2FF7))),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF107A3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                shape: const StadiumBorder(),
              ),
              onPressed: onTap,
              child: Text(button, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecialPainter extends CustomPainter {
  _SpecialPainter(this.special);
  final Special special;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;
    switch (special) {
      case Special.stripedH:
        for (final y in [0.35, 0.5, 0.65]) {
          canvas.drawLine(Offset(size.width * 0.2, size.height * y), Offset(size.width * 0.8, size.height * y), paint);
        }
      case Special.stripedV:
        for (final x in [0.35, 0.5, 0.65]) {
          canvas.drawLine(Offset(size.width * x, size.height * 0.2), Offset(size.width * x, size.height * 0.8), paint);
        }
      case Special.bomb:
        final rnd = Random(7);
        for (var i = 0; i < 14; i++) {
          final a = rnd.nextDouble() * 2 * pi;
          final d = rnd.nextDouble() * size.width * 0.3;
          canvas.drawCircle(size.center(Offset(cos(a) * d, sin(a) * d)), size.width * 0.05, Paint()..color = kCandyColors[i % kCandyColors.length][0]);
        }
      case Special.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_SpecialPainter old) => old.special != special;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.particles);
  final List<Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()..color = p.color.withValues(alpha: p.life.clamp(0, 1));
      final s = p.size * p.life + 1;
      if (p.star) {
        canvas.save();
        canvas.translate(p.pos.dx, p.pos.dy);
        canvas.rotate(p.spin);
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? s : s * 0.45;
          final a = i * pi / 5;
          if (i == 0) {
            path.moveTo(cos(a) * r, sin(a) * r);
          } else {
            path.lineTo(cos(a) * r, sin(a) * r);
          }
        }
        canvas.drawPath(path..close(), paint);
        canvas.restore();
      } else {
        canvas.drawCircle(p.pos, s, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
