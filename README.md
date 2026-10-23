# VGC Multi (Lead + Back): private Showdown server

## Install
    ./setup.sh
    cd pokemon-showdown && node pokemon-showdown 8000
Open https://play.pokemonshowdown.com/~~localhost:8000 in 4 browser windows (use separate
profiles or incognito) and log in with 4 different names (no password needed).

## Start a battle
Only players 1 and 2 bring a team. Players 3 and 4 do NOT need a team: they use a copy of their ally's team.
Teams: Player 1 + Player 3 vs Player 2 + Player 4 (3 is allied with 1, 4 with 2).
1. Player 1 and Player 2 each build a team of 6 in the Teambuilder for the format
   **[Gen 9 Champions] VGC Reg M-C Multi Lead+Back**. Player 1 challenges Player 2 in that format.
2. The battle room opens with four slots. Use the invite form to add Player 3 (their ally is Player 1) and
   Player 4 (their ally is Player 2). They just click Accept; no team needed.
3. At team preview (after the optional Open Team Sheets accept from all 4), each player picks 2: lead first, then back.

## Picking rules
- Allies pick from the same 6 Pokemon, and may NOT pick the same one. If you try, the server rejects it and tells
  you who already took it.
- Each player picks 2 (lead, then back), so each team has 4 Pokemon in total.
- You are told in the battle log when your ally picks ("P1 picked Garchomp (lead), Pikachu (back)") and when they take
  a pick back with Undo. Opponents are not told.
- The Showdown client only sends a pick once you have chosen both Pokemon, so your ally sees it when you finish
  choosing, not after each individual click.
- If a timer runs out, an automatic pick skips what your ally already took.

## Shared bench (during the battle)
- You still control only your own field slot, but when you switch (by choice, or after a faint) you can bring in ANY
  benched Pokemon of your team's 4: your own back, or a Pokemon your ally picked and has not sent out.
- You cannot swap with the Pokemon your ally currently has on the field.
- A Pokemon you take from your ally becomes yours (it moves to your side, and the ally loses it). The log says
  "P1 sends out P3's Gengar!". Your ally can later take one of your benched Pokemon the same way.
- If you and your ally both try to switch in the same Pokemon in one turn, the second choice is rejected
  ("P1 is already switching in Gengar") and that player picks something else.
- If all your own Pokemon have fainted but your ally still has a benched one, you can still bring it in.
  The team loses only when all 4 Pokemon have fainted.

## Confusion friendly fire
When a confused Pokemon would hurt itself, there is a 50% chance it hits its ally instead. The damage uses the confused
Pokemon's Attack against the ally's Defense, the log says "X hurt its ally Y in its confusion!", and the confusion
still ends the same way. If the ally has fainted or there is none, it hurts itself as usual.

## Ally Switch Trade
In this format Ally Switch swaps your active Pokemon with your ally's active Pokemon, and you swap control of them:
you now give orders to their Pokemon and they give orders to yours. Moves already chosen this turn still happen. It
fails if your ally's Pokemon has fainted. The usual Ally Switch rule applies: using it again right away is less likely
to work.

## Team Healing
Revival Blessing can revive any fainted Pokemon of your team's 4, including ones your ally controls. The revived
Pokemon stays with its current owner and comes back at half HP. (Heal Bell and Aromatherapy already cure both
partners' whole sides in multi battles, including the shared bench.)

## Infatuation Friendly Fire
Each time an infatuated Pokemon would be immobilized by love (50%), there is a 50% chance it instead uses its chosen
single-target damaging move on its ally ("X is so infatuated it attacks its ally Y!"). That works out to about 25%
attack the ally, 25% immobilized, 50% move normally. Status moves and spread moves are not redirected.

## No chat ("telepathic" mode)
Chat is disabled in these battle rooms for everyone, including spectators, and private messages between the four
players of an ongoing battle are blocked. Buttons and commands still work: Open Team Sheets Accept/Reject, picking,
moves, Undo, timer and forfeit. This only covers Showdown itself; players can still talk on Discord or a call, so agree
not to. Not tested on a live server: the server check builds and the rule loads, but I could not exercise the chat block itself.

## If a rule does not seem to work (chat not locked, can't switch to ally's Pokemon)
Your server is almost certainly running old code. Check in this order:
1. Stop any old server: `pkill -f pokemon-showdown`, and close old windows running `start-online.sh`.
2. Replace `setup.sh`, `start-online.sh` and `vgc-multi.patch` with the newest copies, then run `./setup.sh`.
   It must print `OK: custom rules installed (Shared Ally Team, Shared Bench, Confusion Friendly Fire, Infatuation Friendly Fire, Ally Switch Trade, Team Healing, No Chat)`.
3. Run `./start-online.sh`. It must print `Server is up with the latest rules`.
4. Start a new battle. The battle log should show rule lines for "Shared Ally Team", "Shared Bench", "Confusion Friendly Fire", "Infatuation Friendly Fire", "Ally Switch Trade", "Team Healing" and "No Chat".
   If those lines are missing, the battle is not on the new code.

## Notes
- Open Team Sheets is opt-in: all 4 players must click Accept at team preview, and any Deny cancels it. Use
  `Force Open Team Sheets` in the format's ruleset if you want it mandatory (untested).
- The format inherits `[Gen 9 Champions] VGC 2026 Reg M-C` (legality, level 50, timer, Open Team Sheets).
- The logic is the `Shared Ally Team` rule (data/rulesets.ts) plus small changes in sim/side.ts, sim/battle.ts and
  server/chat-commands/core.ts and server/chat.ts (the No Chat rule), and the `Shared Bench` rule (sim/side.ts, sim/battle.ts, sim/pokemon.ts). An older optional `Hide Ally Bench` rule is also in the patch but not used by this format.
- Pinned to Showdown commit d601443; newer versions may need the patch adjusted.
- Tested: simulated 4-player battles (players 3/4 with no team get their ally's team, overlapping picks are rejected,
  ally pick messages and undo work, opponents see nothing; shared bench: switching to an ally's benched Pokemon,
  forced switches, a player with no own Pokemon left, and two allies claiming the same Pokemon). Also tested against a real running server with 4 connected clients: invite/accept without a team for players 3 and 4, chat and PM blocking, and switching to an ally's Pokemon. NOT tested: the browser screens (especially how the unmodified Showdown client draws a Pokemon switched in from your ally).

## Playing with friends over the internet (free tunnel from your own PC)
1. One-time: install `cloudflared` (macOS `brew install cloudflared`; Windows `winget install Cloudflare.cloudflared`;
   Linux: download from github.com/cloudflare/cloudflared/releases). No account needed for quick tunnels.
2. Run `./start-online.sh` (macOS / Linux / WSL). It starts the server, opens the tunnel and prints a link like
   `https://play.pokemonshowdown.com/~~something.trycloudflare.com`.
3. Send that link to your 3 friends. Everyone logs in with any name and builds a team in the Teambuilder.
4. Keep the window open while playing. The link changes each time you restart.

Things to know:
- Your PC must stay on and awake, and your upload speed matters a little (battles are tiny, so it is usually fine).
- Anyone who has the link can join and pick any name (no passwords). The link is random, so only share it with friends.
- Not tested: I could not run a real tunnel from my environment. I tested that the server starts with the proxy setting
  and has websockets enabled, and I read the client code to choose the link format. If the first link does not connect,
  try the `:443` variant the script also prints.
- Windows without WSL: run `node pokemon-showdown 8000` in the `pokemon-showdown` folder, and in a second window
  `cloudflared tunnel --url http://localhost:8000`. Then build the link yourself:
  `https://play.pokemonshowdown.com/~~<the-trycloudflare-host>`. You also need to set `exports.proxyip = ['127.0.0.1'];`
  in `pokemon-showdown/config/config.js`.
