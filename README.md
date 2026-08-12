# Monster Fight Club (UT2004)

A cinematic UT2004 gametype: two **random monsters** fight each other in a
**best-of-3** grudge match while the audience — players **and** bots — bets on
the outcome. Everybody is locked into spectator mode and watches the show
through randomly placed TV-style cameras, complete with film grain,
letterboxing and **slow-motion kill replays**.

**The richest bankroll at the end of the show wins the game.**

---

## Install / Build

1. Drop the `MonsterFightClub` source folder next to `System\` in your
   UT2004 install (already done for the Steam install this was built for).
2. Make sure `System\UT2004.ini` has these lines in `[Engine.Engine]`:
   ```
   EditPackages=MonsterFightClub
   ServerPackages=MonsterFightClub
   ```
3. Compile from a command prompt in `System\`:
   ```
   ucc make
   ```
4. Start the gametype:
   ```
   DM-Deck17?Game=MonsterFightClubV1.MonsterFightClubGame
   ```

---

## How the show works

- **Matchups**: two random monsters from the roster (see
  `System\MonsterFightClubV1.ini`, `[MonsterFightClubV1.MonsterFightClubMonsters]`)
  are booked for a best-of-3 fight. Each matchup has a **betting window**,
  then the monsters spawn at opposite ends of the map and fight.
- **Rounds**: a round ends when a monster dies (slow motion + camera cut!)
  or when the **round time limit** expires (draw, bets refunded).
  First to 2 round wins takes the matchup; then a fresh pair is picked.
- **Bets**: everyone starts with **$100**. During the window, either use the
  **interactive betting menu** or the console:
  ```
  E (Use)         open / close the bet menu
  1 / 2           pick fighter A / B
  3 - 7           quick amount: min / $50 / $100 / $500 / ALL-IN
  8               custom amount (type digits, E to confirm)
  9               ready up (fight starts when everyone is ready!)
  LMB             PLACE BET button
  RMB             close the menu
  mouse wheel     cycle the amount

  /bet 50            -> bets $50 on the favorite
  /bet 50 1          -> bets $50 on fighter 1
  /bet 50 2          -> bets $50 on fighter 2
  ```
  Minimum bet is **$20** (configurable). Underdogs pay better odds.
- **Ready system**: the betting window ends as soon as every bettor has
  locked in with **9** (placing a bet also readies you; bots ready up after
  they bet). `BettingTime` remains as a fallback so one straggler can't
  stall the show forever.
- **Bots** bet on their own and fire off text taunts (with their portrait
  shown in chat) aimed at the monsters, at each other and at you.
- **Winner**: when the show's time limit (default **15 minutes**) expires,
  the participant with the most money wins. The scoreboard shows
  **BANKROLL** and **BETS WON** columns.

## Cinematics

- Random **camera cuts** every few seconds, orbiting the fight — and the
  camera **tracks the monsters at all times** (live positions replicated at
  4 Hz, smoothed client-side), so they stay centered even while they move.
- **Slow motion** on the killing blow, with a camera snap to the kill.
- **Film grain** and **letterbox bars** (both toggleable).
- Custom HUD: health bars for both fighters, round counter, bet status,
  bankroll, show clock, LIVE badge and SLO-MO REPLAY banner. Bot chat
  messages show the bot's **portrait** with a name plate.

## Maps

Only **DM maps** are used (`MapPrefix=DM`). By default
(`bOnly1on1Maps=True`) the gametype only accepts maps labeled `DM-1ON1*` or
maps in the curated duel list in `MapListMonsterFightClub`; any other map
gets an automatic switch to the first map in the rotation. Turn
`bOnly1on1Maps=False` to allow any DM map. The bundled test server uses
**DM-Gael** (`RunServerMFC.bat`).

## Configuration

All settings live in `System\MonsterFightClubV1.ini`:

| Setting | Default | Meaning |
|---|---|---|
| `StartMoney` | 100 | Starting bankroll |
| `MinBet` | 20 | Minimum wager |
| `RoundTimeLimit` | 60 | Seconds per round (draw if nobody dies) |
| `RoundsPerMatch` | 3 | Best-of-N per matchup |
| `BettingTime` | 10 | Betting window length (s) |
| `ResultTime` | 5 | Round result linger (s) |
| `IntermissionTime` | 7 | Gap between matchups (s) |
| `CamInterval` | 6 | Seconds between camera cuts |
| `TauntCooldown` | 12 | Seconds between bot taunts |
| `bOnly1on1Maps` | True | Restrict to 1-on-1/duel DM maps |
| `bFilmGrain` / `GrainAlpha` | True / 28 | Film grain overlay |
| `bLetterbox` | True | Letterbox bars |
| `bSlowMoOnKill` | True | Slow motion kill replays |
| `SlowMoScale` / `SlowMoDuration` | 0.3 / 1.5 | Slo-mo intensity |
| `TimeLimit` | 15 | Show length in minutes |
| `MinPlayers` | 4 | Bots fill the audience to this many |
| `MaxPlayers` | 32 | Standard 32-slot capacity kept |
| `MaxSpectators` | 32 | All humans join as spectators |

Standard URL overrides also work: `?TimeLimit=20`, `?MaxPlayers=32`,
`?MinPlayers=6`, `?RoundTimeLimit=90`, ...

## Notes

- **Everyone is a spectator** — nobody spawns a pawn. `MinPlayers` is
  filled with betting/taunting bots, so the show runs even with zero humans.
- The monster roster is editable in the ini; add monsters from other packs
  (e.g. MonsterSpawn/SMP packs) by appending
  `MonsterTable=(...)` entries with their class names.
- `killbots`/`KillBots` does not remove Monster Fight Club bots (they are
  not normal `Bot` controllers). Use `Mutate KillBots` equivalents or just
  let them be — they are the audience.
- Clients that join need the package; add it to `ServerPackages` (done
  above) and set up a redirect if you want automatic downloads.
