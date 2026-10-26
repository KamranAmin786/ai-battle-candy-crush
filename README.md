# AI Battle: ChatGPT vs Gemini vs Claude build Candy Crush in Flutter

Each AI got the same prompt and returned one `main.dart` with no packages. The code here is exactly what each AI wrote. Nothing was edited by hand.

## How to run any version

```bash
flutter create candy_battle
cd candy_battle
# copy one of the files below over lib/main.dart
flutter run
```

## Files

| Folder | Round 1 (main prompt) | Round 2 (fix) | Round 3 (polish) |
|---|---|---|---|
| `chatgpt/` | `round1_main.dart`, built first try | not needed | `round3_main.dart` has a refill bug; `round3_fix_main.dart` is the fixed version |
| `gemini/` | `round1_main.dart`, 3 compile errors | `round2_main.dart` | `round3_main.dart` |
| `claude/` | `round1_main.dart`, 1 compile error | `round2_main.dart` | `round3_main.dart` |

Final versions to play: `chatgpt/round3_fix_main.dart`, `gemini/round3_main.dart`, `claude/round3_main.dart`.

## The prompts

**Round 1**
> Make a Candy Crush style match-3 game in Flutter. Put everything in one file, lib/main.dart, and use no packages beyond Flutter itself.
> It must have: an 8x8 board of colorful candies, swap two neighbouring candies by tapping or swiping, matches of 3 or more disappear, candies fall down and new ones drop in, chain combos, a score, a moves counter (30 moves), and a game over screen with restart.
> Make it look and feel like a real mobile game: smooth animations, nice colors, satisfying effects. Reply with only the full code.

**Round 2 (fix)**
> Here is the problem: (the exact build error). Fix it and reply with the full main.dart.

**Round 3**
> Now make it look amazing: special candies for 4 and 5 matches, a combo text popup, particles when candies pop, and a level target. Reply with the full main.dart.

Video: Orhan Yazdan on YouTube.
