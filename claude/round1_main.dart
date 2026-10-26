import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

void main() => runApp(const CandyApp());

class CandyApp extends StatelessWidget {
  const CandyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Candy Match',
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: const GamePage(),
    );
  }
}

const int kSize = 8;
const int kMoves = 30;

const List<List<Color>> kCandyColors = [
  [Color(0xFFFF5A7A), Color(0xFFC2185B)], // strawberry
  [Color(0xFFFFB74D), Color(0xFFE65100)], // orange
  [Color(0xFFFFF176), Color(0xFFF9A825)], // lemon
  [Color(0xFF81C784), Color(0xFF2E7D32)], // apple
  [Color(0xFF64B5F6), Color(0xFF1565C0)], // blueberry
  [Color(0xFFCE93D8), Color(0xFF6A1B9A)], // grape
];

class Candy {
  Candy(this.type) : id = _nextId++;
  static int _nextId = 0;
  final int id;
  final int type;
}

class Particle {
  Particle(this.pos, this.vel, this.color);
  Offset pos;
  Offset vel;
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
  Point<int>? _selected;
  int _score = 0;
  int _moves = kMoves;
  int _combo = 0;
  bool _busy = false;
  String? _comboText;
  late final Ticker _ticker;
  double _cell = 40;

  @override
  void initState() {
    super.initState();
    _newGame();
    _ticker = createTicker((_) => _tickParticles())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _newGame() {
    _board = List.generate(kSize, (_) => List.filled(kSize, null));
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
    _score = 0;
    _moves = kMoves;
    _selected = null;
    _busy = false;
  }

  void _tickParticles() {
    if (_particles.isEmpty) return;
    setState(() {
      for (final p in _particles) {
        p.pos += p.vel;
        p.vel = Offset(p.vel.dx * 0.96, p.vel.dy * 0.96 + 0.35);
        p.life -= 0.03;
      }
      _particles.removeWhere((p) => p.life <= 0);
    });
  }

  Set<Point<int>> _findMatches() {
    final matches = <Point<int>>{};
    for (var r = 0; r < kSize; r++) {
      var run = 1;
      for (var c = 1; c <= kSize; c++) {
        final same = c < kSize && _board[r][c] != null && _board[r][c - 1] != null && _board[r][c]!.type == _board[r][c - 1]!.type;
        if (same) {
          run++;
        } else {
          if (run >= 3) {
            for (var k = c - run; k < c; k++) {
              matches.add(Point(r, k));
            }
          }
          run = 1;
        }
      }
    }
    for (var c = 0; c < kSize; c++) {
      var run = 1;
      for (var r = 1; r <= kSize; r++) {
        final same = r < kSize && _board[r][c] != null && _board[r - 1][c] != null && _board[r][c]!.type == _board[r - 1][c]!.type;
        if (same) {
          run++;
        } else {
          if (run >= 3) {
            for (var k = r - run; k < r; k++) {
              matches.add(Point(k, c));
            }
          }
          run = 1;
        }
      }
    }
    return matches;
  }

  void _swap(Point<int> a, Point<int> b) {
    final t = _board[a.x][a.y];
    _board[a.x][a.y] = _board[b.x][b.y];
    _board[b.x][b.y] = t;
  }

  Future<void> _trySwap(Point<int> a, Point<int> b) async {
    if (_busy || _moves <= 0) return;
    if ((a.x - b.x).abs() + (a.y - b.y).abs() != 1) return;
    _busy = true;
    setState(() {
      _swap(a, b);
      _selected = null;
    });
    await Future.delayed(const Duration(milliseconds: 220));
    if (_findMatches().isEmpty) {
      setState(() => _swap(a, b));
      await Future.delayed(const Duration(milliseconds: 220));
      _busy = false;
      return;
    }
    setState(() => _moves--);
    _combo = 0;
    await _resolve();
    _busy = false;
    if (_moves <= 0 && mounted) setState(() {});
  }

  Future<void> _resolve() async {
    while (true) {
      final matches = _findMatches();
      if (matches.isEmpty) break;
      _combo++;
      setState(() {
        for (final p in matches) {
          final candy = _board[p.x][p.y]!;
          _popping.add(candy.id);
          _burst(p, kCandyColors[candy.type][0]);
        }
        _score += matches.length * 10 * _combo;
        if (_combo > 1) _comboText = 'Combo x$_combo!';
      });
      await Future.delayed(const Duration(milliseconds: 260));
      setState(() {
        for (final p in matches) {
          _popping.remove(_board[p.x][p.y]!.id);
          _board[p.x][p.y] = null;
        }
        _collapse();
      });
      await Future.delayed(const Duration(milliseconds: 320));
    }
    if (_comboText != null) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _comboText = null);
      });
    }
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

  void _burst(Point<int> p, Color color) {
    final center = Offset((p.y + 0.5) * _cell, (p.x + 0.5) * _cell);
    for (var i = 0; i < 8; i++) {
      final a = _rnd.nextDouble() * 2 * pi;
      final s = 2 + _rnd.nextDouble() * 4;
      _particles.add(Particle(center, Offset(cos(a) * s, sin(a) * s - 2), color));
    }
  }

  Offset? _dragStart;
  Point<int>? _dragCell;

  Point<int> _cellAt(Offset local) => Point((local.dy / _cell).floor().clamp(0, kSize - 1), (local.dx / _cell).floor().clamp(0, kSize - 1));

  @override
  Widget build(BuildContext context) {
    final gameOver = _moves <= 0 && !_busy;
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
              const SizedBox(height: 12),
              const Text('Candy Match',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(blurRadius: 12, color: Colors.black38)])),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _stat('SCORE', '$_score'),
                  const SizedBox(width: 16),
                  _stat('MOVES', '$_moves'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: LayoutBuilder(builder: (context, box) {
                    final side = min(box.maxWidth, box.maxHeight) - 24;
                    _cell = side / kSize;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: side + 12,
                          height: side + 12,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white54, width: 2),
                          ),
                        ),
                        SizedBox(
                          width: side,
                          height: side,
                          child: GestureDetector(
                            onPanStart: (d) {
                              _dragStart = d.localPosition;
                              _dragCell = _cellAt(d.localPosition);
                            },
                            onPanUpdate: (d) {
                              if (_dragStart == null || _dragCell == null) return;
                              final delta = d.localPosition - _dragStart!;
                              if (delta.distance > _cell * 0.4) {
                                final from = _dragCell!;
                                final to = delta.dx.abs() > delta.dy.abs()
                                    ? Point(from.x, from.y + (delta.dx > 0 ? 1 : -1))
                                    : Point(from.x + (delta.dy > 0 ? 1 : -1), from.y);
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
                              ],
                            ),
                          ),
                        ),
                        if (_comboText != null)
                          IgnorePointer(
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(_comboText),
                              tween: Tween(begin: 0.4, end: 1),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.elasticOut,
                              builder: (context, s, child) => Transform.scale(scale: s, child: child),
                              child: Text(_comboText!,
                                  style: const TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFFFEB3B),
                                      shadows: [Shadow(blurRadius: 16, color: Colors.deepPurple), Shadow(offset: Offset(2, 3), color: Colors.black45)])),
                            ),
                          ),
                        if (gameOver) _gameOver(),
                      ],
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

  Widget _candyWidget(Candy candy, int r, int c) {
    final popping = _popping.contains(candy.id);
    final selected = _selected == Point(r, c);
    final colors = kCandyColors[candy.type];
    return AnimatedPositioned(
      key: ValueKey(candy.id),
      duration: const Duration(milliseconds: 280),
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
              shape: candy.type.isEven ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: candy.type.isEven ? null : BorderRadius.circular(_cell * 0.25),
              gradient: RadialGradient(center: const Alignment(-0.35, -0.4), radius: 0.9, colors: colors),
              boxShadow: [
                BoxShadow(color: colors[1].withOpacity(0.6), blurRadius: selected ? 14 : 6, offset: const Offset(0, 3)),
              ],
              border: selected ? Border.all(color: Colors.white, width: 3) : null,
            ),
            child: Align(
              alignment: const Alignment(-0.4, -0.45),
              child: Container(
                width: _cell * 0.22,
                height: _cell * 0.14,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 2)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: Text(value, key: ValueKey(value), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _gameOver() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(blurRadius: 30, color: Colors.black38)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Game Over', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF7B2FF7))),
          const SizedBox(height: 8),
          Text('Score: $_score', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF107A3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              shape: const StadiumBorder(),
            ),
            onPressed: () => setState(_newGame),
            child: const Text('Play Again', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.particles);
  final List<Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      canvas.drawCircle(p.pos, 4 * p.life + 1, Paint()..color = p.color.withOpacity(p.life.clamp(0, 1)));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
