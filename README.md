# Monster Fight Club (UT2004)

A cinematic spectator gametype for Unreal Tournament 2004 (Steam v3369). Two
random monsters fight a best-of-N duel while the audience (players + bots)
bets on the outcome. TV-style presentation: letterboxed frame, ring-side
camera rigs, fighter preview cards, bot taunts with portraits, gauntlet mode.

## Files

- `Classes/` — all UnrealScript source (14 classes)
- `MonsterFightClub.ucl` — package definition (edit `EditPackages` to build)
- `MonsterFightClub.ini` — gametype config: monster roster (218), bet
  economy, taunts, bot names, logging gates
- `UT2004MFC.ini` — server launch ini (passwords redacted — set your own)
- `RunServerMFC.bat` — dedicated-server launcher (auto-restarts on crash)
- `deploy_redirect.ps1` — compress + FTP-upload the package to the web
  redirect (needs `redirect_creds.txt`, which is git-ignored)
- `backup_mfc_ini.ps1` — safety backup of the ini before edits

## Build

```
ucc make
```

Requires the pack source folders (`MonsterFightClub\Classes`) next to
`System\`. The 64-bit preview client downloads the fresh package from the
redirect on connect.

## Server

```
RunServerMFC.bat
```

## Config highlights (`MonsterFightClub.ini`)

| Key | Meaning |
|---|---|
| `StartMoney` | starting bankroll (100) |
| `MinBet` | broke threshold (1) |
| `AudienceMin` | total audience slots (players + bots) |
| `RoundsPerMatch` | rounds per matchup |
| `TimeLimit` | show length in minutes (stock clock) |
| `bWinnerAdvances` | gauntlet mode |
| `ChampionStreakLimit` | retire the champ after N wins |
| `bSlowMoOnKill` | kill-cam slow motion (disabled: script slow-mo skews the clock) |
| `bLogDamage` / `bLogProbe` / `bLogCamera` / `bLogInput` | diagnostic logging gates |

## Commands

- `/bet <amount|all> [1|2]` — place a bet (console)
- `/reload` — fresh bankroll after going broke
- `/out` — bow out (scoreboard marks you Out)
- `E` — betting menu; `1`/`2` pick fighter, mouse wheel picks amount,
  LMB places bet + readies up
- `\` (Backslash) — toggle spectator cam / action cam (experimental)
