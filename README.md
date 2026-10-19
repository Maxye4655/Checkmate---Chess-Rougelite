# Checkmate
 
A pixel-art, single-player chess roguelite made in **Godot 4.7** (GL Compatibility renderer).
 
Play chess against a computer opponent. Win and the opponent gets stronger; lose and you visit a shop to buy upgrades for your next attempt.
 
## How to run
 
1. Install Godot 4.7 or newer.
2. Open `project.godot` in the editor.
3. Press **F5** (the main scene is `main_menu.tscn`).
## How to play
 
You play White against the computer. Each game is one **round** of a **run**.
 
| Outcome | What happens |
|---|---|
| **You win** | You earn coins. Choose *Keep Playing* and the opponent starts the next round with one extra **Queen** (replacing one of its pieces). |
| **You lose** | You earn coins and a 10-second countdown starts. Choose *Continue Playing* to open the **shop**, buy upgrades, then start the next round. If the timer runs out you return to the main menu. |
| **Draw (stalemate)** | You earn coins and can replay the same round. |
 
Coins are based on how well you did: moves played, enemy material captured, a checkmate bonus and a round bonus.
 
### Controls
 
| Input | Action |
|---|---|
| Left click | Select a piece / move to a highlighted square |
| Right click | Deselect |
| `Z` or `Backspace` | Undo your last move (limited per round) |
| `R` | Start a brand-new run (resets coins and upgrades) |
| `Esc` | Back to the main menu |
 
### Shop items
 
| Item | Cost | Effect |
|---|---|---|
| Knight's Oath | 5 | A pawn becomes a Knight at the start of every round |
| Bishop's Blessing | 6 | A pawn becomes a Bishop at the start of every round |
| Rook's Vow | 9 | A pawn becomes a Rook at the start of every round |
| Queen's Gambit | 16 | A pawn becomes a Queen at the start of every round |
| Time Turner | 4 | +2 undos every round |
| Second Wind | 8 | Single use: when you would be checkmated, the board rewinds and you play on |
| Piggy Bank | 7 | Interest on held coins after each round |
| Lucky Coin | 5 | +3 coins after each round |
| Pawn Purge | 8 | One enemy pawn is removed at the start of every round |
 
Rerolling the shop costs coins and gets more expensive each time.
 
## Project structure
 
| File | Purpose |
|---|---|
| `main_menu.tscn` / `main_menu.gd` | Title screen with animated shader background |
| `board.tscn` / `board.gd` | Board rendering, input, animations, win/lose/shop flow |
| `chess_engine.gd` | Rules: move generation, check, checkmate, stalemate, undo |
| `chess_ai.gd` | Computer opponent (alpha-beta search, 1.2s per move) |
| `game_config.gd` | Autoload with shared settings (player colour) |
| `run_state.gd` | Per-run data: coins, upgrades, enemy queens, rewards |
| `shop_items.gd` | Catalog of shop items |
| `shop_screen.gd` | The shop UI |
| `menu_background.gdshader`, `board_background.gdshader` | Background shaders |
 
## Art assets
 
Existing: `Assets/CheckMate.ttf`, `Assets/Title.png`, `Assets/Play.png`, and the piece sprites `Assets/W_*.png` / `Assets/B_*.png`.
 
Still to draw (the game shows placeholders until they exist):
 
| File | Size | Used for |
|---|---|---|
| `Assets/UI/coin.png` | 16x16 | Coin counter and prices |
| `Assets/Shop/<item id>.png` | 32x32 | Shop item icons: `knights_oath`, `bishops_blessing`, `rooks_vow`, `queens_gambit`, `time_turner`, `second_wind`, `piggy_bank`, `lucky_coin`, `pawn_purge` |
| `Assets/W_King_Cracked.png` | same as `W_King.png` | Optional: shown during the final seconds of the defeat countdown |
 
To add a new shop item, add an entry in `shop_items.gd` and draw `Assets/Shop/<id>.png`.
 
## Known limitations
 
- The engine has no castling or en passant. Pawns reaching the last rank always promote to a Queen.
- The AI searches on the main thread, so the game briefly freezes while it thinks.
- No save system or sound yet.
 
