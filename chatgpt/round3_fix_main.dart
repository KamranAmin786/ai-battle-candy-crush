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
      systemNavigationBarColor: Color(0xFF190A39),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const CandyKingdomApp());
}
// ============================================================
// CONSTANTS
// ============================================================
const int boardSize = 8;
const int candyTypeCount = 6;
const int startingMoves = 30;
const int targetScore = 15000;
const Duration swapDuration = Duration(milliseconds: 230);
const Duration popDuration = Duration(milliseconds: 300);
const Duration gravityDuration = Duration(milliseconds: 460);
const List<Color> candyColors = [
  Color(0xFFFF456F),
  Color(0xFFFFB62E),
  Color(0xFF38D5F6),
  Color(0xFFA168FF),
  Color(0xFF70DF62),
  Color(0xFFFF72C9),
];
const List<Color> candyDarkColors = [
  Color(0xFFB8174C),
  Color(0xFFD17713),
  Color(0xFF168EBD),
  Color(0xFF622FBB),
  Color(0xFF318F39),
  Color(0xFFB9378D),
];
// ============================================================
// MODELS
// ============================================================
enum SpecialType {
  none,
  horizontal,
  vertical,
  rainbow,
}
class Candy {
  Candy({
    required this.id,
    required this.type,
    required this.row,
    required this.col,
    this.special = SpecialType.none,
  });
  final int id;
  int type;
  int row;
  int col;
  SpecialType special;
}
class Cell {
  const Cell(this.row, this.col);
  final int row;
  final int col;
  @override
  bool operator ==(Object other) =>
      other is Cell && other.row == row && other.col == col;
  @override
  int get hashCode => Object.hash(row, col);
}
class MatchRun {
  MatchRun(this.candies, this.horizontal);
  final List<Candy> candies;
  final bool horizontal;
}
class MatchResult {
  MatchResult(this.runs);
  final List<MatchRun> runs;
  bool get isEmpty => runs.isEmpty;
  Set<int> get ids => {
        for (final run in runs)
          for (final candy in run.candies) candy.id,
      };
}
class SpecialCreation {
  SpecialCreation(this.candy, this.type);
  final Candy candy;
  final SpecialType type;
}
class Particle {
  Particle({
    required this.velocity,
    required this.color,
    required this.radius,
    required this.rotation,
    required this.shape,
  });
  final Offset velocity;
  final Color color;
  final double radius;
  final double rotation;
  final int shape;
}
class ParticleBurst {
  ParticleBurst({
    required this.position,
    required this.particles,
  });
  final Offset position;
  final List<Particle> particles;
}
// ============================================================
// APP
// ============================================================
class CandyKingdomApp extends StatelessWidget {
  const CandyKingdomApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Candy Kingdom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF210D49),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF74C9),
          brightness: Brightness.dark,
        ),
      ),
      home: const CandyGame(),
    );
  }
}
// ============================================================
// GAME
// ============================================================
class CandyGame extends StatefulWidget {
  const CandyGame({super.key});
  @override
  State<CandyGame> createState() => _CandyGameState();
}
class _CandyGameState extends State<CandyGame>
    with TickerProviderStateMixin {
  final math.Random _random = math.Random();
  late final AnimationController _backgroundController;
  late final AnimationController _particleController;
  late final AnimationController _pulseController;
  final List<Candy> _candies = [];
  final Set<int> _poppingIds = {};
  final List<ParticleBurst> _bursts = [];
  int _nextCandyId = 0;
  int _gameVersion = 0;
  int _comboVersion = 0;
  int _messageVersion = 0;
  int _score = 0;
  int _moves = startingMoves;
  int _combo = 0;
  int _bestCombo = 0;
  bool _busy = false;
  bool _gameOver = false;
  bool _won = false;
  bool _showCombo = false;
  Cell? _selected;
  Cell? _dragOrigin;
  String _status = 'SWAP & MATCH TO WIN!';
  String _comboTitle = '';
  String _comboSubtitle = '';
  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _newGame();
  }
  @override
  void dispose() {
    _backgroundController.dispose();
    _particleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }
  bool _isActive(int version) =>
      mounted && version == _gameVersion;
  Future<void> _wait(Duration duration) =>
      Future<void>.delayed(duration);
  void _newGame() {
    _gameVersion++;
    _comboVersion++;
    _messageVersion++;
    _nextCandyId = 0;
    _candies.clear();
    _poppingIds.clear();
    _bursts.clear();
    _score = 0;
    _moves = startingMoves;
    _combo = 0;
    _bestCombo = 0;
    _busy = false;
    _gameOver = false;
    _won = false;
    _showCombo = false;
    _selected = null;
    _dragOrigin = null;
    _status = 'SWAP & MATCH TO WIN!';
    _generateBoard();
    _particleController.reset();
    if (mounted) setState(() {});
  }
  // ==========================================================
  // BOARD GENERATION
  // ==========================================================
  void _generateBoard() {
    var attempts = 0;
    do {
      _candies.clear();
      final types = List.generate(
        boardSize,
        (_) => List<int>.filled(boardSize, -1),
      );
      for (int row = 0; row < boardSize; row++) {
        for (int col = 0; col < boardSize; col++) {
          final choices = List<int>.generate(
            candyTypeCount,
            (i) => i,
          );
          if (col >= 2 &&
              types[row][col - 1] == types[row][col - 2]) {
            choices.remove(types[row][col - 1]);
          }
          if (row >= 2 &&
              types[row - 1][col] == types[row - 2][col]) {
            choices.remove(types[row - 1][col]);
          }
          final type = choices[_random.nextInt(choices.length)];
          types[row][col] = type;
          _candies.add(
            Candy(
              id: _nextCandyId++,
              type: type,
              row: row,
              col: col,
            ),
          );
        }
      }
      attempts++;
    } while (!_hasPossibleMove() && attempts < 300);
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
  // ==========================================================
  // MATCH DETECTION
  // ==========================================================
  MatchResult _findMatches() {
    final grid = _grid();
    final runs = <MatchRun>[];
    // Horizontal matches.
    for (int row = 0; row < boardSize; row++) {
      int start = 0;
      while (start < boardSize) {
        final first = grid[row][start];
        if (first == null ||
            first.special == SpecialType.rainbow) {
          start++;
          continue;
        }
        int end = start + 1;
        while (end < boardSize) {
          final next = grid[row][end];
          if (next == null ||
              next.special == SpecialType.rainbow ||
              next.type != first.type) {
            break;
          }
          end++;
        }
        if (end - start >= 3) {
          runs.add(
            MatchRun(
              [
                for (int col = start; col < end; col++)
                  grid[row][col]!,
              ],
              true,
            ),
          );
        }
        start = end;
      }
    }
    // Vertical matches.
    for (int col = 0; col < boardSize; col++) {
      int start = 0;
      while (start < boardSize) {
        final first = grid[start][col];
        if (first == null ||
            first.special == SpecialType.rainbow) {
          start++;
          continue;
        }
        int end = start + 1;
        while (end < boardSize) {
          final next = grid[end][col];
          if (next == null ||
              next.special == SpecialType.rainbow ||
              next.type != first.type) {
            break;
          }
          end++;
        }
        if (end - start >= 3) {
          runs.add(
            MatchRun(
              [
                for (int row = start; row < end; row++)
                  grid[row][col]!,
              ],
              false,
            ),
          );
        }
        start = end;
      }
    }
    return MatchResult(runs);
  }
  bool _hasPossibleMove() {
    if (_candies.any(
      (candy) => candy.special == SpecialType.rainbow,
    )) {
      return true;
    }
    for (int row = 0; row < boardSize; row++) {
      for (int col = 0; col < boardSize; col++) {
        final first = _candyAt(row, col);
        if (first == null) continue;
        for (final direction in const [
          Cell(0, 1),
          Cell(1, 0),
        ]) {
          final newRow = row + direction.row;
          final newCol = col + direction.col;
          if (newRow >= boardSize || newCol >= boardSize) {
            continue;
          }
          final second = _candyAt(newRow, newCol);
          if (second == null) continue;
          _exchange(first, second);
          final valid = !_findMatches().isEmpty;
          _exchange(first, second);
          if (valid) return true;
        }
      }
    }
    return false;
  }
  void _exchange(Candy a, Candy b) {
    final oldRow = a.row;
    final oldCol = a.col;
    a.row = b.row;
    a.col = b.col;
    b.row = oldRow;
    b.col = oldCol;
  }
  bool _areNeighbors(Cell a, Cell b) =>
      (a.row - b.row).abs() + (a.col - b.col).abs() == 1;
  // ==========================================================
  // INPUT
  // ==========================================================
  void _tapCell(Cell cell) {
    if (_busy || _gameOver) return;
    if (_selected == null) {
      setState(() => _selected = cell);
      HapticFeedback.selectionClick();
      return;
    }
    if (_selected == cell) {
      setState(() => _selected = null);
      return;
    }
    if (_areNeighbors(_selected!, cell)) {
      final previous = _selected!;
      setState(() => _selected = null);
      _trySwap(previous, cell);
    } else {
      setState(() => _selected = cell);
      HapticFeedback.selectionClick();
    }
  }
  void _swipe(Cell from, Cell to) {
    if (_busy || _gameOver || !_areNeighbors(from, to)) {
      return;
    }
    setState(() => _selected = null);
    _trySwap(from, to);
  }
  // ==========================================================
  // SWAPPING
  // ==========================================================
  Future<void> _trySwap(Cell from, Cell to) async {
    if (_busy || _gameOver || _moves <= 0) return;
    final first = _candyAt(from.row, from.col);
    final second = _candyAt(to.row, to.col);
    if (first == null || second == null) return;
    final version = _gameVersion;
    final rainbowSwap =
        first.special == SpecialType.rainbow ||
            second.special == SpecialType.rainbow;
    setState(() {
      _busy = true;
      _exchange(first, second);
    });
    HapticFeedback.lightImpact();
    await _wait(swapDuration);
    if (!_isActive(version)) return;
    final matches = _findMatches();
    if (matches.isEmpty && !rainbowSwap) {
      // Invalid swap: animate back without spending a move.
      setState(() {
        _exchange(first, second);
      });
      HapticFeedback.mediumImpact();
      await _wait(swapDuration);
      if (!_isActive(version)) return;
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _moves--;
      _combo = 0;
    });
    if (rainbowSwap) {
      final rainbow = first.special == SpecialType.rainbow
          ? first
          : second;
      final other = identical(rainbow, first) ? second : first;
      final affected = <int>{rainbow.id, other.id};
      if (other.special == SpecialType.rainbow) {
        affected.addAll(_candies.map((c) => c.id));
        _showComboPopup(
          'RAINBOW PARTY!',
          'TOTAL SUGAR BLAST',
        );
      } else {
        affected.addAll(
          _candies
              .where((c) => c.type == other.type)
              .map((c) => c.id),
        );
        if (other.special == SpecialType.horizontal ||
            other.special == SpecialType.vertical) {
          for (final candy in _candies) {
            if (candy.type == other.type &&
                candy.id != rainbow.id) {
              candy.special = other.special;
            }
          }
        }
        _showComboPopup(
          'COLOR BLAST!',
          'RAINBOW MAGIC',
        );
      }
      _combo = 1;
      await _popCandies(
        affected,
        const <int>{},
        version,
      );
      if (!_isActive(version)) return;
      await _applyGravity(version);
      if (!_isActive(version)) return;
      await _resolveBoard(version);
    } else {
      await _resolveBoard(
        version,
        preferredCandy: second,
      );
    }
    if (!_isActive(version)) return;
    if (_score >= targetScore || _moves <= 0) {
      await _wait(const Duration(milliseconds: 450));
      if (!_isActive(version)) return;
      setState(() {
        _won = _score >= targetScore;
        _gameOver = true;
        _busy = false;
        _showCombo = false;
      });
      HapticFeedback.heavyImpact();
      return;
    }
    if (!_hasPossibleMove()) {
      await _shuffleBoard(version);
    }
    if (!_isActive(version)) return;
    setState(() {
      _busy = false;
    });
  }
  // ==========================================================
  // SPECIAL CANDY CREATION
  // ==========================================================
  List<SpecialCreation> _chooseSpecials(
    MatchResult result,
    Candy? preferredCandy,
  ) {
    final creations = <SpecialCreation>[];
    final reserved = <int>{};
    final runs = [...result.runs]
      ..sort(
        (a, b) => b.candies.length.compareTo(a.candies.length),
      );
    // 4 matched -> striped candy.
    // 5+ matched -> rainbow candy.
    for (final run in runs) {
      if (run.candies.length < 4) continue;
      Candy? anchor;
      if (preferredCandy != null &&
          run.candies.any(
            (c) => c.id == preferredCandy.id,
          ) &&
          !reserved.contains(preferredCandy.id)) {
        anchor = preferredCandy;
      } else {
        final candidates = run.candies
            .where((c) => !reserved.contains(c.id))
            .toList();
        if (candidates.isEmpty) continue;
        anchor = candidates[candidates.length ~/ 2];
      }
      reserved.add(anchor.id);
      final type = run.candies.length >= 5
          ? SpecialType.rainbow
          : run.horizontal
              ? SpecialType.horizontal
              : SpecialType.vertical;
      creations.add(SpecialCreation(anchor, type));
    }
    // T and L intersections -> rainbow.
    for (int i = 0; i < result.runs.length; i++) {
      for (int j = i + 1; j < result.runs.length; j++) {
        final a = result.runs[i];
        final b = result.runs[j];
        if (a.horizontal == b.horizontal) continue;
        for (final candy in a.candies) {
          if (!b.candies.any((c) => c.id == candy.id)) {
            continue;
          }
          creations.removeWhere(
            (creation) =>
                a.candies.any(
                  (c) => c.id == creation.candy.id,
                ) ||
                b.candies.any(
                  (c) => c.id == creation.candy.id,
                ),
          );
          if (!creations.any(
            (creation) => creation.candy.id == candy.id,
          )) {
            creations.add(
              SpecialCreation(candy, SpecialType.rainbow),
            );
          }
        }
      }
    }
    return creations;
  }
  // ==========================================================
  // MATCH RESOLUTION
  // ==========================================================
  Future<void> _resolveBoard(
    int version, {
    Candy? preferredCandy,
  }) async {
    // Every pass completes all phases:
    // detect -> pop -> remove -> gravity -> refill -> wait.
    //
    // The board is NEVER unlocked before this finishes.
    int cascadeCount = 0;
    while (_isActive(version)) {
      final result = _findMatches();
      if (result.isEmpty) break;
      cascadeCount++;
      _combo = cascadeCount;
      _bestCombo = math.max(
        _bestCombo,
        _combo,
      );
      final creations = _chooseSpecials(
        result,
        preferredCandy,
      );
      preferredCandy = null;
      final preservedIds = creations
          .map((creation) => creation.candy.id)
          .toSet();
      for (final creation in creations) {
        creation.candy.special = creation.type;
      }
      if (creations.any(
        (c) => c.type == SpecialType.rainbow,
      )) {
        _showComboPopup(
          'RAINBOW BOMB!',
          'SPECTACULAR!',
        );
        _setStatus('RAINBOW CANDY CREATED!');
      } else if (creations.isNotEmpty) {
        _showComboPopup(
          'STRIPED CANDY!',
          'SWEET POWER!',
        );
        _setStatus('SPECIAL CANDY CREATED!');
      }
      if (_combo >= 2) {
        _showComboPopup(
          _combo >= 5
              ? 'SUGAR RUSH!'
              : _combo >= 4
                  ? 'UNBELIEVABLE!'
                  : _combo >= 3
                      ? 'AMAZING!'
                      : 'SWEET COMBO!',
          'CHAIN x$_combo',
        );
      }
      await _popCandies(
        result.ids,
        preservedIds,
        version,
      );
      if (!_isActive(version)) return;
      await _applyGravity(version);
      if (!_isActive(version)) return;
      await _wait(
        const Duration(milliseconds: 90),
      );
    }
  }
  // ==========================================================
  // SPECIAL CANDY EXPLOSIONS
  // ==========================================================
  Set<int> _expandSpecialEffects(
    Set<int> initial,
    Set<int> protectedIds,
  ) {
    final affected = <int>{...initial};
    final queue = <int>[...initial];
    final triggered = <int>{};
    final byId = {
      for (final candy in _candies) candy.id: candy,
    };
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (protectedIds.contains(id)) continue;
      final candy = byId[id];
      if (candy == null ||
          candy.special == SpecialType.none ||
          !triggered.add(id)) {
        continue;
      }
      final additional = <int>{};
      switch (candy.special) {
        case SpecialType.horizontal:
          additional.addAll(
            _candies
                .where((c) => c.row == candy.row)
                .map((c) => c.id),
          );
          break;
        case SpecialType.vertical:
          additional.addAll(
            _candies
                .where((c) => c.col == candy.col)
                .map((c) => c.id),
          );
          break;
        case SpecialType.rainbow:
          final candidates = _candies
              .where(
                (c) => c.special != SpecialType.rainbow,
              )
              .toList();
          if (candidates.isNotEmpty) {
            final chosen = candidates[
                _random.nextInt(candidates.length)].type;
            additional.addAll(
              _candies
                  .where((c) => c.type == chosen)
                  .map((c) => c.id),
            );
          }
          break;
        case SpecialType.none:
          break;
      }
      for (final newId in additional) {
        if (affected.add(newId)) {
          queue.add(newId);
        }
      }
    }
    return affected;
  }
  // ==========================================================
  // POPPING + PARTICLES
  // ==========================================================
  Future<void> _popCandies(
    Set<int> initialIds,
    Set<int> protectedIds,
    int version,
  ) async {
    if (!_isActive(version)) return;
    final affected = _expandSpecialEffects(
      initialIds,
      protectedIds,
    );
    affected.removeAll(protectedIds);
    if (affected.isEmpty) return;
    final popped = _candies
        .where((c) => affected.contains(c.id))
        .toList();
    final specialCount = popped
        .where(
          (c) => c.special != SpecialType.none,
        )
        .length;
    final multiplier = math.max(1, _combo);
    final earned = popped.length * 65 * multiplier +
        specialCount * 250 +
        (popped.length >= 8 ? 500 * multiplier : 0);
    setState(() {
      _score += earned;
      _poppingIds.addAll(affected);
      _bursts.clear();
      for (final candy in popped) {
        _createParticles(candy);
      }
    });
    _particleController.forward(from: 0);
    if (_combo >= 3 || popped.length >= 8) {
      HapticFeedback.heavyImpact();
      _setStatus('SUGAR EXPLOSION!');
    } else {
      HapticFeedback.mediumImpact();
      if (_combo <= 1 && specialCount == 0) {
        _setStatus('SWEET!');
      }
    }
    await _wait(popDuration);
    if (!_isActive(version)) return;
    // Remove only after the pop animation has completed.
    setState(() {
      _candies.removeWhere(
        (c) => affected.contains(c.id),
      );
      _poppingIds.clear();
    });
  }
  void _createParticles(Candy candy) {
    final particles = <Particle>[];
    final count =
        candy.special == SpecialType.none ? 13 : 25;
    for (int i = 0; i < count; i++) {
      final angle = i * math.pi * 2 / count +
          _random.nextDouble() * 0.24;
      final speed = 0.65 + _random.nextDouble() * 0.85;
      particles.add(
        Particle(
          velocity: Offset(
            math.cos(angle) * speed,
            math.sin(angle) * speed,
          ),
          color: i % 4 == 0
              ? Colors.white
              : i % 5 == 0
                  ? const Color(0xFFFFE58B)
                  : candyColors[candy.type],
          radius: 2 + _random.nextDouble() * 3,
          rotation: _random.nextDouble() * math.pi,
          shape: i % 4,
        ),
      );
    }
    _bursts.add(
      ParticleBurst(
        position: Offset(
          candy.col + 0.5,
          candy.row + 0.5,
        ),
        particles: particles,
      ),
    );
  }
  // ==========================================================
  // GRAVITY AND REFILL - FIXED
  // ==========================================================
  Future<void> _applyGravity(int version) async {
    if (!_isActive(version)) return;
    // Store new candies and their final destinations.
    // New candy objects BEGIN above the board (negative rows).
    //
    // This is important: AnimatedPositioned must see the candy
    // at its starting position in one rendered frame before we
    // move it to the destination in a later frame.
    final newCandies = <Candy>[];
    final destinations = <int, int>{};
    setState(() {
      for (int col = 0; col < boardSize; col++) {
        // Collect surviving candies, bottom first.
        final column = _candies
            .where((c) => c.col == col && c.row >= 0)
            .toList()
          ..sort(
            (a, b) => b.row.compareTo(a.row),
          );
        int targetRow = boardSize - 1;
        // Drop existing candies into gaps.
        // AnimatedPositioned observes candy.row directly.
        for (final candy in column) {
          candy.row = targetRow;
          targetRow--;
        }
        // All rows from 0 through targetRow need new candy.
        //
        // Each new candy starts above the top of the board.
        // Its final position is stored separately until
        // the next rendered frame.
        final missingCount = targetRow + 1;
        for (int row = targetRow; row >= 0; row--) {
          final spawnRow = row - missingCount;
          final candy = Candy(
            id: _nextCandyId++,
            type: _random.nextInt(candyTypeCount),
            row: spawnRow,
            col: col,
          );
          destinations[candy.id] = row;
          newCandies.add(candy);
          _candies.add(candy);
        }
      }
    });
    // Allow the above-the-board positions to actually render.
    await WidgetsBinding.instance.endOfFrame;
    if (!_isActive(version)) return;
    // Move ALL new candies to their final positive board rows.
    // Existing candies have already been moved to their final
    // coordinates. Both now animate smoothly in parallel.
    setState(() {
      for (final candy in newCandies) {
        candy.row = destinations[candy.id]!;
      }
    });
    // Wait for all falling animations to finish.
    await _wait(gravityDuration);
    if (!_isActive(version)) return;
    // At this point, the model must contain exactly 64 candies,
    // one candy per square, before cascade detection continues.
    _bursts.clear();
    assert(_candies.length == boardSize * boardSize);
    assert(() {
      final occupied = <Cell>{};
      for (final candy in _candies) {
        final cell = Cell(candy.row, candy.col);
        if (candy.row < 0 ||
            candy.row >= boardSize ||
            candy.col < 0 ||
            candy.col >= boardSize ||
            !occupied.add(cell)) {
          throw StateError(
            'Invalid board after gravity at '
            '(${candy.row}, ${candy.col}).',
          );
        }
      }
      return occupied.length == boardSize * boardSize;
    }());
  }
  // ==========================================================
  // SHUFFLE
  // ==========================================================
  Future<void> _shuffleBoard(int version) async {
    if (!_isActive(version)) return;
    _setStatus('MAGICAL SHUFFLE!');
    _showComboPopup(
      'SUGAR SHUFFLE!',
      'NEW POSSIBILITIES',
    );
    setState(() {
      _poppingIds.addAll(
        _candies.map((c) => c.id),
      );
    });
    await _wait(
      const Duration(milliseconds: 300),
    );
    if (!_isActive(version)) return;
    setState(() {
      _poppingIds.clear();
      _bursts.clear();
      _generateBoard();
    });
    await _wait(
      const Duration(milliseconds: 350),
    );
  }
  // ==========================================================
  // MESSAGES
  // ==========================================================
  void _setStatus(String text) {
    final version = ++_messageVersion;
    if (mounted) {
      setState(() => _status = text);
    }
    Future<void>.delayed(
      const Duration(milliseconds: 1600),
      () {
        if (!mounted ||
            version != _messageVersion ||
            _gameOver) {
          return;
        }
        setState(() {
          _status = 'SWAP & MATCH TO WIN!';
        });
      },
    );
  }
  void _showComboPopup(
    String title,
    String subtitle,
  ) {
    final version = ++_comboVersion;
    if (mounted) {
      setState(() {
        _comboTitle = title;
        _comboSubtitle = subtitle;
        _showCombo = true;
      });
    }
    Future<void>.delayed(
      const Duration(milliseconds: 1100),
      () {
        if (!mounted || version != _comboVersion) {
          return;
        }
        setState(() => _showCombo = false);
      },
    );
  }
  String _formatScore(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
  double get _progress =>
      (_score / targetScore).clamp(0.0, 1.0);
  int get _stars {
    if (_score >= targetScore) return 3;
    if (_score >= targetScore * 0.65) return 2;
    if (_score >= targetScore * 0.3) return 1;
    return 0;
  }
  // ==========================================================
  // MAIN UI
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(screen),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                final compact = height < 720;
                final boardWidth = math.min(
                  screen.width - 24,
                  math.min(
                    485.0,
                    height * (compact ? 0.54 : 0.58),
                  ),
                );
                return Column(
                  children: [
                    SizedBox(height: compact ? 7 : 17),
                    _buildTitle(compact),
                    SizedBox(height: compact ? 11 : 21),
                    _buildStats(),
                    SizedBox(height: compact ? 11 : 20),
                    _buildTarget(),
                    const Spacer(),
                    _buildBoard(boardWidth),
                    const Spacer(),
                    _buildFooter(compact),
                    SizedBox(height: compact ? 8 : 20),
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
  // ==========================================================
  // BACKGROUND
  // ==========================================================
  Widget _buildBackground(Size size) {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        final t =
            _backgroundController.value * math.pi * 2;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0, 0.4, 0.8, 1],
              colors: [
                Color(0xFF6533AA),
                Color(0xFF3F1C76),
                Color(0xFF260F52),
                Color(0xFF170A36),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: -130 + math.sin(t) * 35,
                top: -170,
                child: _glow(
                  380,
                  const Color(0xFFFF6DD3)
                      .withValues(alpha: 0.27),
                ),
              ),
              Positioned(
                right: -180 + math.cos(t) * 40,
                bottom: -140,
                child: _glow(
                  460,
                  const Color(0xFF7C80FF)
                      .withValues(alpha: 0.23),
                ),
              ),
              for (int i = 0; i < 36; i++)
                Positioned(
                  left: ((math.sin(i * 13.91) + 1) / 2) *
                      size.width,
                  top: ((math.cos(i * 9.73) + 1) / 2) *
                          size.height +
                      math.sin(t + i) * 10,
                  child: Opacity(
                    opacity: 0.14 + (i % 5) * 0.075,
                    child: Icon(
                      i % 4 == 0
                          ? Icons.auto_awesome
                          : Icons.circle,
                      color: i.isEven
                          ? Colors.white
                          : const Color(0xFFFFB4E6),
                      size: i % 4 == 0 ? 12 : 3.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
  Widget _glow(double size, Color color) {
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
  // ==========================================================
  // TITLE
  // ==========================================================
  Widget _buildTitle(bool compact) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.star_rounded,
              color: Color(0xFFFFD364),
              size: 25,
            ),
            const SizedBox(width: 5),
            ShaderMask(
              shaderCallback: (bounds) =>
                  const LinearGradient(
                colors: [
                  Color(0xFFFFF7C3),
                  Color(0xFFFFD16D),
                  Color(0xFFFF83C6),
                ],
              ).createShader(bounds),
              child: Text(
                'CANDY KINGDOM',
                style: TextStyle(
                  fontSize: compact ? 26 : 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  height: 1.1,
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                      color: Color(0xFF9A338C),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.star_rounded,
              color: Color(0xFFFFD364),
              size: 25,
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          'A SWEET LITTLE ADVENTURE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: Color(0xFFDEC5F5),
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
  // ==========================================================
  // SCORE + MOVES
  // ==========================================================
  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              'SCORE',
              _formatScore(_score),
              Icons.stars_rounded,
              const Color(0xFFFFD361),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              'MOVES LEFT',
              '$_moves',
              Icons.bolt_rounded,
              _moves <= 5
                  ? const Color(0xFFFF718F)
                  : const Color(0xFF6DEAF8),
            ),
          ),
        ],
      ),
    );
  }
  Widget _statCard(
    String label,
    String value,
    IconData icon,
    Color accent,
  ) {
    return Container(
      height: 83,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.19),
            Colors.white.withValues(alpha: 0.07),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      color:
                          Colors.white.withValues(alpha: 0.65),
                      fontSize: 10,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    );
                  },
                  child: FittedBox(
                    key: ValueKey(value),
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        height: 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // ==========================================================
  // LEVEL TARGET
  // ==========================================================
  Widget _buildTarget() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 19),
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF1D0C44)
            .withValues(alpha: 0.49),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD69CFF)
              .withValues(alpha: 0.23),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_rounded,
                color: Color(0xFFFFD17A),
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'LEVEL 1',
                style: TextStyle(
                  color: Color(0xFFFFD88C),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Text(
                '${_formatScore(math.min(_score, targetScore))}'
                ' / ${_formatScore(targetScore)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 13,
                    decoration: BoxDecoration(
                      color: const Color(0xFF170B37),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white
                            .withValues(alpha: 0.11),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(
                      milliseconds: 650,
                    ),
                    curve: Curves.easeOutCubic,
                    height: 13,
                    width: constraints.maxWidth * _progress,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF74BF),
                          Color(0xFFFFAC61),
                          Color(0xFFFFE676),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB95C)
                              .withValues(alpha: 0.55),
                          blurRadius: 9,
                        ),
                      ],
                    ),
                  ),
                  for (final milestone in [0.3, 0.65, 1.0])
                    Positioned(
                      left: constraints.maxWidth * milestone - 10,
                      top: -6,
                      child: Icon(
                        Icons.star_rounded,
                        size: 23,
                        color: _progress >= milestone
                            ? const Color(0xFFFFD65F)
                            : const Color(0xFF81679D),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 9),
          const Text(
            'Reach the target score to win!',
            style: TextStyle(
              color: Color(0xFFBFA5DB),
              fontWeight: FontWeight.w500,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
  // ==========================================================
  // BOARD UI
  // ==========================================================
  Widget _buildBoard(double width) {
    final innerWidth = width - 16;
    final cellSize = innerWidth / boardSize;
    return Container(
      width: width,
      height: width,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFD7F6),
            Color(0xFFCA85F0),
            Color(0xFF6A3AAA),
            Color(0xFFEE98DD),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF63CF)
                .withValues(alpha: 0.28),
            blurRadius: 35,
            spreadRadius: 3,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 13),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF221044),
          borderRadius: BorderRadius.circular(21),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: innerWidth,
            height: innerWidth,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                _boardTiles(cellSize),
                // Every candy is positioned directly from its
                // current row and column. No stale visualRow.
                for (final candy in _candies)
                  _candyWidget(candy, cellSize),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _particleController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: ParticlePainter(
                            bursts: _bursts,
                            progress:
                                _particleController.value,
                            cellSize: cellSize,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (_showCombo) _comboOverlay(cellSize),
                _gestureLayer(cellSize),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _boardTiles(double cell) {
    return Stack(
      children: [
        Container(color: const Color(0xFF311659)),
        for (int row = 0; row < boardSize; row++)
          for (int col = 0; col < boardSize; col++)
            Positioned(
              left: col * cell,
              top: row * cell,
              width: cell,
              height: cell,
              child: Container(
                decoration: BoxDecoration(
                  color: (row + col).isEven
                      ? const Color(0xFF7442A2)
                          .withValues(alpha: 0.49)
                      : const Color(0xFF4D277A)
                          .withValues(alpha: 0.28),
                  border: Border.all(
                    color: Colors.white
                        .withValues(alpha: 0.025),
                    width: 0.5,
                  ),
                ),
              ),
            ),
      ],
    );
  }
  Widget _candyWidget(Candy candy, double cellSize) {
    final selected =
        _selected == Cell(candy.row, candy.col);
    final popping = _poppingIds.contains(candy.id);
    return AnimatedPositioned(
      key: ValueKey('candy-${candy.id}'),
      duration: gravityDuration,
      curve: Curves.easeOutCubic,
      left: candy.col * cellSize,
      top: candy.row * cellSize,
      width: cellSize,
      height: cellSize,
      child: AnimatedScale(
        scale: popping ? 0.01 : (selected ? 1.13 : 1),
        duration: popping
            ? popDuration
            : const Duration(milliseconds: 150),
        curve: popping
            ? Curves.easeInBack
            : Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: popping ? 0 : 1,
          duration: popDuration,
          child: Padding(
            padding: EdgeInsets.all(cellSize * 0.045),
            child: CustomPaint(
              painter: CandyPainter(
                type: candy.type,
                special: candy.special,
                selected: selected,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
  Widget _comboOverlay(double cellSize) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_comboVersion),
            tween: Tween(begin: 0.15, end: 1),
            duration: const Duration(milliseconds: 480),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Transform.rotate(
              angle: -0.07,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Text(
                        _comboTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: cellSize * 0.55,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 6
                            ..strokeJoin = StrokeJoin.round
                            ..color = const Color(0xFF702281),
                        ),
                      ),
                      Text(
                        _comboTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: cellSize * 0.55,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: const Color(0xFFFFE57A),
                          shadows: const [
                            Shadow(
                              color: Color(0xFFFF9B38),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9F3FA7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFFFBBEE),
                      ),
                    ),
                    child: Text(
                      _comboSubtitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  // ==========================================================
  // GESTURE INPUT
  // ==========================================================
  Widget _gestureLayer(double cellSize) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          final cell = _cellFromOffset(
            details.localPosition,
            cellSize,
          );
          if (cell != null) _tapCell(cell);
        },
        onPanStart: (details) {
          _dragOrigin = _cellFromOffset(
            details.localPosition,
            cellSize,
          );
        },
        onPanUpdate: (details) {
          final start = _dragOrigin;
          if (start == null || _busy) return;
          final dx = details.localPosition.dx -
              (start.col + 0.5) * cellSize;
          final dy = details.localPosition.dy -
              (start.row + 0.5) * cellSize;
          if (math.max(dx.abs(), dy.abs()) <
              cellSize * 0.38) {
            return;
          }
          final Cell end;
          if (dx.abs() > dy.abs()) {
            end = Cell(
              start.row,
              start.col + (dx > 0 ? 1 : -1),
            );
          } else {
            end = Cell(
              start.row + (dy > 0 ? 1 : -1),
              start.col,
            );
          }
          _dragOrigin = null;
          if (_validCell(end)) {
            _swipe(start, end);
          }
        },
        onPanEnd: (_) => _dragOrigin = null,
        onPanCancel: () => _dragOrigin = null,
      ),
    );
  }
  Cell? _cellFromOffset(
    Offset offset,
    double cellSize,
  ) {
    final row = (offset.dy / cellSize).floor();
    final col = (offset.dx / cellSize).floor();
    final cell = Cell(row, col);
    return _validCell(cell) ? cell : null;
  }
  bool _validCell(Cell cell) =>
      cell.row >= 0 &&
      cell.row < boardSize &&
      cell.col >= 0 &&
      cell.col < boardSize;
  // ==========================================================
  // FOOTER
  // ==========================================================
  Widget _buildFooter(bool compact) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 230),
          child: Text(
            _status,
            key: ValueKey(_status),
            style: const TextStyle(
              color: Color(0xFFFFD97B),
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1.7,
              shadows: [
                Shadow(
                  color: Color(0xFFFF69B4),
                  blurRadius: 11,
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
              color: Colors.white.withValues(alpha: 0.52),
              size: 16,
            ),
            const SizedBox(width: 7),
            Text(
              'Tap or swipe • Match 4+ for power-ups!',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
  // ==========================================================
  // GAME OVER
  // ==========================================================
  Widget _buildGameOver() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF100623)
            .withValues(alpha: 0.86),
        child: SafeArea(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.5, end: 1),
              duration: const Duration(milliseconds: 670),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: Container(
                width: math.min(
                  MediaQuery.sizeOf(context).width - 38,
                  390,
                ),
                padding: const EdgeInsets.fromLTRB(
                  24,
                  28,
                  24,
                  29,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(31),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF8950C9),
                      Color(0xFF592C99),
                      Color(0xFF38186A),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFFFB8E9),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF77CC)
                          .withValues(alpha: 0.38),
                      blurRadius: 55,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _won
                          ? Icons.emoji_events_rounded
                          : Icons.auto_awesome,
                      color: const Color(0xFFFFD96B),
                      size: 49,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      _won
                          ? 'LEVEL COMPLETE!'
                          : 'SWEET FINISH!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFE38D),
                        fontWeight: FontWeight.w900,
                        fontSize: 29,
                        letterSpacing: -0.6,
                        shadows: [
                          Shadow(
                            color: Color(0xFFBB4E95),
                            blurRadius: 15,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _won
                          ? 'You conquered the candy kingdom!'
                          : 'So close! Give it another try!',
                      style: const TextStyle(
                        color: Color(0xFFEBD4FA),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < 3; i++)
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: i < _stars
                                    ? 1 +
                                        _pulseController.value *
                                            0.06
                                    : 1,
                                child: child,
                              );
                            },
                            child: Icon(
                              Icons.star_rounded,
                              size: i == 1 ? 67 : 54,
                              color: i < _stars
                                  ? const Color(0xFFFFD658)
                                  : const Color(0xFF9979BB),
                              shadows: i < _stars
                                  ? const [
                                      Shadow(
                                        color:
                                            Color(0xFFFFCB52),
                                        blurRadius: 16,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 17),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0A43)
                            .withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(21),
                        border: Border.all(
                          color: Colors.white
                              .withValues(alpha: 0.13),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'FINAL SCORE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFCDB2E4),
                              letterSpacing: 2.1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _formatScore(_score),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 46,
                            ),
                          ),
                          const Divider(
                            color: Color(0xFF684A8C),
                            height: 22,
                          ),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Target',
                                style: TextStyle(
                                  color: Color(0xFFD5BDED),
                                ),
                              ),
                              Text(
                                _formatScore(targetScore),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Best combo',
                                style: TextStyle(
                                  color: Color(0xFFD5BDED),
                                ),
                              ),
                              Text(
                                'x$_bestCombo',
                                style: const TextStyle(
                                  color: Color(0xFFFFDB79),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Moves remaining',
                                style: TextStyle(
                                  color: Color(0xFFD5BDED),
                                ),
                              ),
                              Text(
                                '$_moves',
                                style: const TextStyle(
                                  color: Color(0xFF85EAF7),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _newGame();
                      },
                      child: Container(
                        width: double.infinity,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFFFE282),
                              Color(0xFFFFB345),
                              Color(0xFFEB8429),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFFFFF3B1),
                            width: 1.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xFFAE4E27),
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.replay_rounded,
                              color: Color(0xFF71336A),
                              size: 26,
                            ),
                            SizedBox(width: 9),
                            Text(
                              'PLAY AGAIN',
                              style: TextStyle(
                                color: Color(0xFF71336A),
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
// ============================================================
// CANDY PAINTER
// ============================================================
class CandyPainter extends CustomPainter {
  CandyPainter({
    required this.type,
    required this.special,
    required this.selected,
  });
  final int type;
  final SpecialType special;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    if (selected) {
      canvas.drawCircle(
        center,
        w * 0.53,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.47)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            9,
          ),
      );
    }
    if (special == SpecialType.rainbow) {
      _paintRainbow(canvas, size);
      return;
    }
    canvas.save();
    canvas.translate(0, h * 0.045);
    final path = _shape(type, w, h);
    canvas.drawShadow(
      path,
      Colors.black.withValues(alpha: 0.38),
      3.5,
      false,
    );
    final bounds = Rect.fromLTWH(0, 0, w, h);
    final base = candyColors[type];
    final dark = candyDarkColors[type];
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.60),
          radius: 1.15,
          colors: [
            Color.lerp(base, Colors.white, 0.62)!,
            base,
            dark,
          ],
          stops: const [0, 0.58, 1],
        ).createShader(bounds),
    );
    final gloss = Path()
      ..moveTo(w * 0.25, h * 0.40)
      ..quadraticBezierTo(
        w * 0.29,
        h * 0.20,
        w * 0.49,
        h * 0.18,
      );
    canvas.drawPath(
      gloss,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.72)
        ..strokeWidth = w * 0.07
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawOval(
      Rect.fromLTWH(
        w * 0.30,
        h * 0.22,
        w * 0.20,
        h * 0.09,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    _paintDetail(canvas, size);
    if (special == SpecialType.horizontal ||
        special == SpecialType.vertical) {
      _paintStripes(canvas, size);
    }
    canvas.restore();
  }
  Path _shape(int type, double w, double h) {
    switch (type) {
      case 0:
        return Path()
          ..moveTo(w * 0.50, h * 0.83)
          ..cubicTo(
            w * 0.27, h * 0.68,
            w * 0.07, h * 0.52,
            w * 0.13, h * 0.32,
          )
          ..cubicTo(
            w * 0.18, h * 0.13,
            w * 0.40, h * 0.10,
            w * 0.50, h * 0.26,
          )
          ..cubicTo(
            w * 0.65, h * 0.10,
            w * 0.88, h * 0.17,
            w * 0.88, h * 0.36,
          )
          ..cubicTo(
            w * 0.92, h * 0.56,
            w * 0.69, h * 0.74,
            w * 0.50, h * 0.83,
          )
          ..close();
      case 1:
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                w * 0.12,
                h * 0.12,
                w * 0.76,
                h * 0.76,
              ),
              Radius.circular(w * 0.23),
            ),
          );
      case 2:
        return Path()
          ..moveTo(w * 0.5, h * 0.05)
          ..cubicTo(
            w * 0.78, h * 0.15,
            w * 0.93, h * 0.37,
            w * 0.91, h * 0.53,
          )
          ..cubicTo(
            w * 0.83, h * 0.77,
            w * 0.65, h * 0.92,
            w * 0.5, h * 0.94,
          )
          ..cubicTo(
            w * 0.28, h * 0.90,
            w * 0.10, h * 0.73,
            w * 0.09, h * 0.53,
          )
          ..cubicTo(
            w * 0.10, h * 0.33,
            w * 0.28, h * 0.13,
            w * 0.5, h * 0.05,
          )
          ..close();
      case 3:
        return Path()
          ..moveTo(w * 0.50, h * 0.06)
          ..quadraticBezierTo(
            w * 0.67, h * 0.07,
            w * 0.76, h * 0.25,
          )
          ..quadraticBezierTo(
            w * 0.94, h * 0.37,
            w * 0.92, h * 0.52,
          )
          ..quadraticBezierTo(
            w * 0.91, h * 0.70,
            w * 0.75, h * 0.80,
          )
          ..quadraticBezierTo(
            w * 0.62, h * 0.95,
            w * 0.50, h * 0.92,
          )
          ..quadraticBezierTo(
            w * 0.32, h * 0.92,
            w * 0.25, h * 0.80,
          )
          ..quadraticBezierTo(
            w * 0.08, h * 0.71,
            w * 0.08, h * 0.52,
          )
          ..quadraticBezierTo(
            w * 0.08, h * 0.35,
            w * 0.25, h * 0.24,
          )
          ..quadraticBezierTo(
            w * 0.36, h * 0.06,
            w * 0.50, h * 0.06,
          )
          ..close();
      case 4:
        return Path()
          ..moveTo(w * 0.50, h * 0.10)
          ..cubicTo(
            w * 0.75, h * 0.05,
            w * 0.94, h * 0.34,
            w * 0.88, h * 0.50,
          )
          ..cubicTo(
            w * 0.98, h * 0.75,
            w * 0.69, h * 0.96,
            w * 0.50, h * 0.88,
          )
          ..cubicTo(
            w * 0.23, h * 0.96,
            w * 0.05, h * 0.73,
            w * 0.12, h * 0.50,
          )
          ..cubicTo(
            w * 0.04, h * 0.29,
            w * 0.27, h * 0.08,
            w * 0.50, h * 0.10,
          )
          ..close();
      default:
        return Path()
          ..addOval(
            Rect.fromLTWH(
              w * 0.09,
              h * 0.08,
              w * 0.82,
              h * 0.83,
            ),
          );
    }
  }
  void _paintDetail(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final detail = Paint()
      ..color = Colors.white.withValues(alpha: 0.43)
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    switch (type) {
      case 0:
        canvas.drawArc(
          Rect.fromLTWH(
            w * 0.30,
            h * 0.31,
            w * 0.40,
            h * 0.35,
          ),
          0.2,
          math.pi * 0.75,
          false,
          detail,
        );
        break;
      case 1:
        for (double x = 0.35; x < 0.78; x += 0.21) {
          canvas.drawLine(
            Offset(w * x, h * 0.36),
            Offset(w * (x - 0.08), h * 0.68),
            detail,
          );
        }
        break;
      case 2:
        canvas.drawLine(
          Offset(w * 0.28, h * 0.54),
          Offset(w * 0.72, h * 0.54),
          detail,
        );
        canvas.drawLine(
          Offset(w * 0.50, h * 0.32),
          Offset(w * 0.50, h * 0.73),
          detail,
        );
        break;
      case 3:
        canvas.drawArc(
          Rect.fromLTWH(
            w * 0.32,
            h * 0.33,
            w * 0.38,
            h * 0.37,
          ),
          -0.7,
          math.pi * 1.5,
          false,
          detail,
        );
        break;
      case 4:
        final leaf = Path()
          ..moveTo(w * 0.30, h * 0.58)
          ..quadraticBezierTo(
            w * 0.45, h * 0.30,
            w * 0.71, h * 0.45,
          );
        canvas.drawPath(leaf, detail);
        break;
      default:
        canvas.drawArc(
          Rect.fromLTWH(
            w * 0.28,
            h * 0.27,
            w * 0.44,
            h * 0.44,
          ),
          -0.6,
          math.pi * 1.55,
          false,
          detail,
        );
        break;
    }
  }
  void _paintStripes(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = _shape(type, w, h);
    canvas.save();
    canvas.clipPath(path);
    final stripePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.12;
    final shadowPaint = Paint()
      ..color =
          candyDarkColors[type].withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.19;
    if (special == SpecialType.horizontal) {
      for (final y in [0.38, 0.67]) {
        final a = Offset(-w * 0.1, h * y);
        final b = Offset(w * 1.1, h * y);
        canvas.drawLine(a, b, shadowPaint);
        canvas.drawLine(a, b, stripePaint);
      }
    } else {
      for (final x in [0.36, 0.65]) {
        final a = Offset(w * x, -h * 0.1);
        final b = Offset(w * x, h * 1.1);
        canvas.drawLine(a, b, shadowPaint);
        canvas.drawLine(a, b, stripePaint);
      }
    }
    canvas.restore();
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.20),
      w * 0.105,
      Paint()
        ..color = const Color(0xFFFFE36B),
    );
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.20),
      w * 0.052,
      Paint()..color = Colors.white,
    );
  }
  void _paintRainbow(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w * 0.42;
    final shadowPath = Path()
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: radius,
        ),
      );
    canvas.drawShadow(
      shadowPath,
      Colors.black,
      5,
      false,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          colors: [
            Color(0xFF8A6A83),
            Color(0xFF48304B),
            Color(0xFF21192D),
          ],
        ).createShader(
          Rect.fromCircle(
            center: center,
            radius: radius,
          ),
        ),
    );
    final ringColors = [
      const Color(0xFFFF5378),
      const Color(0xFFFFC446),
      const Color(0xFF77E568),
      const Color(0xFF54DAFF),
      const Color(0xFFAF79FF),
      const Color(0xFFFF71D5),
    ];
    for (int i = 0; i < ringColors.length; i++) {
      final angle = i * math.pi / 3;
      final position = Offset(
        center.dx + math.cos(angle) * radius * 0.67,
        center.dy + math.sin(angle) * radius * 0.67,
      );
      canvas.drawCircle(
        position,
        w * 0.105,
        Paint()..color = ringColors[i],
      );
      canvas.drawCircle(
        position.translate(
          -w * 0.023,
          -h * 0.023,
        ),
        w * 0.04,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.75),
      );
    }
    final star = Path();
    final outer = w * 0.25;
    final inner = w * 0.115;
    for (int i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? outer : inner;
      final p = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(
      star,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFFE37D),
          ],
        ).createShader(
          Rect.fromCircle(
            center: center,
            radius: outer,
          ),
        ),
    );
    canvas.drawCircle(
      Offset(w * 0.33, h * 0.24),
      w * 0.085,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }
  @override
  bool shouldRepaint(covariant CandyPainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.special != special ||
      oldDelegate.selected != selected;
}
// ============================================================
// PARTICLE PAINTER
// ============================================================
class ParticlePainter extends CustomPainter {
  ParticlePainter({
    required this.bursts,
    required this.progress,
    required this.cellSize,
  });
  final List<ParticleBurst> bursts;
  final double progress;
  final double cellSize;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    for (final burst in bursts) {
      final origin = Offset(
        burst.position.dx * cellSize,
        burst.position.dy * cellSize,
      );
      for (final particle in burst.particles) {
        final distance = cellSize * 1.05 * progress;
        final position = origin +
            Offset(
              particle.velocity.dx * distance,
              particle.velocity.dy * distance +
                  progress * progress * cellSize * 0.4,
            );
        final opacity =
            (1 - progress).clamp(0.0, 1.0);
        final radius =
            particle.radius * (1 - progress * 0.8);
        final paint = Paint()
          ..color =
              particle.color.withValues(alpha: opacity);
        if (particle.shape == 0) {
          _drawSparkle(
            canvas,
            position,
            radius * 1.65,
            paint,
          );
        } else if (particle.shape == 1) {
          canvas.save();
          canvas.translate(
            position.dx,
            position.dy,
          );
          canvas.rotate(
            particle.rotation + progress * 5,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: radius * 2,
                height: radius * 1.2,
              ),
              const Radius.circular(1.5),
            ),
            paint,
          );
          canvas.restore();
        } else {
          canvas.drawCircle(
            position,
            radius,
            paint,
          );
        }
      }
      if (progress < 0.75) {
        final ringPaint = Paint()
          ..color = Colors.white.withValues(
            alpha: 0.55 * (1 - progress),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - progress);
        canvas.drawCircle(
          origin,
          cellSize * progress * 0.8,
          ringPaint,
        );
      }
    }
  }
  void _drawSparkle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + radius * 0.16,
        center.dy - radius * 0.16,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + radius * 0.16,
        center.dy + radius * 0.16,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.16,
        center.dy + radius * 0.16,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.16,
        center.dy - radius * 0.16,
        center.dx,
        center.dy - radius,
      )
      ..close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.bursts != bursts;
}