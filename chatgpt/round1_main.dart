import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF24104F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const CandyKingdomApp());
}
const int boardSize = 8;
const int candyTypes = 6;
const int startingMoves = 30;
const List<Color> candyColors = [
  Color(0xFFFF496B),
  Color(0xFFFFB52E),
  Color(0xFF45D9F5),
  Color(0xFF9C65FF),
  Color(0xFF79DF59),
  Color(0xFFFF72C5),
];
const List<Color> candyShadows = [
  Color(0xFFB91B50),
  Color(0xFFD36B18),
  Color(0xFF168FC4),
  Color(0xFF5B32BC),
  Color(0xFF399C36),
  Color(0xFFBF388E),
];
class CandyKingdomApp extends StatelessWidget {
  const CandyKingdomApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Candy Kingdom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF24104F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF78C7),
          brightness: Brightness.dark,
        ),
      ),
      home: const CandyGame(),
    );
  }
}
class Candy {
  Candy({
    required this.id,
    required this.type,
    required this.row,
    required this.col,
    this.spawnRow,
  });
  final int id;
  final int type;
  int row;
  int col;
  final int? spawnRow;
}
class BoardPosition {
  const BoardPosition(this.row, this.col);
  final int row;
  final int col;
  @override
  bool operator ==(Object other) =>
      other is BoardPosition &&
      other.row == row &&
      other.col == col;
  @override
  int get hashCode => Object.hash(row, col);
}
class CandyGame extends StatefulWidget {
  const CandyGame({super.key});
  @override
  State<CandyGame> createState() => _CandyGameState();
}
class _CandyGameState extends State<CandyGame>
    with TickerProviderStateMixin {
  final math.Random _random = math.Random();
  late AnimationController _backgroundController;
  late AnimationController _pulseController;
  late AnimationController _boardController;
  final List<Candy> _candies = [];
  final Set<int> _matchedIds = {};
  final List<_Burst> _bursts = [];
  int _nextId = 0;
  int _score = 0;
  int _moves = startingMoves;
  int _combo = 0;
  int _bestCombo = 0;
  int _session = 0;
  bool _busy = false;
  bool _gameOver = false;
  bool _showCombo = false;
  bool _invalidSwap = false;
  BoardPosition? _selected;
  BoardPosition? _dragStart;
  String _comboText = '';
  String _message = 'MATCH 3 TO SCORE!';
  int _messageVersion = 0;
  static const Duration swapDuration = Duration(milliseconds: 230);
  static const Duration matchDuration = Duration(milliseconds: 260);
  static const Duration fallDuration = Duration(milliseconds: 420);
  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat(reverse: true);
    _boardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _newGame();
  }
  @override
  void dispose() {
    _backgroundController.dispose();
    _pulseController.dispose();
    _boardController.dispose();
    super.dispose();
  }
  void _newGame() {
    _session++;
    _nextId = 0;
    _candies.clear();
    _matchedIds.clear();
    _bursts.clear();
    _score = 0;
    _moves = startingMoves;
    _combo = 0;
    _bestCombo = 0;
    _selected = null;
    _dragStart = null;
    _busy = false;
    _gameOver = false;
    _showCombo = false;
    _invalidSwap = false;
    _message = 'MATCH 3 TO SCORE!';
    _comboText = '';
    _generateBoard();
    if (mounted) {
      setState(() {});
      _boardController.forward(from: 0);
    }
  }
  void _generateBoard() {
    int attempts = 0;
    do {
      _candies.clear();
      final grid = List.generate(
        boardSize,
        (_) => List<int>.filled(boardSize, -1),
      );
      for (int row = 0; row < boardSize; row++) {
        for (int col = 0; col < boardSize; col++) {
          final options = List<int>.generate(
            candyTypes,
            (i) => i,
          );
          if (col >= 2 &&
              grid[row][col - 1] == grid[row][col - 2]) {
            options.remove(grid[row][col - 1]);
          }
          if (row >= 2 &&
              grid[row - 1][col] == grid[row - 2][col]) {
            options.remove(grid[row - 1][col]);
          }
          final type = options[_random.nextInt(options.length)];
          grid[row][col] = type;
          _candies.add(
            Candy(
              id: _nextId++,
              type: type,
              row: row,
              col: col,
            ),
          );
        }
      }
      attempts++;
    } while (!_hasPossibleMove() && attempts < 200);
  }
  Candy? _candyAt(int row, int col) {
    for (final candy in _candies) {
      if (candy.row == row && candy.col == col) {
        return candy;
      }
    }
    return null;
  }
  List<List<Candy?>> _grid() {
    final grid = List.generate(
      boardSize,
      (_) => List<Candy?>.filled(boardSize, null),
    );
    for (final candy in _candies) {
      if (candy.row >= 0 &&
          candy.row < boardSize &&
          candy.col >= 0 &&
          candy.col < boardSize) {
        grid[candy.row][candy.col] = candy;
      }
    }
    return grid;
  }
  Set<int> _findMatches() {
    final grid = _grid();
    final matches = <int>{};
    for (int row = 0; row < boardSize; row++) {
      int start = 0;
      while (start < boardSize) {
        final first = grid[row][start];
        if (first == null) {
          start++;
          continue;
        }
        int end = start + 1;
        while (end < boardSize &&
            grid[row][end]?.type == first.type) {
          end++;
        }
        if (end - start >= 3) {
          for (int col = start; col < end; col++) {
            matches.add(grid[row][col]!.id);
          }
        }
        start = end;
      }
    }
    for (int col = 0; col < boardSize; col++) {
      int start = 0;
      while (start < boardSize) {
        final first = grid[start][col];
        if (first == null) {
          start++;
          continue;
        }
        int end = start + 1;
        while (end < boardSize &&
            grid[end][col]?.type == first.type) {
          end++;
        }
        if (end - start >= 3) {
          for (int row = start; row < end; row++) {
            matches.add(grid[row][col]!.id);
          }
        }
        start = end;
      }
    }
    return matches;
  }
  bool _hasPossibleMove() {
    final grid = _grid();
    for (int row = 0; row < boardSize; row++) {
      for (int col = 0; col < boardSize; col++) {
        final first = grid[row][col];
        if (first == null) continue;
        for (final direction in const [
          BoardPosition(0, 1),
          BoardPosition(1, 0),
        ]) {
          final nr = row + direction.row;
          final nc = col + direction.col;
          if (nr >= boardSize || nc >= boardSize) continue;
          final second = grid[nr][nc];
          if (second == null) continue;
          first.row = nr;
          first.col = nc;
          second.row = row;
          second.col = col;
          final possible = _findMatches().isNotEmpty;
          first.row = row;
          first.col = col;
          second.row = nr;
          second.col = nc;
          if (possible) return true;
        }
      }
    }
    return false;
  }
  bool _isNeighbor(BoardPosition a, BoardPosition b) {
    return (a.row - b.row).abs() +
            (a.col - b.col).abs() ==
        1;
  }
  void _onCellTap(int row, int col) {
    if (_busy || _gameOver) return;
    final position = BoardPosition(row, col);
    if (_selected == null) {
      setState(() => _selected = position);
      HapticFeedback.selectionClick();
      return;
    }
    if (_selected == position) {
      setState(() => _selected = null);
      return;
    }
    if (_isNeighbor(_selected!, position)) {
      final previous = _selected!;
      setState(() => _selected = null);
      _swap(previous, position);
    } else {
      setState(() => _selected = position);
      HapticFeedback.selectionClick();
    }
  }
  void _onSwipe(BoardPosition from, BoardPosition to) {
    if (_busy || _gameOver) return;
    if (!_isNeighbor(from, to)) return;
    setState(() => _selected = null);
    _swap(from, to);
  }
  Future<void> _swap(BoardPosition a, BoardPosition b) async {
    if (_busy || _gameOver || _moves <= 0) return;
    final first = _candyAt(a.row, a.col);
    final second = _candyAt(b.row, b.col);
    if (first == null || second == null) return;
    final session = _session;
    setState(() {
      _busy = true;
      first.row = b.row;
      first.col = b.col;
      second.row = a.row;
      second.col = a.col;
    });
    HapticFeedback.lightImpact();
    await Future<void>.delayed(swapDuration);
    if (!mounted || session != _session) return;
    final matches = _findMatches();
    if (matches.isEmpty) {
      setState(() {
        first.row = a.row;
        first.col = a.col;
        second.row = b.row;
        second.col = b.col;
        _invalidSwap = true;
      });
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(swapDuration);
      if (!mounted || session != _session) return;
      setState(() {
        _busy = false;
        _invalidSwap = false;
      });
      return;
    }
    setState(() {
      _moves--;
      _combo = 0;
    });
    await _resolveMatches(session);
    if (!mounted || session != _session) return;
    if (_moves <= 0) {
      await Future<void>.delayed(
        const Duration(milliseconds: 450),
      );
      if (!mounted || session != _session) return;
      setState(() {
        _gameOver = true;
        _busy = false;
        _showCombo = false;
      });
      HapticFeedback.heavyImpact();
      return;
    }
    if (!_hasPossibleMove()) {
      _setMessage('SWEET SHUFFLE!');
      await _shuffleBoard(session);
    }
    if (!mounted || session != _session) return;
    setState(() {
      _busy = false;
      _showCombo = false;
    });
  }
  Future<void> _resolveMatches(int session) async {
    while (true) {
      if (!mounted || session != _session) return;
      final matches = _findMatches();
      if (matches.isEmpty) break;
      _combo++;
      _bestCombo = math.max(_bestCombo, _combo);
      final earned = matches.length * 60 * _combo +
          (matches.length >= 4 ? 100 * _combo : 0);
      final matchedCandies = _candies
          .where((candy) => matches.contains(candy.id))
          .toList();
      setState(() {
        _score += earned;
        _matchedIds.addAll(matches);
        for (final candy in matchedCandies) {
          _bursts.add(
            _Burst(
              id: candy.id,
              row: candy.row,
              col: candy.col,
              color: candyColors[candy.type],
            ),
          );
        }
        if (_combo > 1) {
          _showCombo = true;
          _comboText = _combo >= 4
              ? 'SUGAR RUSH! x$_combo'
              : _combo >= 3
                  ? 'AMAZING! x$_combo'
                  : 'SWEET COMBO! x$_combo';
        }
      });
      _setMessage(
        _combo >= 4
            ? 'LEGENDARY!'
            : _combo == 3
                ? 'INCREDIBLE!'
                : _combo == 2
                    ? 'DELICIOUS!'
                    : matches.length >= 5
                        ? 'SUGAR BLAST!'
                        : matches.length >= 4
                            ? 'TASTY!'
                            : 'SWEET!',
      );
      if (_combo >= 2) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
      await Future<void>.delayed(matchDuration);
      if (!mounted || session != _session) return;
      setState(() {
        _candies.removeWhere(
          (candy) => matches.contains(candy.id),
        );
        _matchedIds.clear();
        _bursts.clear();
      });
      _applyGravity();
      await Future<void>.delayed(fallDuration);
      if (!mounted || session != _session) return;
      await Future<void>.delayed(
        const Duration(milliseconds: 110),
      );
    }
  }
  void _applyGravity() {
    setState(() {
      for (int col = 0; col < boardSize; col++) {
        final column = _candies
            .where((candy) => candy.col == col)
            .toList()
          ..sort((a, b) => b.row.compareTo(a.row));
        int destination = boardSize - 1;
        for (final candy in column) {
          candy.row = destination;
          destination--;
        }
        int spawnOffset = 1;
        while (destination >= 0) {
          _candies.add(
            Candy(
              id: _nextId++,
              type: _random.nextInt(candyTypes),
              row: destination,
              col: col,
              spawnRow: -spawnOffset,
            ),
          );
          destination--;
          spawnOffset++;
        }
      }
    });
  }
  Future<void> _shuffleBoard(int session) async {
    if (!mounted || session != _session) return;
    setState(() {
      _matchedIds.addAll(
        _candies.map((candy) => candy.id),
      );
    });
    await Future<void>.delayed(
      const Duration(milliseconds: 280),
    );
    if (!mounted || session != _session) return;
    setState(() {
      _matchedIds.clear();
      _generateBoard();
      _boardController.forward(from: 0);
    });
    await Future<void>.delayed(
      const Duration(milliseconds: 650),
    );
  }
  void _setMessage(String message) {
    final version = ++_messageVersion;
    if (mounted) {
      setState(() => _message = message);
    }
    Future<void>.delayed(
      const Duration(milliseconds: 1400),
      () {
        if (!mounted || version != _messageVersion) return;
        if (_gameOver) return;
        setState(() => _message = 'MATCH 3 TO SCORE!');
      },
    );
  }
  String _formatScore(int score) {
    final value = score.toString();
    return value.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
  }
  int get _stars {
    if (_score >= 12000) return 3;
    if (_score >= 6500) return 2;
    if (_score >= 2500) return 1;
    return 0;
  }
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final availableHeight = size.height - safeTop - safeBottom;
    final boardWidth = math.min(
      size.width - 26,
      math.min(490.0, availableHeight * 0.58),
    );
    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 700;
                return Column(
                  children: [
                    SizedBox(height: compact ? 8 : 18),
                    _buildHeader(compact),
                    SizedBox(height: compact ? 12 : 24),
                    _buildStats(),
                    SizedBox(height: compact ? 12 : 24),
                    _buildLevelStrip(),
                    const Spacer(),
                    _buildBoard(boardWidth),
                    const Spacer(),
                    _buildBottomMessage(compact),
                    SizedBox(height: compact ? 10 : 24),
                  ],
                );
              },
            ),
          ),
          if (_gameOver) _buildGameOver(),
        ],
      ),
    );
  }
  Widget _buildBackground() {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        final progress = _backgroundController.value;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF59299C),
                Color(0xFF371568),
                Color(0xFF230E4F),
                Color(0xFF170B38),
              ],
              stops: [0.0, 0.33, 0.72, 1.0],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -145 + math.sin(progress * math.pi * 2) * 22,
                right: -130,
                child: _backgroundGlow(
                  360,
                  const Color(0xFFFF63CA).withValues(alpha: 0.22),
                ),
              ),
              Positioned(
                bottom: -160,
                left: -150 + math.cos(progress * math.pi * 2) * 25,
                child: _backgroundGlow(
                  400,
                  const Color(0xFF6267FF).withValues(alpha: 0.20),
                ),
              ),
              ...List.generate(24, (index) {
                final seed = index * 17.37;
                final dx = (math.sin(seed) + 1) / 2;
                final dy = (math.cos(seed * 1.7) + 1) / 2;
                final drift =
                    math.sin(progress * math.pi * 2 + seed) * 9;
                return Positioned(
                  left: dx * MediaQuery.sizeOf(context).width,
                  top: dy * MediaQuery.sizeOf(context).height + drift,
                  child: Opacity(
                    opacity: 0.15 + (index % 4) * 0.075,
                    child: Icon(
                      index % 3 == 0
                          ? Icons.auto_awesome
                          : Icons.circle,
                      size: index % 3 == 0 ? 12 : 4,
                      color: index.isEven
                          ? Colors.white
                          : const Color(0xFFFFA3E8),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
  Widget _backgroundGlow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
  Widget _buildHeader(bool compact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(
                angle: -0.25,
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFFFD65A),
                  size: 25,
                ),
              ),
              const SizedBox(width: 6),
              ShaderMask(
                shaderCallback: (bounds) {
                  return const LinearGradient(
                    colors: [
                      Color(0xFFFFF7B5),
                      Color(0xFFFFC464),
                      Color(0xFFFF7CB9),
                    ],
                  ).createShader(bounds);
                },
                child: Text(
                  'CANDY KINGDOM',
                  style: TextStyle(
                    fontSize: compact ? 25 : 29,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.9,
                    height: 1,
                    color: Colors.white,
                    shadows: const [
                      Shadow(
                        color: Color(0xFF981E91),
                        blurRadius: 13,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Transform.rotate(
                angle: 0.25,
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFFFD65A),
                  size: 25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'A SWEET LITTLE ADVENTURE',
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              color: const Color(0xFFEBCBFF).withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              title: 'SCORE',
              value: _formatScore(_score),
              icon: Icons.stars_rounded,
              accent: const Color(0xFFFFC857),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              title: 'MOVES LEFT',
              value: '$_moves',
              icon: Icons.bolt_rounded,
              accent: _moves <= 5
                  ? const Color(0xFFFF6C85)
                  : const Color(0xFF6DE9F7),
            ),
          ),
        ],
      ),
    );
  }
  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      height: 84,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.065),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.19),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 15,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 25,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.75,
                          end: 1,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    child: FittedBox(
                      key: ValueKey(value),
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildLevelStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFFBB58).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFFFFD67B)
                    .withValues(alpha: 0.36),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_florist_rounded,
                  color: Color(0xFFFFD269),
                  size: 16,
                ),
                SizedBox(width: 5),
                Text(
                  'LEVEL 1',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    color: Color(0xFFFFE3A7),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          ...List.generate(3, (index) {
            final filled = index < _stars;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: filled
                        ? 1 + _pulseController.value * 0.07
                        : 1,
                    child: child,
                  );
                },
                child: Icon(
                  Icons.star_rounded,
                  size: 29,
                  color: filled
                      ? const Color(0xFFFFD053)
                      : Colors.white.withValues(alpha: 0.20),
                  shadows: filled
                      ? const [
                          Shadow(
                            color: Color(0xFFFFA336),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
  Widget _buildBoard(double width) {
    final cellSize = (width - 16) / boardSize;
    return Center(
      child: Container(
        width: width + 6,
        height: width + 6,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFD1F4),
              Color(0xFFB972ED),
              Color(0xFF6536A4),
              Color(0xFFE695E0),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF64CE)
                  .withValues(alpha: 0.20),
              blurRadius: 30,
              spreadRadius: 3,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF27114E),
            borderRadius: BorderRadius.circular(22),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: cellSize * boardSize,
              height: cellSize * boardSize,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  _buildBoardTiles(cellSize),
                  ..._candies.map(
                    (candy) => _buildCandy(candy, cellSize),
                  ),
                  ..._bursts.map(
                    (burst) => _buildBurst(burst, cellSize),
                  ),
                  if (_showCombo)
                    IgnorePointer(
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey('combo-$_combo'),
                          tween: Tween(begin: 0.35, end: 1),
                          duration: const Duration(
                            milliseconds: 420,
                          ),
                          curve: Curves.elasticOut,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: value,
                              child: child,
                            );
                          },
                          child: Transform.rotate(
                            angle: -0.065,
                            child: Text(
                              _comboText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: cellSize * 0.63,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                foreground: Paint()
                                  ..style = PaintingStyle.stroke
                                  ..strokeWidth = 5
                                  ..color =
                                      const Color(0xFF802C95),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_showCombo)
                    IgnorePointer(
                      child: Center(
                        child: Text(
                          _comboText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: cellSize * 0.63,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: const Color(0xFFFFE674),
                            shadows: const [
                              Shadow(
                                color: Color(0xFFBD498D),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  _buildBoardGestureLayer(cellSize),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildBoardTiles(double cellSize) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFF321659),
        ),
        for (int row = 0; row < boardSize; row++)
          for (int col = 0; col < boardSize; col++)
            Positioned(
              left: col * cellSize,
              top: row * cellSize,
              width: cellSize,
              height: cellSize,
              child: Container(
                decoration: BoxDecoration(
                  color: (row + col).isEven
                      ? const Color(0xFF713C9E)
                          .withValues(alpha: 0.46)
                      : const Color(0xFF4D277E)
                          .withValues(alpha: 0.35),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.025),
                    width: 0.5,
                  ),
                ),
              ),
            ),
      ],
    );
  }
  Widget _buildCandy(Candy candy, double cellSize) {
    final isMatched = _matchedIds.contains(candy.id);
    final isSelected = _selected ==
        BoardPosition(candy.row, candy.col);
    final startTop =
        (candy.spawnRow ?? candy.row) * cellSize.toDouble();
    final top = candy.row * cellSize.toDouble();
    final left = candy.col * cellSize.toDouble();
    return AnimatedPositioned(
      key: ValueKey(candy.id),
      duration: fallDuration,
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: cellSize,
      height: cellSize,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('entry-${candy.id}'),
        tween: Tween(
          begin: candy.spawnRow != null ? startTop - top : 0,
          end: 0,
        ),
        duration: candy.spawnRow == null
            ? Duration.zero
            : fallDuration,
        curve: Curves.easeOutCubic,
        builder: (context, offset, child) {
          return Transform.translate(
            offset: Offset(0, offset),
            child: child,
          );
        },
        child: AnimatedScale(
          scale: isMatched ? 0.03 : (isSelected ? 1.13 : 1),
          duration: isMatched
              ? matchDuration
              : const Duration(milliseconds: 150),
          curve: isMatched
              ? Curves.easeInBack
              : Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: isMatched ? 0 : 1,
            duration: matchDuration,
            child: Padding(
              padding: EdgeInsets.all(cellSize * 0.055),
              child: CustomPaint(
                painter: CandyPainter(
                  type: candy.type,
                  selected: isSelected,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildBurst(_Burst burst, double cellSize) {
    return Positioned(
      left: burst.col * cellSize - cellSize * 0.45,
      top: burst.row * cellSize - cellSize * 0.45,
      width: cellSize * 1.9,
      height: cellSize * 1.9,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey('burst-${burst.id}'),
          tween: Tween(begin: 0, end: 1),
          duration: matchDuration,
          builder: (context, value, child) {
            return CustomPaint(
              painter: BurstPainter(
                progress: value,
                color: burst.color,
                seed: burst.id,
              ),
            );
          },
        ),
      ),
    );
  }
  Widget _buildBoardGestureLayer(double cellSize) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          final position = _positionFromOffset(
            details.localPosition,
            cellSize,
          );
          if (position != null) {
            _onCellTap(position.row, position.col);
          }
        },
        onPanStart: (details) {
          _dragStart = _positionFromOffset(
            details.localPosition,
            cellSize,
          );
        },
        onPanEnd: (_) {
          _dragStart = null;
        },
        onPanCancel: () {
          _dragStart = null;
        },
        onPanUpdate: (details) {
          if (_dragStart == null || _busy) return;
          final from = _dragStart!;
          final local = details.localPosition;
          final dx = local.dx - (from.col + 0.5) * cellSize;
          final dy = local.dy - (from.row + 0.5) * cellSize;
          if (math.max(dx.abs(), dy.abs()) < cellSize * 0.36) {
            return;
          }
          BoardPosition target;
          if (dx.abs() > dy.abs()) {
            target = BoardPosition(
              from.row,
              from.col + (dx > 0 ? 1 : -1),
            );
          } else {
            target = BoardPosition(
              from.row + (dy > 0 ? 1 : -1),
              from.col,
            );
          }
          _dragStart = null;
          if (target.row >= 0 &&
              target.row < boardSize &&
              target.col >= 0 &&
              target.col < boardSize) {
            _onSwipe(from, target);
          }
        },
      ),
    );
  }
  BoardPosition? _positionFromOffset(
    Offset offset,
    double cellSize,
  ) {
    final row = (offset.dy / cellSize).floor();
    final col = (offset.dx / cellSize).floor();
    if (row < 0 ||
        col < 0 ||
        row >= boardSize ||
        col >= boardSize) {
      return null;
    }
    return BoardPosition(row, col);
  }
  Widget _buildBottomMessage(bool compact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            _message,
            key: ValueKey(_message),
            style: const TextStyle(
              color: Color(0xFFFFD978),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.1,
              shadows: [
                Shadow(
                  color: Color(0xFFDD5CA5),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.48),
            ),
            const SizedBox(width: 6),
            Text(
              'Tap or swipe to swap candies',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
  Widget _buildGameOver() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF130625).withValues(alpha: 0.82),
        child: SafeArea(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.65, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Container(
                width: math.min(
                  MediaQuery.sizeOf(context).width - 40,
                  380,
                ),
                padding: const EdgeInsets.fromLTRB(
                  25,
                  28,
                  25,
                  30,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF8044C4),
                      Color(0xFF54268F),
                      Color(0xFF38166D),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: const Color(0xFFFFA7E6),
                    width: 2.3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6DD0)
                          .withValues(alpha: 0.35),
                      blurRadius: 55,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 31,
                      color: Color(0xFFFFD67E),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'SWEET FINISH!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFFFE28A),
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        shadows: [
                          Shadow(
                            color: Color(0xFFBA479A),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You used all 30 moves!',
                      style: TextStyle(
                        color: Color(0xFFEAD1FA),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) {
                        final filled = index < _stars;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                          ),
                          child: Icon(
                            Icons.star_rounded,
                            size: index == 1 ? 65 : 53,
                            color: filled
                                ? const Color(0xFFFFD456)
                                : const Color(0xFF9971B9),
                            shadows: filled
                                ? const [
                                    Shadow(
                                      color: Color(0xFFFFBD35),
                                      blurRadius: 21,
                                    ),
                                  ]
                                : null,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF210E4B)
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'FINAL SCORE',
                            style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: 0.65),
                              letterSpacing: 2,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _formatScore(_score),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 46,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Divider(
                            color: Colors.white
                                .withValues(alpha: 0.13),
                          ),
                          const SizedBox(height: 7),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Best chain',
                                style: TextStyle(
                                  color: Color(0xFFE0C5F4),
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'x$_bestCombo',
                                style: const TextStyle(
                                  color: Color(0xFFFFD577),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _newGame();
                      },
                      child: Container(
                        width: double.infinity,
                        height: 59,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFFFD96D),
                              Color(0xFFFFA936),
                              Color(0xFFED7D26),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(
                            color: const Color(0xFFFFF0A8),
                            width: 1.7,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xFFAD4F20),
                              offset: Offset(0, 5),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.replay_rounded,
                              color: Color(0xFF77356A),
                              size: 25,
                            ),
                            SizedBox(width: 9),
                            Text(
                              'PLAY AGAIN',
                              style: TextStyle(
                                color: Color(0xFF77356A),
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _Burst {
  const _Burst({
    required this.id,
    required this.row,
    required this.col,
    required this.color,
  });
  final int id;
  final int row;
  final int col;
  final Color color;
}
class CandyPainter extends CustomPainter {
  CandyPainter({
    required this.type,
    required this.selected,
  });
  final int type;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final bounds = Rect.fromLTWH(0, 0, w, h);
    final base = candyColors[type];
    final shadow = candyShadows[type];
    if (selected) {
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          10,
        );
      canvas.drawCircle(
        center,
        w * 0.55,
        glow,
      );
    }
    canvas.save();
    canvas.translate(0, h * 0.055);
    final path = _candyPath(type, w, h);
    canvas.drawShadow(
      path,
      Colors.black.withValues(alpha: 0.38),
      3.5,
      false,
    );
    final darkPaint = Paint()
      ..color = shadow
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, darkPaint);
    final fill = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.42, -0.65),
        radius: 1.1,
        colors: [
          Color.lerp(base, Colors.white, 0.56)!,
          base,
          shadow,
        ],
        stops: const [0, 0.58, 1],
      ).createShader(bounds);
    canvas.drawPath(path, fill);
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.67)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round;
    final highlightPath = Path()
      ..moveTo(w * 0.24, h * 0.40)
      ..quadraticBezierTo(
        w * 0.27,
        h * 0.19,
        w * 0.50,
        h * 0.19,
      );
    canvas.drawPath(highlightPath, highlight);
    final shine = Paint()
      ..color = Colors.white.withValues(alpha: 0.32);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.35, h * 0.29),
        width: w * 0.20,
        height: h * 0.10,
      ),
      shine,
    );
    _drawCandyDetail(canvas, size, type);
    canvas.restore();
  }
  Path _candyPath(int type, double w, double h) {
    switch (type) {
      case 0:
        return Path()
          ..moveTo(w * 0.50, h * 0.82)
          ..cubicTo(
            w * 0.34,
            h * 0.72,
            w * 0.08,
            h * 0.53,
            w * 0.13,
            h * 0.32,
          )
          ..cubicTo(
            w * 0.17,
            h * 0.12,
            w * 0.38,
            h * 0.11,
            w * 0.50,
            h * 0.25,
          )
          ..cubicTo(
            w * 0.65,
            h * 0.08,
            w * 0.87,
            h * 0.17,
            w * 0.88,
            h * 0.37,
          )
          ..cubicTo(
            w * 0.90,
            h * 0.56,
            w * 0.68,
            h * 0.74,
            w * 0.50,
            h * 0.82,
          )
          ..close();
      case 1:
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                w * 0.13,
                h * 0.14,
                w * 0.74,
                h * 0.72,
              ),
              Radius.circular(w * 0.22),
            ),
          );
      case 2:
        return Path()
          ..moveTo(w * 0.50, h * 0.06)
          ..cubicTo(
            w * 0.70,
            h * 0.14,
            w * 0.89,
            h * 0.32,
            w * 0.92,
            h * 0.53,
          )
          ..cubicTo(
            w * 0.84,
            h * 0.77,
            w * 0.67,
            h * 0.91,
            w * 0.50,
            h * 0.93,
          )
          ..cubicTo(
            w * 0.31,
            h * 0.91,
            w * 0.12,
            h * 0.75,
            w * 0.08,
            h * 0.53,
          )
          ..cubicTo(
            w * 0.12,
            h * 0.30,
            w * 0.28,
            h * 0.14,
            w * 0.50,
            h * 0.06,
          )
          ..close();
      case 3:
        return Path()
          ..moveTo(w * 0.50, h * 0.05)
          ..quadraticBezierTo(
            w * 0.62,
            h * 0.06,
            w * 0.74,
            h * 0.24,
          )
          ..quadraticBezierTo(
            w * 0.94,
            h * 0.37,
            w * 0.92,
            h * 0.51,
          )
          ..quadraticBezierTo(
            w * 0.90,
            h * 0.72,
            w * 0.73,
            h * 0.79,
          )
          ..quadraticBezierTo(
            w * 0.61,
            h * 0.94,
            w * 0.50,
            h * 0.93,
          )
          ..quadraticBezierTo(
            w * 0.34,
            h * 0.92,
            w * 0.27,
            h * 0.80,
          )
          ..quadraticBezierTo(
            w * 0.08,
            h * 0.70,
            w * 0.08,
            h * 0.51,
          )
          ..quadraticBezierTo(
            w * 0.08,
            h * 0.34,
            w * 0.26,
            h * 0.23,
          )
          ..quadraticBezierTo(
            w * 0.38,
            h * 0.05,
            w * 0.50,
            h * 0.05,
          )
          ..close();
      case 4:
        return Path()
          ..moveTo(w * 0.50, h * 0.10)
          ..cubicTo(
            w * 0.74,
            h * 0.05,
            w * 0.93,
            h * 0.34,
            w * 0.88,
            h * 0.50,
          )
          ..cubicTo(
            w * 0.98,
            h * 0.75,
            w * 0.68,
            h * 0.95,
            w * 0.50,
            h * 0.88,
          )
          ..cubicTo(
            w * 0.25,
            h * 0.97,
            w * 0.05,
            h * 0.72,
            w * 0.12,
            h * 0.50,
          )
          ..cubicTo(
            w * 0.04,
            h * 0.29,
            w * 0.26,
            h * 0.08,
            w * 0.50,
            h * 0.10,
          )
          ..close();
      default:
        return Path()
          ..moveTo(w * 0.50, h * 0.06)
          ..cubicTo(
            w * 0.80,
            h * 0.06,
            w * 0.94,
            h * 0.30,
            w * 0.90,
            h * 0.50,
          )
          ..cubicTo(
            w * 0.94,
            h * 0.77,
            w * 0.70,
            h * 0.93,
            w * 0.50,
            h * 0.91,
          )
          ..cubicTo(
            w * 0.24,
            h * 0.96,
            w * 0.06,
            h * 0.72,
            w * 0.10,
            h * 0.50,
          )
          ..cubicTo(
            w * 0.07,
            h * 0.28,
            w * 0.25,
            h * 0.05,
            w * 0.50,
            h * 0.06,
          )
          ..close();
    }
  }
  void _drawCandyDetail(Canvas canvas, Size size, int type) {
    final w = size.width;
    final h = size.height;
    switch (type) {
      case 0:
        final paint = Paint()
          ..color = const Color(0xFFFFD4DE)
              .withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.065
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          Rect.fromLTWH(
            w * 0.30,
            h * 0.30,
            w * 0.40,
            h * 0.32,
          ),
          0.2,
          math.pi * 0.7,
          false,
          paint,
        );
        break;
      case 1:
        final paint = Paint()
          ..color = const Color(0xFFFFF2B2)
              .withValues(alpha: 0.64)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.09
          ..strokeCap = StrokeCap.round;
        for (double x = 0.31; x <= 0.7; x += 0.2) {
          canvas.drawLine(
            Offset(w * x, h * 0.34),
            Offset(w * (x - 0.09), h * 0.68),
            paint,
          );
        }
        break;
      case 2:
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: 0.58)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.065
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(w * 0.28, h * 0.53),
          Offset(w * 0.72, h * 0.53),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.5, h * 0.31),
          Offset(w * 0.5, h * 0.74),
          paint,
        );
        break;
      case 3:
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.07
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(w * 0.35, h * 0.36)
          ..quadraticBezierTo(
            w * 0.72,
            h * 0.37,
            w * 0.64,
            h * 0.60,
          )
          ..quadraticBezierTo(
            w * 0.53,
            h * 0.78,
            w * 0.38,
            h * 0.58,
          );
        canvas.drawPath(path, paint);
        break;
      case 4:
        final paint = Paint()
          ..color = const Color(0xFFE0FFC8)
              .withValues(alpha: 0.52)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.065
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(w * 0.30, h * 0.58)
          ..quadraticBezierTo(
            w * 0.46,
            h * 0.32,
            w * 0.70,
            h * 0.47,
          );
        canvas.drawPath(path, paint);
        break;
      case 5:
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.075
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          Rect.fromLTWH(
            w * 0.27,
            h * 0.27,
            w * 0.46,
            h * 0.46,
          ),
          -0.6,
          math.pi * 1.55,
          false,
          paint,
        );
        canvas.drawCircle(
          Offset(w * 0.49, h * 0.50),
          w * 0.045,
          Paint()..color = Colors.white.withValues(alpha: 0.7),
        );
        break;
    }
  }
  @override
  bool shouldRepaint(covariant CandyPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.selected != selected;
  }
}
class BurstPainter extends CustomPainter {
  BurstPainter({
    required this.progress,
    required this.color,
    required this.seed,
  });
  final double progress;
  final Color color;
  final int seed;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;
    final random = math.Random(seed);
    for (int i = 0; i < 11; i++) {
      final angle = math.pi * 2 * i / 11 +
          random.nextDouble() * 0.25;
      final distance = radius * (0.2 + progress * 0.76);
      final position = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      final particleRadius =
          (2.2 + random.nextDouble() * 3.4) *
              (1 - progress * 0.85);
      final paint = Paint()
        ..color = (i.isEven ? Colors.white : color)
            .withValues(alpha: (1 - progress).clamp(0, 1));
      canvas.drawCircle(
        position,
        particleRadius,
        paint,
      );
    }
    final ring = Paint()
      ..color = Colors.white.withValues(
        alpha: (0.55 * (1 - progress)).clamp(0, 1),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = (3 * (1 - progress)).clamp(0, 3);
    canvas.drawCircle(
      center,
      radius * progress * 0.85,
      ring,
    );
    for (int i = 0; i < 4; i++) {
      final angle = math.pi * 2 * i / 4 + 0.4;
      final d = radius * (0.35 + progress * 0.5);
      final p = Offset(
        center.dx + math.cos(angle) * d,
        center.dy + math.sin(angle) * d,
      );
      final starPaint = Paint()
        ..color = const Color(0xFFFFF4B9)
            .withValues(alpha: 1 - progress);
      final s = 5.0 * (1 - progress);
      final path = Path()
        ..moveTo(p.dx, p.dy - s)
        ..lineTo(p.dx + s * 0.25, p.dy - s * 0.25)
        ..lineTo(p.dx + s, p.dy)
        ..lineTo(p.dx + s * 0.25, p.dy + s * 0.25)
        ..lineTo(p.dx, p.dy + s)
        ..lineTo(p.dx - s * 0.25, p.dy + s * 0.25)
        ..lineTo(p.dx - s, p.dy)
        ..lineTo(p.dx - s * 0.25, p.dy - s * 0.25)
        ..close();
      canvas.drawPath(path, starPaint);
    }
  }
  @override
  bool shouldRepaint(covariant BurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color;
  }
}