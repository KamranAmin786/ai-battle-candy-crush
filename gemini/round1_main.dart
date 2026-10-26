import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const CandyCrushApp());
}

class CandyCrushApp extends StatelessWidget {
  const CandyCrushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Candy Crush Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'sans-serif',
      ),
      home: const GameScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// MODELS & CONFIG
// -----------------------------------------------------------------------------

const int BOARD_SIZE = 8;
const int NUM_CANDY_TYPES = 6;
const int INITIAL_MOVES = 30;

enum CandyType {
  red,
  blue,
  green,
  yellow,
  purple,
  orange,
}

class Tile {
  final String id;
  CandyType type;
  int row;
  int col;
  bool isMatched;

  Tile({
    required this.id,
    required this.type,
    required this.row,
    required this.col,
    this.isMatched = false,
  });
}

class FloatingTextItem {
  final String id;
  final String text;
  final Offset position;
  final Color color;

  FloatingTextItem({
    required this.id,
    required this.text,
    required this.position,
    required this.color,
  });
}

// -----------------------------------------------------------------------------
// MAIN GAME SCREEN
// -----------------------------------------------------------------------------

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  final Random _random = Random();
  int _tileIdCounter = 0;

  // Board storage
  late List<List<Tile?>> _grid;
  final List<Tile> _allTiles = [];

  // Game state
  int _score = 0;
  int _movesLeft = INITIAL_MOVES;
  bool _isBusy = false;
  bool _isGameOver = false;

  // Selection state
  int? _selectedRow;
  int? _selectedCol;

  // Visual effects
  final List<FloatingTextItem> _floatingTexts = [];

  @override
  void initState() {
    super.initState();
    _startNewGame();
  }

  void _startNewGame() {
    setState(() {
      _score = 0;
      _movesLeft = INITIAL_MOVES;
      _isBusy = false;
      _isGameOver = false;
      _selectedRow = null;
      _selectedCol = null;
      _floatingTexts.clear();
      _allTiles.clear();
      _grid = List.generate(BOARD_SIZE, (_) => List.filled(BOARD_SIZE, null));

      _generateInitialBoard();
    });
  }

  // ---------------------------------------------------------------------------
  // BOARD GENERATION
  // ---------------------------------------------------------------------------

  void _generateInitialBoard() {
    for (int r = 0; r < BOARD_SIZE; r++) {
      for (int c = 0; c < BOARD_SIZE; c++) {
        CandyType type;
        do {
          type = CandyType.values[_random.nextInt(NUM_CANDY_TYPES)];
        } while (_createsInitialMatch(r, c, type));

        final tile = Tile(
          id: 'tile_${_tileIdCounter++}',
          type: type,
          row: r,
          col: c,
        );
        _grid[r][c] = tile;
        _allTiles.add(tile);
      }
    }
  }

  bool _createsInitialMatch(int r, int c, CandyType type) {
    if (c >= 2 &&
        _grid[r][c - 1]?.type == type &&
        _grid[r][c - 2]?.type == type) {
      return true;
    }
    if (r >= 2 &&
        _grid[r - 1][c]?.type == type &&
        _grid[r - 2][c]?.type == type) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // INPUT & SWAP HANDLING
  // ---------------------------------------------------------------------------

  void _onTileTap(int r, int c) {
    if (_isBusy || _isGameOver) return;

    if (_selectedRow == null || _selectedCol == null) {
      setState(() {
        _selectedRow = r;
        _selectedCol = c;
      });
    } else {
      int prevR = _selectedRow!;
      int prevC = _selectedCol!;

      if (prevR == r && prevC == c) {
        // Deselect
        setState(() {
          _selectedRow = null;
          _selectedCol = null;
        });
      } else if (_isAdjacent(prevR, prevC, r, c)) {
        setState(() {
          _selectedRow = null;
          _selectedCol = null;
        });
        _attemptSwap(prevR, prevC, r, c);
      } else {
        // Select new tile
        setState(() {
          _selectedRow = r;
          _selectedCol = c;
        });
      }
    }
  }

  void _onTileSwipe(int r, int c, Vector2D dir) {
    if (_isBusy || _isGameOver) return;

    int targetR = r + dir.dy;
    int targetC = c + dir.dx;

    if (targetR >= 0 &&
        targetR < BOARD_SIZE &&
        targetC >= 0 &&
        targetC < BOARD_SIZE) {
      setState(() {
        _selectedRow = null;
        _selectedCol = null;
      });
      _attemptSwap(r, c, targetR, targetC);
    }
  }

  bool _isAdjacent(int r1, int c1, int r2, int c2) {
    return (r1 == r2 && (c1 - c2).abs() == 1) ||
        (c1 == c2 && (r1 - r2).abs() == 1);
  }

  // ---------------------------------------------------------------------------
  // GAME CORE LOOP (ASYNC PIPELINE)
  // ---------------------------------------------------------------------------

  Future<void> _attemptSwap(int r1, int c1, int r2, int c2) async {
    _isBusy = true;

    // 1. Swap positions in data model
    _swapGridPositions(r1, c1, r2, c2);
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 250));

    // 2. Check for matches
    List<Point<int>> matches = _findMatches();

    if (matches.isEmpty) {
      // Revert swap if invalid
      _swapGridPositions(r1, c1, r2, c2);
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 250));
      _isBusy = false;
      return;
    }

    // Valid move!
    setState(() {
      _movesLeft--;
    });

    int comboCount = 1;

    // Cascade processing loop
    while (matches.isNotEmpty) {
      // Highlight & score matches
      _markMatches(matches);
      _addScore(matches, comboCount);
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 300));

      // Remove matched tiles
      _removeMatchedTiles();
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 100));

      // Gravity & Refill
      _applyGravityAndRefill();
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 350));

      // Check next cascade iteration
      matches = _findMatches();
      if (matches.isNotEmpty) {
        comboCount++;
      }
    }

    _isBusy = false;

    // Check Game Over condition
    if (_movesLeft <= 0) {
      setState(() {
        _isGameOver = true;
      });
    }
  }

  void _swapGridPositions(int r1, int c1, int r2, int c2) {
    Tile? t1 = _grid[r1][c1];
    Tile? t2 = _grid[r2][c2];

    if (t1 != null) {
      t1.row = r2;
      t1.col = c2;
    }
    if (t2 != null) {
      t2.row = r1;
      t2.col = c1;
    }

    _grid[r2][c2] = t1;
    _grid[r1][c1] = t2;
  }

  // ---------------------------------------------------------------------------
  // MATCH FINDING & SCORING
  // ---------------------------------------------------------------------------

  List<Point<int>> _findMatches() {
    Set<Point<int>> matchedPoints = {};

    // Horizontal matches
    for (int r = 0; r < BOARD_SIZE; r++) {
      for (int c = 0; c < BOARD_SIZE - 2; c++) {
        CandyType? type = _grid[r][c]?.type;
        if (type == null) continue;

        int matchLen = 1;
        while (c + matchLen < BOARD_SIZE &&
            _grid[r][c + matchLen]?.type == type) {
          matchLen++;
        }

        if (matchLen >= 3) {
          for (int i = 0; i < matchLen; i++) {
            matchedPoints.add(Point(r, c + i));
          }
        }
      }
    }

    // Vertical matches
    for (int c = 0; c < BOARD_SIZE; c++) {
      for (int r = 0; r < BOARD_SIZE - 2; r++) {
        CandyType? type = _grid[r][c]?.type;
        if (type == null) continue;

        int matchLen = 1;
        while (r + matchLen < BOARD_SIZE &&
            _grid[r + matchLen][c]?.type == type) {
          matchLen++;
        }

        if (matchLen >= 3) {
          for (int i = 0; i < matchLen; i++) {
            matchedPoints.add(Point(r + i, c));
          }
        }
      }
    }

    return matchedPoints.toList();
  }

  void _markMatches(List<Point<int>> matches) {
    for (var p in matches) {
      _grid[p.x][p.y]?.isMatched = true;
    }
  }

  void _removeMatchedTiles() {
    for (int r = 0; r < BOARD_SIZE; r++) {
      for (int c = 0; c < BOARD_SIZE; c++) {
        if (_grid[r][c]?.isMatched == true) {
          Tile? tile = _grid[r][c];
          if (tile != null) {
            _allTiles.remove(tile);
          }
          _grid[r][c] = null;
        }
      }
    }
  }

  void _addScore(List<Point<int>> matches, int combo) {
    int points = matches.length * 50 * combo;
    _score += points;

    // Find center of matches to spawn float text
    double avgR = 0;
    double avgC = 0;
    for (var p in matches) {
      avgR += p.x;
      avgC += p.y;
    }
    avgR /= matches.length;
    avgC /= matches.length;

    String text = "+$points";
    if (combo > 1) {
      text = "COMBO x$combo!\n+$points";
    }

    _spawnFloatingText(text, avgR, avgC, combo > 1 ? Colors.yellowAccent : Colors.white);
  }

  void _spawnFloatingText(String text, double row, double col, Color color) {
    final id = 'ft_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(1000)}';
    final item = FloatingTextItem(
      id: id,
      text: text,
      position: Offset(col, row),
      color: color,
    );

    setState(() {
      _floatingTexts.add(item);
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _floatingTexts.removeWhere((ft) => ft.id == id);
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // GRAVITY & REFILL
  // ---------------------------------------------------------------------------

  void _applyGravityAndRefill() {
    for (int c = 0; c < BOARD_SIZE; c++) {
      int emptyRow = BOARD_SIZE - 1;

      // Drop existing candies
      for (int r = BOARD_SIZE - 1; r >= 0; r--) {
        if (_grid[r][c] != null) {
          if (r != emptyRow) {
            Tile tile = _grid[r][c]!;
            tile.row = emptyRow;
            _grid[emptyRow][c] = tile;
            _grid[r][c] = null;
          }
          emptyRow--;
        }
      }

      // Fill remaining empty spots from above
      int newSpawnCount = emptyRow + 1;
      for (int r = emptyRow; r >= 0; r--) {
        CandyType type = CandyType.values[_random.nextInt(NUM_CANDY_TYPES)];

        Tile newTile = Tile(
          id: 'tile_${_tileIdCounter++}',
          type: type,
          row: r,
          col: c,
        );

        // Position it visually above the grid before sliding down
        newTile.row = r - newSpawnCount;
        _allTiles.add(newTile);

        // Instantly assign target position in logical grid
        _grid[r][c] = newTile;

        // Schedule visual slide in to actual target row
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              newTile.row = r;
            });
          }
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UI BUILDERS
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final boardWidth = min(screenSize.width - 32, 500.0);
    final tileSize = boardWidth / BOARD_SIZE;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF2C003E),
              Color(0xFF510A32),
              Color(0xFF801336),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 12),
                  _buildHeader(),
                  const Spacer(),
                  _buildBoard(boardWidth, tileSize),
                  const Spacer(),
                  _buildFooter(),
                  const SizedBox(height: 16),
                ],
              ),
              if (_isGameOver) _buildGameOverOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 10,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildScoreColumn("SCORE", "$_score", Icons.stars_rounded, Colors.amber),
            Container(height: 40, width: 2, color: Colors.white24),
            _buildScoreColumn("MOVES", "$_movesLeft", Icons.touch_app_rounded, Colors.cyanAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreColumn(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.extrabold,
            fontSize: 26,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 2)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBoard(double boardWidth, double tileSize) {
    return Container(
      width: boardWidth,
      height: boardWidth,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 15,
            spreadRadius: 2,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: [
            // Background Grid Slots
            ...List.generate(BOARD_SIZE * BOARD_SIZE, (index) {
              int r = index ~/ BOARD_SIZE;
              int c = index % BOARD_SIZE;
              bool isEven = (r + c) % 2 == 0;
              return Positioned(
                left: c * tileSize,
                top: r * tileSize,
                width: tileSize,
                height: tileSize,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isEven
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }),

            // Animated Candies
            ..._allTiles.map((tile) {
              final isSelected =
                  _selectedRow == tile.row && _selectedCol == tile.col;

              return AnimatedPositioned(
                key: ValueKey(tile.id),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutBack,
                left: tile.col * tileSize,
                top: tile.row * tileSize,
                width: tileSize,
                height: tileSize,
                child: GestureDetector(
                  onTap: () => _onTileTap(tile.row, tile.col),
                  onPanEnd: (details) {
                    final velocity = details.velocity.pixelsPerSecond;
                    if (velocity.distance < 100) return;

                    if (velocity.dx.abs() > velocity.dy.abs()) {
                      // Horizontal swipe
                      if (velocity.dx > 0) {
                        _onTileSwipe(tile.row, tile.col, Vector2D(1, 0));
                      } else {
                        _onTileSwipe(tile.row, tile.col, Vector2D(-1, 0));
                      }
                    } else {
                      // Vertical swipe
                      if (velocity.dy > 0) {
                        _onTileSwipe(tile.row, tile.col, Vector2D(0, 1));
                      } else {
                        _onTileSwipe(tile.row, tile.col, Vector2D(0, -1));
                      }
                    }
                  },
                  child: AnimatedScale(
                    scale: tile.isMatched ? 0.0 : (isSelected ? 1.15 : 1.0),
                    duration: const Duration(milliseconds: 200),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: CandyWidget(
                        type: tile.type,
                        isSelected: isSelected,
                      ),
                    ),
                  ),
                ),
              );
            }),

            // Floating Text Layer
            ..._floatingTexts.map((ft) {
              return AnimatedPositioned(
                key: ValueKey(ft.id),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                left: ft.position.dx * tileSize,
                top: (ft.position.dy - 0.8) * tileSize,
                child: IgnorePointer(
                  child: Material(
                    color: Colors.transparent,
                    child: Text(
                      ft.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ft.color,
                        fontWeight: FontWeight.extrabold,
                        fontSize: 20,
                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 6,
                            offset: Offset(2, 2),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: _startNewGame,
        icon: const Icon(Icons.refresh_rounded, size: 22),
        label: const Text(
          "RESTART GAME",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE91E63),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 6,
          shadowColor: Colors.pinkAccent,
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4A154B), Color(0xFF571845)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.amber, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.amberAccent,
                blurRadius: 20,
                spreadRadius: 1,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Colors.amber,
                size: 72,
              ),
              const SizedBox(height: 12),
              const Text(
                "GAME OVER",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.extrabold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Final Score",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "$_score",
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.black,
                  color: Colors.amberAccent,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _startNewGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 8,
                ),
                child: const Text(
                  "PLAY AGAIN",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HELPER STRUCTURES & CANDY GRAPHICS
// -----------------------------------------------------------------------------

class Vector2D {
  final int dx;
  final int dy;
  Vector2D(this.dx, this.dy);
}

class CandyWidget extends StatelessWidget {
  final CandyType type;
  final bool isSelected;

  const CandyWidget({
    super.key,
    required this.type,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isSelected
            ? Border.all(color: Colors.white, width: 3)
            : null,
        boxShadow: [
          BoxShadow(
            color: _getCandyColor(type).withOpacity(0.5),
            blurRadius: isSelected ? 12 : 6,
            spreadRadius: isSelected ? 2 : 1,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: CustomPaint(
        painter: _CandyPainter(type: type),
      ),
    );
  }

  Color _getCandyColor(CandyType type) {
    switch (type) {
      case CandyType.red:
        return const Color(0xFFFF2A55);
      case CandyType.blue:
        return const Color(0xFF00B0FF);
      case CandyType.green:
        return const Color(0xFF00E676);
      case CandyType.yellow:
        return const Color(0xFFFFD600);
      case CandyType.purple:
        return const Color(0xFFAA00FF);
      case CandyType.orange:
        return const Color(0xFFFF6D00);
    }
  }
}

class _CandyPainter extends CustomPainter {
  final CandyType type;

  _CandyPainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    final paint = Paint()..style = PaintingStyle.fill;
    final shinePaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..style = PaintingStyle.fill;

    switch (type) {
      case CandyType.red:
        // Sphere with Radial Gradient
        paint.shader = RadialGradient(
          colors: const [Color(0xFFFF758C), Color(0xFFFF7E5F), Color(0xFFB721FF)],
          center: const Alignment(-0.3, -0.3),
          radius: 0.9,
        ).createShader(Rect.fromCircle(center: center, radius: radius));
        canvas.drawCircle(center, radius, paint);
        // Highlight shine
        canvas.drawCircle(
            Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
            radius * 0.25,
            shinePaint);
        break;

      case CandyType.blue:
        // Diamond Gem
        paint.shader = const LinearGradient(
          colors: [Color(0xFF80E5FF), Color(0xFF0072FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

        final path = Path()
          ..moveTo(center.dx, center.dy - radius)
          ..lineTo(center.dx + radius, center.dy)
          ..lineTo(center.dx, center.dy + radius)
          ..lineTo(center.dx - radius, center.dy)
          ..close();
        canvas.drawPath(path, paint);

        final shinePath = Path()
          ..moveTo(center.dx, center.dy - radius)
          ..lineTo(center.dx + radius * 0.4, center.dy)
          ..lineTo(center.dx, center.dy - radius * 0.2)
          ..lineTo(center.dx - radius * 0.4, center.dy)
          ..close();
        canvas.drawPath(shinePath, shinePaint);
        break;

      case CandyType.green:
        // Rounded Rect / Capsule Jelly
        paint.shader = const LinearGradient(
          colors: [Color(0xFFA8FF78), Color(0xFF78FFD6)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

        final rrect = RRect.fromRectAndRadius(
          Rect.fromCircle(center: center, radius: radius * 0.9),
          Radius.circular(radius * 0.4),
        );
        canvas.drawRRect(rrect, paint);

        canvas.drawOval(
          Rect.fromLTWH(center.dx - radius * 0.4, center.dy - radius * 0.6,
              radius * 0.8, radius * 0.3),
          shinePaint,
        );
        break;

      case CandyType.yellow:
        // Star Candy
        paint.shader = const RadialGradient(
          colors: [Color(0xFFFFF176), Color(0xFFF57F17)],
          center: Alignment(0, -0.2),
        ).createShader(Rect.fromCircle(center: center, radius: radius));

        final path = Path();
        int points = 5;
        double outerRadius = radius;
        double innerRadius = radius * 0.5;
        double angle = -pi / 2;
        double step = pi / points;

        for (int i = 0; i < points * 2; i++) {
          double r = (i % 2 == 0) ? outerRadius : innerRadius;
          double x = center.dx + cos(angle) * r;
          double y = center.dy + sin(angle) * r;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
          angle += step;
        }
        path.close();
        canvas.drawPath(path, paint);
        canvas.drawCircle(center, radius * 0.25, shinePaint);
        break;

      case CandyType.purple:
        // Hexagon Candy
        paint.shader = const LinearGradient(
          colors: [Color(0xFFE100FF), Color(0xFF7F00FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

        final path = Path();
        for (int i = 0; i < 6; i++) {
          double a = (i * 60) * pi / 180;
          double x = center.dx + radius * cos(a);
          double y = center.dy + radius * sin(a);
          if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
        }
        path.close();
        canvas.drawPath(path, paint);

        canvas.drawCircle(
          Offset(center.dx - radius * 0.2, center.dy - radius * 0.3),
          radius * 0.2,
          shinePaint,
        );
        break;

      case CandyType.orange:
        // Rounded Square Slice
        paint.shader = const RadialGradient(
          colors: [Color(0xFFFFB74D), Color(0xFFE65100)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

        final rrect = RRect.fromRectAndRadius(
          Rect.fromRectExtent(center, radius * 1.6, radius * 1.6),
          Radius.circular(radius * 0.35),
        );
        canvas.drawRRect(rrect, paint);

        canvas.drawCircle(
            Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
            radius * 0.2,
            shinePaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CandyPainter oldDelegate) =>
      oldDelegate.type != type;
}
