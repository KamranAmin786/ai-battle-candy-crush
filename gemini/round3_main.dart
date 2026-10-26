import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
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
      title: 'Candy Crush Deluxe',
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
const int TARGET_SCORE = 5000;

enum CandyType { red, blue, green, yellow, purple, orange }

enum SpecialType { none, stripedH, stripedV, wrapped, colorBomb }

class Tile {
  final String id;
  CandyType type;
  SpecialType special;
  int row;
  int col;
  bool isMatched;

  Tile({
    required this.id,
    required this.type,
    this.special = SpecialType.none,
    required this.row,
    required this.col,
    this.isMatched = false,
  });
}

class Particle {
  double x;
  double y;
  double vx;
  double vy;
  Color color;
  double size;
  double life; // 1.0 to 0.0
  double maxLife;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.maxLife,
  }) : life = maxLife;
}

class ComboBanner {
  final String id;
  final String text;
  final Color color;

  ComboBanner({
    required this.id,
    required this.text,
    required this.color,
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

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
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
  bool _isWin = false;

  // Selection state
  int? _selectedRow;
  int? _selectedCol;

  // VFX State
  final List<FloatingTextItem> _floatingTexts = [];
  final List<Particle> _particles = [];
  ComboBanner? _currentComboBanner;
  late AnimationController _particleController;

  @override
  void initState() {
    super.initState();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateParticles);
    _particleController.repeat();

    _startNewGame();
  }

  @override
  void dispose() {
    _particleController.dispose();
    super.dispose();
  }

  void _startNewGame() {
    setState(() {
      _score = 0;
      _movesLeft = INITIAL_MOVES;
      _isBusy = false;
      _isGameOver = false;
      _isWin = false;
      _selectedRow = null;
      _selectedCol = null;
      _floatingTexts.clear();
      _particles.clear();
      _currentComboBanner = null;
      _allTiles.clear();
      _grid = List.generate(BOARD_SIZE, (_) => List.filled(BOARD_SIZE, null));

      _generateInitialBoard();
    });
  }

  void _updateParticles() {
    if (_particles.isEmpty) return;
    setState(() {
      for (int i = _particles.length - 1; i >= 0; i--) {
        pUpdate(_particles[i]);
        if (_particles[i].life <= 0) {
          _particles.removeAt(i);
        }
      }
    });
  }

  void pUpdate(Particle p) {
    p.x += p.vx;
    p.y += p.vy;
    p.vy += 0.18; // gravity on particles
    p.life -= 0.04;
  }

  void _spawnPopParticles(double col, double row, Color color) {
    for (int i = 0; i < 12; i++) {
      double angle = _random.nextDouble() * 2 * pi;
      double speed = 1.5 + _random.nextDouble() * 4.5;
      _particles.add(Particle(
        x: col,
        y: row,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        color: color,
        size: 4 + _random.nextDouble() * 6,
        maxLife: 1.0,
      ));
    }
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
  // USER INPUT
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
  // CORE GAME LOOP & SPECIAL CANDIES logic
  // ---------------------------------------------------------------------------

  Future<void> _attemptSwap(int r1, int c1, int r2, int c2) async {
    _isBusy = true;

    Tile? t1 = _grid[r1][c1];
    Tile? t2 = _grid[r2][c2];

    if (t1 == null || t2 == null) {
      _isBusy = false;
      return;
    }

    // 1. Swap positions visually & logic
    _swapGridPositions(r1, c1, r2, c2);
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 250));

    // Handle Color Bomb swap special case
    if (t1.special == SpecialType.colorBomb || t2.special == SpecialType.colorBomb) {
      setState(() {
        _movesLeft--;
      });
      await _triggerColorBombSwap(t1, t2);
      await _runCascadeLoop();
      _isBusy = false;
      _checkGameEnd();
      return;
    }

    // 2. Check for normal matches
    List<MatchGroup> matchGroups = _findMatchGroups();

    if (matchGroups.isEmpty) {
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

    await _processMatchesAndCascade(matchGroups, swappedRow: r2, swappedCol: c2);

    _isBusy = false;
    _checkGameEnd();
  }

  Future<void> _triggerColorBombSwap(Tile t1, Tile t2) async {
    Tile colorBombTile = (t1.special == SpecialType.colorBomb) ? t1 : t2;
    Tile targetTile = (t1.special == SpecialType.colorBomb) ? t2 : t1;

    CandyType targetColor = targetTile.type;

    // Destroy color bomb & all target color tiles
    colorBombTile.isMatched = true;
    for (int r = 0; r < BOARD_SIZE; r++) {
      for (int c = 0; c < BOARD_SIZE; c++) {
        if (_grid[r][c]?.type == targetColor) {
          _grid[r][c]?.isMatched = true;
        }
      }
    }

    _showComboBanner("COLOR BLAST!", Colors.pinkAccent);
    _score += 1000;
    _spawnFloatingText("+1000", targetTile.col.toDouble(), targetTile.row.toDouble(), Colors.pinkAccent);

    setState(() {});
    await Future.delayed(const Duration(milliseconds: 300));
    _popMatchedTiles();
    await Future.delayed(const Duration(milliseconds: 150));
    _applyGravityAndRefill();
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _runCascadeLoop() async {
    int combo = 1;
    while (true) {
      List<MatchGroup> matchGroups = _findMatchGroups();
      if (matchGroups.isEmpty) break;

      combo++;
      await _processMatchesAndCascade(matchGroups, comboCount: combo);
    }
  }

  Future<void> _processMatchesAndCascade(List<MatchGroup> matchGroups,
      {int? swappedRow, int? swappedCol, int comboCount = 1}) async {
    int currentCombo = comboCount;

    while (matchGroups.isNotEmpty) {
      // Trigger special creations & special candy expansions
      _processSpecialCreations(matchGroups, swappedRow, swappedCol);
      _expandSpecialExplosions();

      // Collect points & particles
      List<Point<int>> matchedPoints = [];
      for (int r = 0; r < BOARD_SIZE; r++) {
        for (int c = 0; c < BOARD_SIZE; c++) {
          if (_grid[r][c]?.isMatched == true) {
            matchedPoints.add(Point(r, c));
          }
        }
      }

      if (matchedPoints.isEmpty) break;

      _addScoreAndEffects(matchedPoints, currentCombo);

      setState(() {});
      await Future.delayed(const Duration(milliseconds: 320));

      // Pop tiles with particles
      _popMatchedTiles();
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 120));

      // Apply Gravity
      _applyGravityAndRefill();
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 350));

      // Reset swap coordinates after first pass
      swappedRow = null;
      swappedCol = null;

      // Find next cascade matches
      matchGroups = _findMatchGroups();
      if (matchGroups.isNotEmpty) {
        currentCombo++;
      }
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
  // MATCH DETECTION & SPECIAL CANDY CREATION
  // ---------------------------------------------------------------------------

  List<MatchGroup> _findMatchGroups() {
    List<MatchGroup> groups = [];

    // Horizontal
    for (int r = 0; r < BOARD_SIZE; r++) {
      for (int c = 0; c < BOARD_SIZE - 2; c++) {
        CandyType? type = _grid[r][c]?.type;
        if (type == null) continue;

        int len = 1;
        while (c + len < BOARD_SIZE && _grid[r][c + len]?.type == type) {
          len++;
        }

        if (len >= 3) {
          List<Point<int>> pts = [];
          for (int i = 0; i < len; i++) {
            pts.add(Point(r, c + i));
          }
          groups.add(MatchGroup(points: pts, isHorizontal: true, type: type));
          c += len - 1;
        }
      }
    }

    // Vertical
    for (int c = 0; c < BOARD_SIZE; c++) {
      for (int r = 0; r < BOARD_SIZE - 2; r++) {
        CandyType? type = _grid[r][c]?.type;
        if (type == null) continue;

        int len = 1;
        while (r + len < BOARD_SIZE && _grid[r + len][c]?.type == type) {
          len++;
        }

        if (len >= 3) {
          List<Point<int>> pts = [];
          for (int i = 0; i < len; i++) {
            pts.add(Point(r + i, c));
          }
          groups.add(MatchGroup(points: pts, isHorizontal: false, type: type));
          r += len - 1;
        }
      }
    }

    return groups;
  }

  void _processSpecialCreations(
      List<MatchGroup> matchGroups, int? swappedRow, int? swappedCol) {
    for (var g in matchGroups) {
      for (var p in g.points) {
        _grid[p.x][p.y]?.isMatched = true;
      }

      // 5-match -> Color Bomb
      if (g.points.length >= 5) {
        Point<int> spawnPt = _getSpawnPoint(g.points, swappedRow, swappedCol);
        _grid[spawnPt.x][spawnPt.y]?.isMatched = false;
        _grid[spawnPt.x][spawnPt.y]?.special = SpecialType.colorBomb;
      }
      // 4-match -> Striped Candy
      else if (g.points.length == 4) {
        Point<int> spawnPt = _getSpawnPoint(g.points, swappedRow, swappedCol);
        _grid[spawnPt.x][spawnPt.y]?.isMatched = false;
        _grid[spawnPt.x][spawnPt.y]?.special =
            g.isHorizontal ? SpecialType.stripedV : SpecialType.stripedH;
      }
    }
  }

  Point<int> _getSpawnPoint(
      List<Point<int>> pts, int? swappedRow, int? swappedCol) {
    if (swappedRow != null && swappedCol != null) {
      for (var p in pts) {
        if (p.x == swappedRow && p.y == swappedCol) return p;
      }
    }
    return pts[pts.length ~/ 2];
  }

  void _expandSpecialExplosions() {
    bool newlyExpanded = true;

    while (newlyExpanded) {
      newlyExpanded = false;

      for (int r = 0; r < BOARD_SIZE; r++) {
        for (int c = 0; c < BOARD_SIZE; c++) {
          Tile? tile = _grid[r][c];
          if (tile != null && tile.isMatched && tile.special != SpecialType.none) {
            SpecialType spec = tile.special;
            tile.special = SpecialType.none; // consume special

            if (spec == SpecialType.stripedH) {
              // Clear horizontal row
              for (int col = 0; col < BOARD_SIZE; col++) {
                if (_grid[r][col] != null && !_grid[r][col]!.isMatched) {
                  _grid[r][col]!.isMatched = true;
                  newlyExpanded = true;
                }
              }
            } else if (spec == SpecialType.stripedV) {
              // Clear vertical column
              for (int row = 0; row < BOARD_SIZE; row++) {
                if (_grid[row][c] != null && !_grid[row][c]!.isMatched) {
                  _grid[row][c]!.isMatched = true;
                  newlyExpanded = true;
                }
              }
            } else if (spec == SpecialType.wrapped) {
              // 3x3 Explosion
              for (int dr = -1; dr <= 1; dr++) {
                for (int dc = -1; dc <= 1; dc++) {
                  int nr = r + dr;
                  int nc = c + dc;
                  if (nr >= 0 &&
                      nr < BOARD_SIZE &&
                      nc >= 0 &&
                      nc < BOARD_SIZE &&
                      _grid[nr][nc] != null &&
                      !_grid[nr][nc]!.isMatched) {
                    _grid[nr][nc]!.isMatched = true;
                    newlyExpanded = true;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  void _popMatchedTiles() {
    for (int r = 0; r < BOARD_SIZE; r++) {
      for (int c = 0; c < BOARD_SIZE; c++) {
        Tile? tile = _grid[r][c];
        if (tile != null && tile.isMatched) {
          _spawnPopParticles(
              c.toDouble(), r.toDouble(), _getCandyColor(tile.type));
          _allTiles.remove(tile);
          _grid[r][c] = null;
        }
      }
    }
  }

  void _addScoreAndEffects(List<Point<int>> matchedPoints, int combo) {
    int points = matchedPoints.length * 60 * combo;
    _score += points;

    double avgR = 0;
    double avgC = 0;
    for (var p in matchedPoints) {
      avgR += p.x;
      avgC += p.y;
    }
    avgR /= matchedPoints.length;
    avgC /= matchedPoints.length;

    String text = "+$points";
    Color txtColor = Colors.white;

    if (combo == 2) {
      _showComboBanner("SWEET!", Colors.cyanAccent);
      txtColor = Colors.cyanAccent;
    } else if (combo == 3) {
      _showComboBanner("TASTY!!", Colors.amberAccent);
      txtColor = Colors.amberAccent;
    } else if (combo == 4) {
      _showComboBanner("DELICIOUS!!!", Colors.orangeAccent);
      txtColor = Colors.orangeAccent;
    } else if (combo >= 5) {
      _showComboBanner("DIVINE!!!!", Colors.purpleAccent);
      txtColor = Colors.purpleAccent;
    }

    _spawnFloatingText(text, avgC, avgR, txtColor);
  }

  void _showComboBanner(String text, Color color) {
    final banner = ComboBanner(
      id: 'cb_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      color: color,
    );
    setState(() {
      _currentComboBanner = banner;
    });

    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted && _currentComboBanner?.id == banner.id) {
        setState(() {
          _currentComboBanner = null;
        });
      }
    });
  }

  void _spawnFloatingText(String text, double col, double row, Color color) {
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

      int newSpawnCount = emptyRow + 1;
      for (int r = emptyRow; r >= 0; r--) {
        CandyType type = CandyType.values[_random.nextInt(NUM_CANDY_TYPES)];

        Tile newTile = Tile(
          id: 'tile_${_tileIdCounter++}',
          type: type,
          row: r,
          col: c,
        );

        newTile.row = r - newSpawnCount;
        _allTiles.add(newTile);
        _grid[r][c] = newTile;

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

  void _checkGameEnd() {
    if (_score >= TARGET_SCORE) {
      setState(() {
        _isGameOver = true;
        _isWin = true;
      });
    } else if (_movesLeft <= 0) {
      setState(() {
        _isGameOver = true;
        _isWin = false;
      });
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
              Color(0xFF1F0033),
              Color(0xFF3B0054),
              Color(0xFF6A006A),
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
                  const SizedBox(height: 12),
                  _buildTargetProgressBar(),
                  const Spacer(),
                  _buildBoard(boardWidth, tileSize),
                  const Spacer(),
                  _buildFooter(),
                  const SizedBox(height: 16),
                ],
              ),

              // Big Combo Banner Popup
              if (_currentComboBanner != null) _buildComboPopup(),

              // Game Over / Win Overlay
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
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildHeaderMetric("SCORE", "$_score", Icons.stars_rounded, Colors.amber),
            Container(height: 36, width: 2, color: Colors.white24),
            _buildHeaderMetric("TARGET", "$TARGET_SCORE", Icons.flag_rounded, Colors.greenAccent),
            Container(height: 36, width: 2, color: Colors.white24),
            _buildHeaderMetric("MOVES", "$_movesLeft", Icons.touch_app_rounded, Colors.cyanAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderMetric(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
      ],
    );
  }

  Widget _buildTargetProgressBar() {
    double progress = (_score / TARGET_SCORE).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Level Target Progress",
                style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 12),
              ),
              Text(
                "${(progress * 100).toInt()}%",
                style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.black45,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(double boardWidth, double tileSize) {
    return Container(
      width: boardWidth,
      height: boardWidth,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 18,
            spreadRadius: 2,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: [
            // Background Slots
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
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }),

            // Candies
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
                      if (velocity.dx > 0) {
                        _onTileSwipe(tile.row, tile.col, Vector2D(1, 0));
                      } else {
                        _onTileSwipe(tile.row, tile.col, Vector2D(-1, 0));
                      }
                    } else {
                      if (velocity.dy > 0) {
                        _onTileSwipe(tile.row, tile.col, Vector2D(0, 1));
                      } else {
                        _onTileSwipe(tile.row, tile.col, Vector2D(0, -1));
                      }
                    }
                  },
                  child: AnimatedScale(
                    scale: tile.isMatched ? 0.0 : (isSelected ? 1.18 : 1.0),
                    duration: const Duration(milliseconds: 200),
                    child: Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: CandyWidget(
                        type: tile.type,
                        special: tile.special,
                        isSelected: isSelected,
                      ),
                    ),
                  ),
                ),
              );
            }),

            // Particle Canvas Overlay
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: ParticlePainter(
                    particles: _particles,
                    tileSize: tileSize,
                  ),
                ),
              ),
            ),

            // Floating Score Overlay
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
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
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

  Widget _buildComboPopup() {
    final banner = _currentComboBanner!;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.2, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: banner.color, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: banner.color.withOpacity(0.6),
                    blurRadius: 25,
                    spreadRadius: 4,
                  )
                ],
              ),
              child: Text(
                banner.text,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: banner.color,
                  letterSpacing: 2,
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 8, offset: Offset(3, 3))
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isWin
                  ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                  : [const Color(0xFF4A154B), const Color(0xFF571845)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: _isWin ? Colors.greenAccent : Colors.amber, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: _isWin ? Colors.greenAccent : Colors.amberAccent,
                blurRadius: 20,
                spreadRadius: 1,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isWin ? Icons.stars_rounded : Icons.sentiment_very_dissatisfied_rounded,
                color: _isWin ? Colors.amberAccent : Colors.orangeAccent,
                size: 80,
              ),
              const SizedBox(height: 12),
              Text(
                _isWin ? "LEVEL CLEARED!" : "OUT OF MOVES!",
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
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
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: _isWin ? Colors.amberAccent : Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _startNewGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isWin ? Colors.greenAccent : Colors.amber,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 8,
                ),
                child: Text(
                  _isWin ? "NEXT LEVEL" : "TRY AGAIN",
                  style: const TextStyle(
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
// PAINTERS & GRAPHICS
// -----------------------------------------------------------------------------

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

class Vector2D {
  final int dx;
  final int dy;
  Vector2D(this.dx, this.dy);
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double tileSize;

  ParticlePainter({required this.particles, required this.tileSize});

  @override
  void paint(Canvas canvas, Size size) {
    for (var p in particles) {
      final paint = Paint()
        ..color = p.color.withOpacity(p.life.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      Offset center = Offset(
        (p.x + 0.5) * tileSize,
        (p.y + 0.5) * tileSize,
      );
      canvas.drawCircle(center, p.size * p.life, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => true;
}

class CandyWidget extends StatelessWidget {
  final CandyType type;
  final SpecialType special;
  final bool isSelected;

  const CandyWidget({
    super.key,
    required this.type,
    this.special = SpecialType.none,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    Color baseColor = _getCandyColor(type);

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
        boxShadow: [
          BoxShadow(
            color: baseColor.withOpacity(0.5),
            blurRadius: isSelected ? 12 : 6,
            spreadRadius: isSelected ? 2 : 1,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: CustomPaint(
        painter: _CandyPainter(type: type, special: special),
      ),
    );
  }
}

class _CandyPainter extends CustomPainter {
  final CandyType type;
  final SpecialType special;

  _CandyPainter({required this.type, required this.special});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    final paint = Paint()..style = PaintingStyle.fill;
    final shinePaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..style = PaintingStyle.fill;

    // Color Bomb render
    if (special == SpecialType.colorBomb) {
      paint.shader = const SweepGradient(
        colors: [
          Colors.red,
          Colors.yellow,
          Colors.green,
          Colors.blue,
          Colors.purple,
          Colors.red,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, paint);
      canvas.drawCircle(center, radius * 0.4, shinePaint);
      return;
    }

    // Standard Candy Shapes
    switch (type) {
      case CandyType.red:
        paint.shader = RadialGradient(
          colors: const [Color(0xFFFF758C), Color(0xFFFF7E5F), Color(0xFFB721FF)],
          center: const Alignment(-0.3, -0.3),
          radius: 0.9,
        ).createShader(Rect.fromCircle(center: center, radius: radius));
        canvas.drawCircle(center, radius, paint);
        canvas.drawCircle(
            Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
            radius * 0.25,
            shinePaint);
        break;

      case CandyType.blue:
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
          if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
          angle += step;
        }
        path.close();
        canvas.drawPath(path, paint);
        canvas.drawCircle(center, radius * 0.25, shinePaint);
        break;

      case CandyType.purple:
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
        paint.shader = const RadialGradient(
          colors: [Color(0xFFFFB74D), Color(0xFFE65100)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

        final rrect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: radius * 1.6, height: radius * 1.6),
          Radius.circular(radius * 0.35),
        );
        canvas.drawRRect(rrect, paint);

        canvas.drawCircle(
            Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
            radius * 0.2,
            shinePaint);
        break;
    }

    // Special Candy Overlay Effect
    if (special == SpecialType.stripedH || special == SpecialType.stripedV) {
      final stripePaint = Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;

      if (special == SpecialType.stripedH) {
        canvas.drawLine(Offset(center.dx - radius * 0.8, center.dy),
            Offset(center.dx + radius * 0.8, center.dy), stripePaint);
      } else {
        canvas.drawLine(Offset(center.dx, center.dy - radius * 0.8),
            Offset(center.dx, center.dy + radius * 0.8), stripePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CandyPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.special != special;
}

class MatchGroup {
  final List<Point<int>> points;
  final bool isHorizontal;
  final CandyType type;

  MatchGroup({
    required this.points,
    required this.isHorizontal,
    required this.type,
  });
}
