//=============================================================================
// MonsterFightClubDriver
// A dedicated 0.125s timer actor that drives the show.
//
// Why this exists: GameInfo actors rely on their state machine Timer() to
// tick. If anything interferes with that (custom mods, state overrides),
// the show would stall. This actor ticks independently of the game's state
// machine so the fights ALWAYS run.
//
// It also force-starts the match if the stock PendingMatch state never does
// (e.g. no human players on a dedicated server).
//
// The show's TIME LIMIT is intentionally NOT handled here - it uses the
// stock RemainingTime clock (the same one every stock gametype uses), which
// the stock MatchInProgress.Timer decrements and which fires EndGame at
// zero. The HUD and scoreboard display that same stock clock, so what you
// see is exactly when the show ends.
//=============================================================================
class MonsterFightClubDriver extends Info;

var MonsterFightClubGame Game;
var int StartupClock;
var int TickAccumulator;   // 8 driver ticks = 1 show-second
var bool bForcedStart;

simulated function PostBeginPlay()
{
    Super.PostBeginPlay();
    if (Role == ROLE_Authority)
    {
        // Single-owner guard: if the game already has a primary driver,
        // this instance is a duplicate - it still helps drive the show but
        // does NOT own the clock (prevents double-counting).
        SetTimer(0.125, true);
    }
}

function Timer()
{
    if (Game == None)
    {
        Game = MonsterFightClubGame(Level.Game);
        if (Game == None)
            return;
    }

    // Camera targets update at 8 Hz so the client can track the monsters
    // smoothly between camera cuts (the client also smooths them further).
    Game.CameraTick();

    TickAccumulator++;
    if (TickAccumulator < 8)
        return;
    TickAccumulator = 0;

    // --- one show-second: force-start logic ---
    if (!bForcedStart)
    {
        if (Game.ShowHasStarted())
        {
            // the stock state machine already started the match on its own
            bForcedStart = true;
        }
        else
        {
            StartupClock++;
            if (StartupClock >= 8)
            {
                bForcedStart = true;
                log("MonsterFightClubDriver: forcing match start (startup wait elapsed)", 'MonsterFightClub');
                Game.StartMatch();
            }
        }
    }

    // --- Drive the show (once per show-second) ---
    Game.RoundTick();
}

defaultproperties
{
}
