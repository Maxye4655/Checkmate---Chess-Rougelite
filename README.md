```
	_______  ________  ________  ________  ____ ___  ________  ________  ________  ________ 
  //       \/    /   \/        \/        \/    /   \/        \/        \/        \/        \
 //        /         /         /         /         /         /         /        _/         /
/       --/         /        _/       --/        _/         /         //       //        _/ 
\________/\___/____/\________/\________/\____/___/\__/__/__/\___/____/ \______/ \________/  ```

#Checkmate

A pixel-art, single-player (So far...) chess rougelike made in Godot 4.7.

Play chess against a computer opponent. Win and the opponent gets stronger, Lose and you visit a shop to purchase upgrades for your next run. Complete challenges to unlock stronger shop items that stay unlocked between runs.

## How to run

### Manual 

1. Install godot 4.7 or newer.
2. Clone this repo with `git clone https://github.com/Maxye4655/Checkmate---Chess-Rougelite.git`
3. Open 'Project.godot' in the editor.
3. Press the play button or **F5**

### Itch.io

You can play the full, web-ported version of the game at https://maxye4655.itch.io/checkmate-chess-rouge-like?secret=j7Q9weM5JuQXKkBqAZ9LFYKkSgE

## How to play
 
You play White against the computer. Each game is one **round** of a **run**.
 
| Outcome | What happens |
|---|---|
| **You win** | You earn coins. Choose *Keep Playing* and the opponent starts the next round with one extra **Queen** (replacing one of its pieces). |
| **You lose** | You earn coins and a 10-second countdown starts. Choose *Continue Playing* to open the **shop**, buy upgrades, then start the next round. If the timer runs out you return to the main menu. |
| **Draw (stalemate)** | You earn coins and can replay the same round. |
 
Coins come from moves played, enemy material captured, a checkmate bonus and a round bonus, plus anything your items add.
 
### Controls
 
| Input | Action |
|---|---|
| Left click | Select a piece / move to a highlighted square |
| Right click | Deselect |
| `Z` or `Backspace` | Undo your last move (limited per round) |
| `H` | Reveal the best move (needs *Oracle's Eye*) |
| `R` | Start a brand-new run (resets coins and upgrades, keeps challenge progress) |
| `Esc` | Back to the main menu (closes the Challenges screen first when it is open) |
| `F9` / `F10` | Debug: unlock everything and add $50 / reset challenge progress. Turn off with `DEBUG_KEYS := false` in `board.gd` before releasing. |
