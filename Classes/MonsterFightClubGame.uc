//=============================================================================
// MonsterFightClubGame
//
// Cinematic spectator gametype for UT2004: two random monsters fight each
// other in a best-of-N grudge match while the audience (players + bots)
// bets on the outcome. Everyone is locked in spectator mode and watches
// the show through randomly placed TV-style cameras, complete with film
// grain, letterboxing and slow-motion kill replays.
//
// Whoever has the most money when the show's time limit expires wins.
//=============================================================================

// The round-start bell. Imported into this package at build time - ucc make
// runs this exec before compiling, so the wav must exist when building.
#exec AUDIO IMPORT NAME="BellSound" FILE="..\MonsterFightClubV1\Sounds\bell_22050.wav"

class MonsterFightClubGame extends xDeathMatch
    config(MonsterFightClubV1);

//------------------------------------------------------------------------------
// Configurable show settings (see System\MonsterFightClubV1.ini)
//------------------------------------------------------------------------------
var() config int    StartMoney;           // starting bankroll for players and bots (default 100)
var() config int    MinBet;               // minimum bet (default 20)
var() config int    AudienceMin;          // TOTAL audience size (humans + bots).
                                           // NOTE: the stock MinPlayers is globalconfig
                                           // (reads [Engine.GameInfo] only), so it can't
                                           // be set from our ini section - this is the
                                           // real audience-size setting (default 4)
var() config int    RoundTimeLimit;       // seconds per round before a draw (default 60)
var() config int    RoundsPerMatch;       // best-of-N rounds per matchup (default 3)
var() config float  BettingTime;          // seconds the betting window stays open (default 10)
var() config float  ResultTime;           // seconds to linger on a round result (default 5)
var() config float  IntermissionTime;     // seconds between matchups (default 7)
var() config float  CamInterval;          // seconds between random camera cuts (default 6)
var() config float  TauntCooldown;        // minimum seconds between bot taunts (default 12)
var() config bool   bOnly1on1Maps;        // only allow duel-friendly DM maps (default true)
var() config bool   bFilmGrain;           // enable the animated film grain overlay
var() config int    GrainAlpha;           // film grain opacity (0-255)
var() config bool   bLetterbox;           // cinematic letterbox bars
var() config bool   bSlowMoOnKill;        // slow motion when a monster lands the killing blow
var() config float  SlowMoScale;          // time dilation while slowed (0.3 = 30% speed)
var() config float  SlowMoDuration;       // seconds of slow motion (game time)
var() config bool   bTeleportStuckFighters; // teleport monsters that refuse to fight (default true)
var() config bool   bWinnerAdvances;   // gauntlet mode: the matchup winner stays
                                       // and fights a new challenger (default false)
var() config int    ChampionStreakLimit; // gauntlet mode: the champion retires
                                       // undefeated after this many consecutive
                                       // matchup wins so the show doesn't get
                                       // boring (default 3, 0 = never retires)
var() config float  BellVolume;        // match-start bell volume (0-255, 255 = max)
var() config bool   bLogDamage;        // debug: log every damage event involving a fighter
var() config bool   bLogProbe;         // debug: log fighter health probes + spawns
var const int BetAmounts[8];           // the only allowed bet amounts ($1..$1000)
var() config array<string> SpeciesGroupBases; // class names of shared species-group
                                       // bases (e.g. Dinotopia.Dinosaur) - classes
                                       // that both extend one of these are treated
                                       // as the same species (sibling detection)
var() config string DebugStatus;          // live show state, written to the ini for admins
var() config array<string> CustomBotNames; // audience bot names - leave empty to use the
                                           // standard UT2004 roster (Brock, Malise, ...)

//------------------------------------------------------------------------------
// Phase constants
//------------------------------------------------------------------------------
const PHASE_IDLE          = 0;
const PHASE_BETTING       = 1;
const PHASE_FIGHT         = 2;
const PHASE_RESULT        = 3;
const PHASE_INTERMISSION  = 4;

//------------------------------------------------------------------------------
// A single wager placed during the betting window
//------------------------------------------------------------------------------
struct BetEntry
{
    var MonsterFightClubPRI Bettor;
    var int Amount;
    var int Fighter;        // 1 = FighterA, 2 = FighterB
};

// Cache of real spawn health per monster class, learned from real fights.
// Keyed by class name string.
struct HealthCacheEntry
{
    var string ClassName;
    var int Health;
};
var array<HealthCacheEntry> HealthCache;

var int  Phase;                     // current show phase
var int  RoundNumber;               // current round within the matchup (1-based)
var int  MatchupNumber;             // how many matchups have been booked
var int  RoundWins[2];              // wins per fighter in the current matchup
var float PhaseClock;               // seconds spent in the current phase
var float CamClock;                 // accumulator for camera cuts
var float HealthClock;              // accumulator for GRI health updates
var float StuckTime;                // how long the fighters have been separated
var float SlowMoTimeLeft;

var bool bBettingOpen;
var bool bSlowMoActive;
var bool bMapSwitchPending;
var float MapSwitchClock;
var float SavedTimeDilation;
var float LastTauntTime;
var float StatusClock;
var int SpectatorFlagClock;
var bool bDriverActive;
var bool bSpawnPendingRetry;    // fighters failed to spawn - retrying
var int SpawnRetryCount;
var bool bShowStarted;
var bool bSameSpeciesMatchup;   // both booked fighters are the same species -
                               // forces our grudge controller on both so they
                               // fight despite the stock SameSpeciesAs() refusal
var bool bShowEnded;            // the time limit fired - the show is over
var int ProbeHealthA, ProbeHealthB;  // REAL spawn health from the pack ini -
                               // published during betting (fighters aren't
                               // spawned yet, so the GRI can't read them live)
var int BotNameCycle;           // round-robin cursor into CustomBotNames (unused now, kept for config compat)

var Monster FighterA, FighterB;
var class<Monster> FighterAClass, FighterBClass;
var string FighterAName, FighterBName;
var float FighterAPower, FighterBPower;     // power ratings used for odds
var float FighterADamageScale, FighterBDamageScale;
var class<Monster> ChampionClass;   // gauntlet mode: the standing champion's class
var string ChampionName;            // gauntlet mode: the standing champion's name
var int ChampionStreak;             // gauntlet mode: consecutive matchup wins
var bool bChampionCrowned;          // this matchup already crowned/kept the champion

var array<BetEntry> Bets;
var array<PlayerStart> StartSpots;
var string FirstSupportedMap;

var MonsterFightClubGRI FCGRI;
var float CamOrbitAngle;        // persistent camera orbit angle - cuts advance it
                                  // so the camera pans around the fight instead of
                                  // jumping to random angles (less "wandering")
var float LastOrbitTime;        // last time the orbit angle was advanced (time-based)
var sound BellSound;            // bell.wav - rings for every viewer when a round starts

//==============================================================================
// Initialization
//==============================================================================

event InitGame(string Options, out string Error)
{
    local string InOpt;

    Super.InitGame(Options, Error);

    // Keep the standard 32-slot server capacity (unless explicitly overridden
    // in the map URL with ?MaxPlayers=).
    InOpt = ParseOption(Options, "MaxPlayers");
    if (InOpt == "")
        MaxPlayers = 32;
    MaxSpectators = 32;   // every human is a spectator in this show!

    // Match length (default 15 minutes, standard ?TimeLimit= override works)
    TimeLimit = Clamp(GetIntOption(Options, "TimeLimit", TimeLimit), 0, 480);
    RemainingTime = 60 * TimeLimit;
    if (GameReplicationInfo != None)
        GameReplicationInfo.TimeLimit = TimeLimit;

    // Our own URL overrides
    StartMoney      = Max(0, GetIntOption(Options, "StartMoney", default.StartMoney));
    MinBet          = Max(1, GetIntOption(Options, "MinBet", default.MinBet));
    RoundTimeLimit  = Max(10, GetIntOption(Options, "RoundTimeLimit", default.RoundTimeLimit));
    RoundsPerMatch  = Clamp(GetIntOption(Options, "RoundsPerMatch", default.RoundsPerMatch), 1, 9);

    // The show runs even with zero humans on the server
    bWaitForNetPlayers = false;
    MinNetPlayers = 0;   // PendingMatch re-enables bWaitForNetPlayers with 0 players; this lets it time out

    FCGRI = MonsterFightClubGRI(GameReplicationInfo);
    if (FCGRI != None)
        FCGRI.RoundsTotal = RoundsPerMatch;

    BuildFirstSupportedMap();
    CheckCurrentMap();

    DebugWrite("init");
}

function PostBeginPlay()
{
    Super.PostBeginPlay();
    CollectStartSpots();
    SavedTimeDilation = Level.TimeDilation;

    // The GRI actor is spawned inside Super.PostBeginPlay - grab it NOW so
    // every push/update path (betting state, camera focus, scoreboard) has
    // a valid handle. Assigning it in InitGame was too early (GRI was None).
    FCGRI = MonsterFightClubGRI(GameReplicationInfo);
    if (FCGRI != None)
        FCGRI.RoundsTotal = RoundsPerMatch;

    // Dedicated show driver: ticks independently of the game state machine
    if (Role == ROLE_Authority)
    {
        bDriverActive = (Spawn(class'MonsterFightClubDriver') != None);
        if (!bDriverActive)
            log("MonsterFightClub: could not spawn show driver - falling back to state timer", 'MonsterFightClubV1');
    }
}

function CollectStartSpots()
{
    local PlayerStart P;
    StartSpots.Length = 0;
    foreach AllActors(class'PlayerStart', P)
        StartSpots[StartSpots.Length] = P;
}

//------------------------------------------------------------------------------
// 1-on-1 map filtering
//------------------------------------------------------------------------------

function string GetCurrentMapName()
{
    local string S;
    S = string(Level);
    if (InStr(S, ".") != -1)
        S = Left(S, InStr(S, "."));
    return S;
}

function bool IsSupportedMap(string MapName)
{
    local string M;
    M = Caps(MapName);
    if (Left(M, 7) == "DM-1ON1")
        return true;
    if (!bOnly1on1Maps)
        return true;
    return IsInCuratedList(M);
}

function bool IsInCuratedList(string MapName)
{
    local class<MapList> MLClass;
    local array<string> Maps;
    local int i;

    MLClass = class<MapList>(DynamicLoadObject(MapListType, class'Class'));
    if (MLClass == None)
        return true;
    Maps = MLClass.static.StaticGetMaps();
    for (i = 0; i < Maps.Length; i++)
        if (Caps(Maps[i]) == MapName)
            return true;
    return false;
}

function BuildFirstSupportedMap()
{
    local class<MapList> MLClass;
    local array<string> Maps;

    MLClass = class<MapList>(DynamicLoadObject(MapListType, class'Class'));
    if (MLClass == None)
        return;
    Maps = MLClass.static.StaticGetMaps();
    if (Maps.Length > 0)
        FirstSupportedMap = Maps[0];
}

function CheckCurrentMap()
{
    local string Cur;
    Cur = GetCurrentMapName();
    if (!IsSupportedMap(Cur))
    {
        if (FirstSupportedMap == "")
            FirstSupportedMap = "DM-Deck17";
        log("MonsterFightClub: map '" $ Cur $ "' is not in the 1-on-1 rotation, switching to '" $ FirstSupportedMap $ "'", 'MonsterFightClubV1');
        Broadcast(Self, "THIS ARENA ISN'T IN THE 1-ON-1 ROTATION - SWITCHING SHOWS...", 'CriticalEvent');
        bMapSwitchPending = true;
        MapSwitchClock = 5.0;
    }
}

function SwitchMap()
{
    bMapSwitchPending = false;
    if (FirstSupportedMap != "")
        Level.ServerTravel(FirstSupportedMap, false);
}

//==============================================================================
// Login / spectator enforcement
//==============================================================================

event PlayerController Login(string Portal, string Options, out string Error)
{
    local PlayerController PC;
    local MonsterFightClubPRI MPRI;

    // Join as a NORMAL player, not a pure spectator. Pure spectators are
    // excluded from the map vote: xVoting rejects bOnlySpectator voters and
    // tallies against Level.Game.NumPlayers, which only counts non-
    // spectators - so a forced-SpectatorOnly audience made NumPlayers always
    // 0 and the vote could never complete (only an admin force-switch
    // worked). PostLogin locks them into the cinematic camera instead.
    PC = Super.Login(Portal, Options, Error);
    if (PC != None && PC.PlayerReplicationInfo != None)
    {
        MPRI = MonsterFightClubPRI(PC.PlayerReplicationInfo);
        if (MPRI != None)
        {
            MPRI.Money = StartMoney;
            MPRI.Score = StartMoney;
            MPRI.NetUpdateTime = Level.TimeSeconds - 1;
        }
        PC.ClientMessage("Welcome to the Monster Fight Club! Bet with /bet <amount> [1|2].");
        SetSpectatorCamera(PC, GetFightFocus(), true, true);
    }
    return PC;
}

event PostLogin(PlayerController NewPlayer)
{
    local MonsterFightClubPRI MPRI;

    Super.PostLogin(NewPlayer);
    if (NewPlayer == None)
        return;

    // MinPlayers means TOTAL players (humans + bots). On a dedicated
    // server bots fill the audience to MinPlayers before anyone joins, so
    // when a human arrives the room would be MinPlayers+1. Trim the excess
    // bots so the audience stays at MinPlayers total.
    TrimAudienceBots();

    // Force the cinematic spectator state on the client so the menu keys
    // and camera tracking are active right after joining.
    NewPlayer.GotoState('Spectating');

    MPRI = MonsterFightClubPRI(NewPlayer.PlayerReplicationInfo);
    if (MPRI != None)
    {
        // Show the bettor on the scoreboard like any other player
        MPRI.bIsSpectator = false;
        MPRI.bOnlySpectator = false;
        MPRI.bOutOfLives = false;
        MPRI.NetUpdateTime = Level.TimeSeconds - 1;
    }

    // Send the current show state to the new viewer immediately.
    PushBettingState();

    if (NewPlayer.PlayerReplicationInfo != None)
        log("MonsterFightClub: " $ NewPlayer.PlayerReplicationInfo.PlayerName $ " is spectating", 'MonsterFightClubV1');
}

// Stock spectator code keeps re-flagging the audience as spectators, which
// makes the scoreboard show "OUT". Keep them listed as real players.
function EnforceScoreboardFlags()
{
    local Controller C;
    local MonsterFightClubPlayerController MPC;
    local MonsterFightClubPRI MPRI;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        MPC = MonsterFightClubPlayerController(C);
        if (MPC == None)
            continue;
        MPRI = MonsterFightClubPRI(MPC.PlayerReplicationInfo);
        if (MPRI != None && (MPRI.bIsSpectator || MPRI.bOnlySpectator || MPRI.bOutOfLives))
        {
            // Players who chose /out keep their Out status on the scoreboard.
            if (MPC.bVoluntaryOut)
            {
                MPRI.bIsSpectator = false;
                MPRI.bOnlySpectator = false;
                MPRI.bOutOfLives = true;
            }
            else
            {
                MPRI.bIsSpectator = false;
                MPRI.bOnlySpectator = false;
                MPRI.bOutOfLives = false;
            }
            MPRI.NetUpdateTime = Level.TimeSeconds - 1;
        }
    }
}

function bool AllowBecomeActivePlayer(PlayerController P)
{
    return false;   // the audience never leaves the stands
}

function bool BecomeSpectator(PlayerController P)
{
    return true;
}

// The stock spectator camera cycles view targets through this. Allow the
// fighters (monsters) to be viewed - they're the show - plus other real
// players. Pawn-less controllers (the audience bots) are skipped.
function bool CanSpectate(PlayerController Viewer, bool bOnlySpectator, actor ViewTarget)
{
    local Controller C;

    if (ViewTarget == None)
        return false;
    C = Controller(ViewTarget);
    if (C != None)
    {
        if (C.Pawn != None && Monster(C.Pawn) != None)
            return true;   // the fighters are always viewable
        // Only non-monster targets WITH a pawn are viewable (real human
        // players in the audience). Pawn-less controllers - the audience
        // bots - are skipped so LMB never cycles through them.
        if (C.Pawn != None && C.PlayerReplicationInfo != None && !C.PlayerReplicationInfo.bOnlySpectator)
            return true;
        return false;
    }
    return true;   // non-controller targets (self, free cam, ...)
}

// Lock every viewer onto a fighter with the stock chase camera - called
// when fresh fighters spawn so the camera lands on the action.
function LockViewersOntoFight()
{
    local Controller C;
    local MonsterFightClubPlayerController MPC;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        MPC = MonsterFightClubPlayerController(C);
        if (MPC == None || MPC.PlayerReplicationInfo == None)
            continue;
        if (MPC.bActionCam)
            continue;   // the action cam owns this viewer's view
        MPC.ServerViewNextPlayer();
    }
}

//==============================================================================
// Bots
//==============================================================================

function bool NeedPlayers()
{
    // AudienceMin = TOTAL audience (humans + bots). Humans are all
    // PlayerControllers (this show's audience are "spectators" in the
    // engine's eyes, so stock NumPlayers is always 0 - count them
    // ourselves, including bOnlySpectator).
    return (NumBots + CountHumans() < AudienceMin && NumBots + CountHumans() < MaxPlayers);
}

// Every real human in the room (PlayerControllers, including pure
// spectators - in this show the whole audience is spectators).
// Every REAL human in the room. Only controllers with an actual connected
// Player count - the dedicated server's URL player (ucc server
// ?Name=VMWheel58?SpectatorOnly=1) creates a phantom PlayerController with
// Player == None that must NOT be counted, or bots would always fill one
// short (AudienceMin 10 -> 9 bots, 5 -> 4 bots).
function int CountHumans()
{
    local int N;
    local Controller C;
    local PlayerController PC;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        PC = PlayerController(C);
        if (PC != None && PC.PlayerReplicationInfo != None && PC.Player != None)
            N++;
    }
    return N;
}

// MinPlayers = TOTAL audience (humans + bots). Bots fill the room to
// MinPlayers before any human joins; when a human arrives, remove the
// excess bots so the total stays at MinPlayers (never MinPlayers+1).
function TrimAudienceBots()
{
    local array<MonsterFightClubBot> Remove;
    local Controller C;
    local MonsterFightClubBot B;
    local int i, Excess;

    // Count ALL humans - the joining player is a pure spectator
    // (?SpectatorOnly=1) so they'd be invisible to a bOnlySpectator check.
    Excess = NumBots + CountHumans() - AudienceMin;
    if (Excess <= 0)
        return;

    // Collect bots to remove.
    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        B = MonsterFightClubBot(C);
        if (B == None || B.PlayerReplicationInfo == None)
            continue;
        if (Remove.Length < Excess)
            Remove[Remove.Length] = B;
    }

    for (i = 0; i < Remove.Length; i++)
    {
        B = Remove[i];
        if (B == None)
            continue;
        log("MonsterFightClub: " $ B.PlayerReplicationInfo.PlayerName $ " removed (audience full)", 'MonsterFightClubV1');
        if (B.PlayerReplicationInfo != None)
            B.PlayerReplicationInfo.Destroy();
        B.Destroy();
        NumBots--;
    }
}

function bool AddBot(optional string botName)
{
    local MonsterFightClubBot B;
    local MonsterFightClubPRI MPRI;

    if (NumBots + NumPlayers >= MaxPlayers)
        return false;

    B = Spawn(class'MonsterFightClubBot');
    if (B == None)
    {
        warn("Failed to spawn MonsterFightClubBot.");
        return false;
    }

    if (botName == "")
        botName = GetNextBotName();

    ChangeName(B, botName, false);
    B.PlayerReplicationInfo.PlayerID = CurrentID++;

    MPRI = MonsterFightClubPRI(B.PlayerReplicationInfo);
    if (MPRI != None)
    {
        // Mark the audience bots as bots. Without this, every system that
        // reads the PRI (xVoting's player counts, HasHumanPlayers, the
        // ready stats, ...) mistakes them for human players.
        MPRI.bBot = true;
        MPRI.Money = StartMoney;
        MPRI.Score = StartMoney;
        MPRI.Portrait = GetPortraitFor(botName);
        MPRI.NetUpdateTime = Level.TimeSeconds - 1;
    }

    NumBots++;
    log("MonsterFightClub: " $ botName $ " joined the audience (" $ NumBots $ " bots)", 'MonsterFightClubV1');
    return true;
}

function Material GetPortraitFor(string BotName)
{
    local array<xUtil.PlayerRecord> Recs;
    local int i;

    if (BotName == "")
        return GetRandomPortrait();

    // Case-insensitive match against the full roster - FindPlayerRecord is
    // exact-match and fails on names whose stored DefaultName differs in
    // case/format (the source of the question-mark portraits). Skip records
    // with no portrait so we never hand back None (which the client then
    // turns into the generic question mark).
    class'xUtil'.static.GetPlayerList(Recs);
    for (i = 0; i < Recs.Length; i++)
        if (Recs[i].DefaultName ~= BotName && Recs[i].Portrait != None)
            return Recs[i].Portrait;

    return GetRandomPortrait();
}

// A random portrait from the standard roster - used when a custom bot name
// has no matching character record. Uses Material (not Texture) so shader/
// combiner portraits are accepted, which kills the question-mark fallback.
function Material GetRandomPortrait()
{
    local array<xUtil.PlayerRecord> Recs;
    local int i, Tries;

    class'xUtil'.static.GetPlayerList(Recs);
    if (Recs.Length == 0)
        return Material(DynamicLoadObject("PlayerPictures.cDefault", class'Texture'));

    for (Tries = 0; Tries < 15; Tries++)
    {
        i = Rand(Recs.Length);
        if (Recs[i].Portrait != None)
            return Recs[i].Portrait;
    }
    return Material(DynamicLoadObject("PlayerPictures.cDefault", class'Texture'));
}

// Audience bot name selection: if the admin configured CustomBotNames in
// MonsterFightClubV1.ini, pick a RANDOM unused name from the list (so the
// same four bots don't always get the same four names in the same order);
// otherwise fall back to the standard UT2004 bot roster.
function string GetNextBotName()
{
    local int i, N, StartIdx;

    if (CustomBotNames.Length > 0)
    {
        N = CustomBotNames.Length;
        StartIdx = Rand(N);
        for (i = 0; i < N; i++)
        {
            if (!BotNameInUse(CustomBotNames[(StartIdx + i) % N]))
                return CustomBotNames[(StartIdx + i) % N];
        }
        // everything taken - return a random one anyway
        return CustomBotNames[Rand(N)];
    }
    return GetRandomBotName();
}

function bool BotNameInUse(string Name)
{
    local Controller C;

    for (C = Level.ControllerList; C != None; C = C.NextController)
        if (C.PlayerReplicationInfo != None
            && C.PlayerReplicationInfo.PlayerName ~= Name)
            return true;
    return false;
}

// Pick a name from the standard UT2004 bot roster (Brock, Malise, Kragen,
// ...) - the same xUtil.PlayerRecord list the stock xDMRoster uses. Names
// are weighted by BotUse exactly like the stock roster, and duplicate
// names already on the server are avoided.
function string GetRandomBotName()
{
    local array<xUtil.PlayerRecord> Recs;
    local int i, RND, Total, Pick, Tries;
    local Controller C;
    local bool bTaken;

    class'xUtil'.static.GetPlayerList(Recs);
    if (Recs.Length == 0)
        return "Bot";

    for (i = 0; i < Recs.Length; i++)
        Total += Recs[i].BotUse;
    if (Total <= 0)
        Total = Recs.Length;

    for (Tries = 0; Tries < 10; Tries++)
    {
        RND = Rand(Total);
        Pick = 0;
        for (i = 0; i < Recs.Length; i++)
        {
            Pick += Max(1, Recs[i].BotUse);
            if (Pick > RND)
                break;
        }
        if (i >= Recs.Length)
            i = Recs.Length - 1;

        // avoid duplicate names on the server
        bTaken = false;
        for (C = Level.ControllerList; C != None; C = C.NextController)
            if (C.PlayerReplicationInfo != None
                && C.PlayerReplicationInfo.PlayerName ~= Recs[i].DefaultName)
            {
                bTaken = true;
                break;
            }
        if (!bTaken)
            return Recs[i].DefaultName;
    }

    // everything taken - just return the last pick anyway
    return Recs[i].DefaultName;
}

function bool TooManyBots(Controller botToRemove)
{
    return false;   // the panel never gets fired
}

function int GetNumPlayers()
{
    return NumPlayers + NumBots;
}

function RestartPlayer(Controller aPlayer)
{
    if (aPlayer == None)
        return;
    if (PlayerController(aPlayer) != None)
        return;   // locked spectators — the audience never gets a pawn
    if (MonsterFightClubBot(aPlayer) != None)
        return;   // pawn-less bettors
    Super.RestartPlayer(aPlayer);
}

function ResetBotBets()
{
    local Controller C;
    local MonsterFightClubBot B;
    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        B = MonsterFightClubBot(C);
        if (B != None)
            B.bHasBetThisRound = false;
    }
}

//==============================================================================
// Show flow
//==============================================================================

function StartMatch()
{
    Super.StartMatch();
    StartShow();
}

function StartShow()
{
    if (bShowStarted)
        return;
    bShowStarted = true;
    Phase = PHASE_IDLE;

    // The show clock starts NOW - RemainingTime used to count from server
    // boot, which ended the show a couple of minutes early (map load +
    // startup wait).
    RemainingTime = 60 * TimeLimit;
    if (GameReplicationInfo != None)
        GameReplicationInfo.RemainingTime = RemainingTime;

    DebugWrite("startshow");
    StartNewMatchup();
}

function StartNewMatchup()
{
    MatchupNumber++;
    RoundNumber = 1;
    RoundWins[0] = 0;
    RoundWins[1] = 0;
    bChampionCrowned = false;
    PickTwoFighters();
    // Read the REAL spawn health right after booking, while the level is
    // fresh (previous round's fighters already destroyed). The probe spawn
    // FAILED when called from BeginBettingPhase (the spawn context is
    // wrong there), so it runs here instead.
    ProbeFighterHealths();
    BeginBettingPhase();
}
function PickTwoFighters()
{
    local array<int> Idx;
    local int a, b, tries, i;
    local string AClass, AName, BClass, BName;
    local class<Monster> ALoaded, BLoaded;

    BuildMonsterIndex(Idx);
    if (Idx.Length == 0)
    {
        // Absolute fallback: the vanilla roster
        FighterAClass = class'SkaarjPack.Skaarj';
        FighterBClass = class'SkaarjPack.Gasbag';
        FighterAName = "Skaarj";
        FighterBName = "Gasbag";
        FighterAPower = 1.5;
        FighterBPower = 1.2;
        FighterADamageScale = 1.0;
        FighterBDamageScale = 1.0;
        PublishFighterClasses();
        return;
    }

    // Gauntlet mode (bWinnerAdvances): the standing champion (from the
    // previous matchup's winner) is locked in as FighterA and gets a NEW
    // challenger. The first matchup has no champion, so it books two
    // fighters normally and the winner becomes the champion.
    if (bWinnerAdvances && ChampionClass != None)
    {
        if (ChampionStreakLimit > 0 && ChampionStreak >= ChampionStreakLimit)
        {
            // The champ has cleaned house long enough - retire them
            // undefeated and book two fresh contenders to keep the show
            // from getting boring.
            Broadcast(Self, Caps(ChampionName) $ " RETIRES UNDEFEATED - " $ ChampionStreak $ " WINS IN A ROW! NEW CONTENDERS WILL BE CHOSEN.", 'CriticalEvent');
            ChampionClass = None;
            ChampionName = "";
            ChampionStreak = 0;
            if (FCGRI != None)
            {
                FCGRI.ChampionName = "";
                FCGRI.ChampionStreak = 0;
                FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
            }
        }
        else
        {
            ALoaded = ChampionClass;
            AName = ChampionName;
        }
    }
    if (ALoaded == None)
    {
        // Pick fighter A.
        a = Idx[Rand(Idx.Length)];
        AClass = class'MonsterFightClubMonsters'.default.MonsterTable[a].MonsterClassName;
        AName = class'MonsterFightClubMonsters'.default.MonsterTable[a].MonsterName;
        ALoaded = class<Monster>(DynamicLoadObject(AClass, class'Class'));
        if (ALoaded == None)
            ALoaded = class'SkaarjPack.Skaarj';
    }

    // Pick fighter B from ANY species - same-species matchups (dino vs
    // dino, skaarj vs skaarj) are allowed again. The bSameSpeciesMatchup
    // flag makes SetupFighterController force our grudge controller onto
    // both fighters, which bypasses the stock SameSpeciesAs() refusal
    // entirely (direct Enemy/Target assignment, no species gates).
    b = -1;
    for (tries = 0; tries < 40 && b == -1; tries++)
    {
        i = Idx[Rand(Idx.Length)];
        BClass = class'MonsterFightClubMonsters'.default.MonsterTable[i].MonsterClassName;
        BLoaded = class<Monster>(DynamicLoadObject(BClass, class'Class'));
        if (BLoaded == None)
            continue;
        if (i == a && Idx.Length > 1)
            continue;   // avoid booking the exact same table entry twice
        b = i;
    }

    // Fallback: the whole table is broken - take the next index anyway so
    // the show still runs.
    if (b == -1)
    {
        b = a;
        BClass = class'MonsterFightClubMonsters'.default.MonsterTable[b].MonsterClassName;
        BName = class'MonsterFightClubMonsters'.default.MonsterTable[b].MonsterName;
    }
    else
        BName = class'MonsterFightClubMonsters'.default.MonsterTable[b].MonsterName;

    FighterAClass = ALoaded;
    FighterAName = AName;
    // Odds are even (1.0) for every matchup; damage scales are computed at
    // spawn time from the fighters' real health pools (see SpawnFighters).
    FighterAPower = 1.0;

    FighterBClass = class<Monster>(DynamicLoadObject(BClass, class'Class'));
    if (FighterBClass == None)
        FighterBClass = class'SkaarjPack.Gasbag';
    FighterBName = BName;
    FighterBPower = 1.0;

    // Same species (including siblings under a shared base like
    // Dinotopia.Dinosaur) -> both fighters get our grudge controller.
    bSameSpeciesMatchup = IsSameSpecies(FighterAClass, FighterBClass);

    PublishFighterClasses();

    if (bWinnerAdvances && ChampionClass != None)
        log("MonsterFightClub: gauntlet - champion " $ FighterAName $ " defends vs " $ FighterBName, 'MonsterFightClubV1');
    else
        log("MonsterFightClub: matchup " $ MatchupNumber $ " - " $ FighterAName $ " vs " $ FighterBName, 'MonsterFightClubV1');
}

// Send the fighter class paths to every client so the HUD can load the
// monster's stats + skin for the pre-fight preview panel.
function PublishFighterClasses()
{
    if (FCGRI != None)
    {
        FCGRI.FighterAClassName = string(FighterAClass);
        FCGRI.FighterBClassName = string(FighterBClass);
        FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
    }
}

// Same check the stock Monster.SameSpeciesAs() uses - plus SIBLING
// detection via known species-group base classes (loaded dynamically so we
// don't need the pack compiled in). Dinos all extend Dinotopia.Dinosaur,
// so Acro vs Trex are siblings under it and would refuse to fight.
//
// ALSO: if both classes live in the SAME PACKAGE (e.g. all AlienMonsterPack
// aliens), they're treated as the same species. This catches packs whose
// monsters share a native base we can't see (compiled-only packages like
// AlienMonsterPack) - their own controllers refuse same-species targets,
// so we force our grudge controller + damage bypass for those matchups.
static function bool IsSameSpecies(class<Monster> A, class<Monster> B)
{
    local class<Monster> Base;
    local string APackage, BPackage;
    local int i;

    if (A == None || B == None)
        return false;
    if (A == B)
        return true;
    if (ClassIsChildOf(A, B) || ClassIsChildOf(B, A))
        return true;

    // Same package = same species family (AlienMonsterPack, MarioMonstersv1,
    // KFChar, ...). Strip the ".Class" suffix from the class string.
    APackage = Left(string(A), InStr(string(A), "."));
    BPackage = Left(string(B), InStr(string(B), "."));
    if (APackage != "" && APackage == BPackage)
        return true;

    // Sibling check: if both classes are children of the same known
    // species-group base (e.g. Dinotopia.Dinosaur), they're the same
    // family even though neither is an ancestor of the other.
    for (i = 0; i < default.SpeciesGroupBases.Length; i++)
    {
        Base = class<Monster>(DynamicLoadObject(default.SpeciesGroupBases[i], class'Class'));
        if (Base != None && ClassIsChildOf(A, Base) && ClassIsChildOf(B, Base))
            return true;
    }
    return false;
}

function BuildMonsterIndex(out array<int> Idx)
{
    local int i;
    local class<Monster> M;
    for (i = 0; i < class'MonsterFightClubMonsters'.default.MonsterTable.Length; i++)
    {
        if (class'MonsterFightClubMonsters'.default.MonsterTable[i].MonsterClassName == "")
            continue;
        M = class<Monster>(DynamicLoadObject(class'MonsterFightClubMonsters'.default.MonsterTable[i].MonsterClassName, class'Class'));
        if (M != None)
            Idx[Idx.Length] = i;
    }
}

function BeginBettingPhase()
{
    local int Target;

    // Best-of-N: the moment a fighter has clinched the series (e.g. 2-0 in
    // a best-of-3), there IS no next round - skip straight to the
    // intermission so "ROUND 3 OF 3" is never announced or bet on.
    Target = (RoundsPerMatch + 1) / 2;
    if (RoundWins[0] >= Target || RoundWins[1] >= Target || RoundNumber > RoundsPerMatch)
    {
        BeginIntermission();
        return;
    }

    Phase = PHASE_BETTING;
    PhaseClock = 0;
    bBettingOpen = true;
    Bets.Length = 0;
    ResetBotBets();
    ResetReady();

    // Bots that went broke are replaced with fresh ones; broke humans are
    // automatically given a fresh bankroll - no commands needed.
    ReplaceBrokeBots();
    AutoReloadBrokeHumans();

    // Clear the previous round's winner so it isn't wandering around the
    // arena during the betting window.
    DestroyFighters();

    DebugWrite("betting phase=" $ Phase $ " fa=" $ FighterAName $ " fb=" $ FighterBName);

    if (FCGRI != None)
    {
        FCGRI.FighterAName = FighterAName;
        FCGRI.FighterBName = FighterBName;
        FCGRI.Phase = Phase;
        FCGRI.RoundNumber = RoundNumber;
        FCGRI.bBettingOpen = true;
        FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
    }
    PushBettingState();

    if (RoundNumber == 1)
        Broadcast(Self, "NEXT FIGHT: " $ Caps(FighterAName) $ " VS " $ Caps(FighterBName), 'CriticalEvent');
    else
        Broadcast(Self, "ROUND " $ RoundNumber $ " OF " $ RoundsPerMatch $ ": " $ Caps(FighterAName) $ " VS " $ Caps(FighterBName), 'CriticalEvent');
    Broadcast(Self, "BETTING OPEN - /bet <amount> [1|2]", 'CriticalEvent');

    // open with a wide establishing shot
    CamClock = 0;
    UpdateCameras(true);
}

// Spawn a throwaway copy of each booked fighter at the REAL duel starts to
// read its REAL spawn health - packs like Dinotopia override health from
// their own config (DinoFactFile.ini), so the class defaults on the card
// were wrong. The high-altitude probe FAILED to spawn these packs (their
// spawn checks reject it), so the probe now uses the same PlayerStarts the
// real fighters will use.
// The card health comes from the REAL spawn whenever we've seen this
// class fight before: SpawnFighters measures each fighter's actual spawn
// health (same spawn path, same mutators active) and remembers it. A
// fresh probe can disagree with the real fighter when a pack randomizes
// its health or initializes it from fight context, so the cache takes
// priority and the probe only fills in for classes never fought this
// server session.
function ProbeFighterHealths()
{
    local int i, iA, iB;
    local int Health;

    if (FCGRI == None)
        return;

    // Cache-first: the last REAL fighter of this class is the closest
    // measurement to what the next one will spawn with.
    ProbeHealthA = GetCachedHealth(FighterAClass);
    ProbeHealthB = GetCachedHealth(FighterBClass);

    // No learned value yet - probe a spawned copy at the same duel starts
    // the real fighters will use (retry across all spots; the probe spawn
    // is flaky for some packs). Probe results are remembered too, so a
    // repeat booking skips the probe entirely.
    if (GetDuelStarts(iA, iB))
    {
        if (FighterAClass != None && ProbeHealthA <= 0)
        {
            Health = ProbeWithRetry(FighterAClass, iA);
            if (Health > 0)
            {
                ProbeHealthA = Health;
                RememberHealth(FighterAClass, Health);
                if (default.bLogProbe)
                    log("MFC-PROBE: " $ FighterAClass $ " defaultHealth=" $ FighterAClass.default.Health
                        $ " probeHealth=" $ Health, 'MonsterFightClubV1');
            }
        }
        if (FighterBClass != None && ProbeHealthB <= 0)
        {
            Health = ProbeWithRetry(FighterBClass, iB);
            if (Health > 0)
            {
                ProbeHealthB = Health;
                RememberHealth(FighterBClass, Health);
                if (default.bLogProbe)
                    log("MFC-PROBE: " $ FighterBClass $ " defaultHealth=" $ FighterBClass.default.Health
                        $ " probeHealth=" $ Health, 'MonsterFightClubV1');
            }
        }
    }

    // Last resort: the class default (most packs override this in their
    // own config ini, so this is the least reliable source).
    if (FighterAClass != None && ProbeHealthA <= 0)
        ProbeHealthA = FighterAClass.default.Health;
    if (FighterBClass != None && ProbeHealthB <= 0)
        ProbeHealthB = FighterBClass.default.Health;

    // ALWAYS publish the resolved values - the GRI can otherwise hold a
    // stale max-health from the previous matchup's class, which is what
    // made the card show the wrong number "sometimes".
    FCGRI.FighterAMaxHealth = ProbeHealthA;
    FCGRI.FighterAHealth = ProbeHealthA;
    FCGRI.FighterBMaxHealth = ProbeHealthB;
    FCGRI.FighterBHealth = ProbeHealthB;
    FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
}

// Try to spawn the probe at the given spot, falling back to every other
// spot. Returns the spawn health, or 0 if it couldn't spawn anywhere.
function int ProbeWithRetry(class<Monster> MClass, int PreferSpot)
{
    local Monster P;
    local int i, Spot, Health;

    for (i = 0; i < StartSpots.Length; i++)
    {
        if (i == 0)
            Spot = PreferSpot;
        else
            Spot = i - 1;
        if (Spot < 0 || Spot >= StartSpots.Length)
            continue;
        P = Spawn(MClass,,, StartSpots[Spot].Location, StartSpots[Spot].Rotation);
        if (P != None)
        {
            Health = P.Health;   // read BEFORE destroying!
            if (P.Controller != None)
                P.Controller.Destroy();
            P.Destroy();
            return Health;
        }
    }
    if (default.bLogProbe)
        log("MFC-PROBE: " $ MClass $ " could not spawn probe at any spot!", 'MonsterFightClubV1');
    return 0;
}

function int GetCachedHealth(class<Monster> MClass){
    local int i;
    local string CName;

    if (MClass == None)
        return 0;
    CName = string(MClass);
    for (i = 0; i < HealthCache.Length; i++)
        if (HealthCache[i].ClassName == CName)
            return HealthCache[i].Health;
    return 0;
}

function RememberHealth(class<Monster> MClass, int Health)
{
    local int i;
    local HealthCacheEntry E;
    local string CName;

    if (MClass == None || Health <= 0)
        return;
    CName = string(MClass);
    for (i = 0; i < HealthCache.Length; i++)
        if (HealthCache[i].ClassName == CName)
        {
            HealthCache[i].Health = Health;
            return;
        }
    E.ClassName = CName;
    E.Health = Health;
    HealthCache[HealthCache.Length] = E;
}

// A bot that can't afford the minimum bet is replaced by a brand-new bot
// with a fresh bankroll (they keep the show lively instead of standing
// around broke).
function ReplaceBrokeBots()
{
    local array<MonsterFightClubBot> Broke;
    local MonsterFightClubBot B;
    local MonsterFightClubPRI MPRI;
    local Controller C;
    local int i;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        B = MonsterFightClubBot(C);
        if (B == None || B.PlayerReplicationInfo == None)
            continue;
        MPRI = MonsterFightClubPRI(B.PlayerReplicationInfo);
        if (MPRI != None && MPRI.Money < MinBet)
            Broke[Broke.Length] = B;
    }

    for (i = 0; i < Broke.Length; i++)
    {
        B = Broke[i];
        if (B == None)
            continue;
        log("MonsterFightClub: " $ B.PlayerReplicationInfo.PlayerName $ " went broke - replaced", 'MonsterFightClubV1');
        if (B.PlayerReplicationInfo != None)
            B.PlayerReplicationInfo.Destroy();
        B.Destroy();
        NumBots--;
        AddBot();   // fresh bot, fresh $100
    }
}

// Broke humans get a fresh bankroll automatically every betting phase - no
// commands to type. Players who chose /out stay out until they /reload or
// reconnect.
function AutoReloadBrokeHumans()
{
    local Controller C;
    local MonsterFightClubPlayerController MPC;
    local MonsterFightClubPRI MPRI;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        MPC = MonsterFightClubPlayerController(C);
        if (MPC == None || MPC.PlayerReplicationInfo == None)
            continue;
        if (MPC.bVoluntaryOut)
            continue;   // chose /out - not automatically revived
        MPRI = MonsterFightClubPRI(MPC.PlayerReplicationInfo);
        if (MPRI != None && MPRI.Money < MinBet)
        {
            MPRI.Money = StartMoney;
            MPRI.Score = StartMoney;
            // Fresh bankroll, clean slate: bets-won (mirrored into Deaths
            // for the scoreboard) resets with the money.
            MPRI.BetWins = 0;
            MPRI.Deaths = 0;
            MPRI.bOutOfLives = false;
            MPRI.NetUpdateTime = Level.TimeSeconds - 1;
            MPC.ClientMessage("Fresh $" $ StartMoney $ " - you're back in! Betting is open.");
            log("MonsterFightClub: " $ MPRI.PlayerName $ " went broke - auto-reloaded $" $ StartMoney, 'MonsterFightClubV1');
        }
    }
}

function StartFight()
{
    Phase = PHASE_FIGHT;
    PhaseClock = 0;
    bBettingOpen = false;
    StuckTime = 0;
    bSpawnPendingRetry = false;
    SpawnRetryCount = 0;

    if (FCGRI != None)
    {
        FCGRI.Phase = Phase;
        FCGRI.bBettingOpen = false;
    }
    PushBettingState();

    SpawnFighters();

    // Lock every viewer onto the fresh fighters with the stock chase
    // camera (the standard spectator experience - no custom camera code).
    LockViewersOntoFight();

    Broadcast(Self, "FIGHT!", 'CriticalEvent');
    PlayBellSound();
    CamClock = 0;
    UpdateCameras(true);
}

// Rings the bell for every connected viewer when the round starts.
function PlayBellSound()
{
    local Controller C;
    local PlayerController PC;

    if (BellSound == None)
        return;
    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        PC = PlayerController(C);
        if (PC != None)
            PC.ClientPlaySound(BellSound, false, BellVolume);
    }
}

//==============================================================================
// Fighters
//==============================================================================

function SpawnFighters()
{
    local Controller CA, CB;
    local int i, iA, iB;
    local vector Center;

    DestroyFighters();

    if (GetDuelStarts(iA, iB))
    {
        FighterA = TrySpawnFighter(FighterAClass, iA);
        if (FighterA == None)
            for (i = 0; i < StartSpots.Length; i++)
            {
                FighterA = TrySpawnFighter(FighterAClass, i);
                if (FighterA != None)
                    break;
            }

        FighterB = TrySpawnFighter(FighterBClass, iB);
        if (FighterB == None)
            for (i = 0; i < StartSpots.Length; i++)
            {
                if (i == iA)
                    continue;
                FighterB = TrySpawnFighter(FighterBClass, i);
                if (FighterB != None)
                    break;
            }
    }

    Center = GetLevelCenter();
    if (FighterA == None)
        FighterA = Spawn(FighterAClass,,, Center + vect(0, -300, 80));
    if (FighterB == None)
        FighterB = Spawn(FighterBClass,,, Center + vect(0, 300, 80));

    if (FighterA == None || FighterB == None)
    {
        if (!bSpawnPendingRetry)
            Broadcast(Self, "THE ARENA IS BEING PREPARED - PLEASE STAND BY...", 'CriticalEvent');
        log("MonsterFightClub: could not spawn fighters - will retry", 'MonsterFightClubV1');
        bSpawnPendingRetry = true;
        SpawnRetryCount = 0;
        return;
    }

    FighterA.DeactivateSpawnProtection();
    FighterB.DeactivateSpawnProtection();

    // DIAGNOSTIC: compare the probe health (betting-card value) against the
    // REAL spawned fighter's health (bLogProbe in the ini).
    if (default.bLogProbe)
    {
        log("MFC-SPAWN: " $ FighterAClass $ " probe=" $ ProbeHealthA $ " real=" $ FighterA.Health
            $ " classDefault=" $ FighterAClass.default.Health, 'MonsterFightClubV1');
        log("MFC-SPAWN: " $ FighterBClass $ " probe=" $ ProbeHealthB $ " real=" $ FighterB.Health
            $ " classDefault=" $ FighterBClass.default.Health, 'MonsterFightClubV1');
    }

    // LEARN the real spawn health so the next booking of this class shows
    // the correct card value even if the probe fails.
    RememberHealth(FighterAClass, FighterA.Health);
    RememberHealth(FighterBClass, FighterB.Health);
    if (ProbeHealthA != FighterA.Health || ProbeHealthB != FighterB.Health)
    {
        ProbeHealthA = FighterA.Health;
        ProbeHealthB = FighterB.Health;
        FCGRI.FighterAMaxHealth = FighterA.Health;
        FCGRI.FighterAHealth = FighterA.Health;
        FCGRI.FighterBMaxHealth = FighterB.Health;
        FCGRI.FighterBHealth = FighterB.Health;
        FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
    }

    // Fair-fight damage scaling: each fighter's damage is scaled by the
    // real health ratio (sqrt, clamped) so a 2000 HP tank doesn't turn the
    // fight into an hour-long slog. Health pools stay NATURAL - every
    // monster keeps its own stats (a brachiosaurus is tanky, a headcrab
    // is squishy).
    FighterADamageScale = FClamp(Sqrt(FighterB.Health / Max(1.0, float(FighterA.Health))), 0.25, 4.0);
    FighterBDamageScale = FClamp(Sqrt(FighterA.Health / Max(1.0, float(FighterB.Health))), 0.25, 4.0);

    // Record the real max health for the HUD bars (stock Monster.HealthMax
    // defaults to 100 for every monster).
    FighterA.HealthMax = FighterA.Health;
    FighterB.HealthMax = FighterB.Health;

    FighterA.SetRotation(rotator(FighterB.Location - FighterA.Location));
    FighterB.SetRotation(rotator(FighterA.Location - FighterB.Location));

    // Never start a duel farther apart than 1024 units - big maps would
    // otherwise need teleports to bring the fighters together. If the
    // chosen starts are still too far (or the fallback center spawn was
    // used), pull FighterB in close.
    ClampFightDistance();

    FighterA.SetRotation(rotator(FighterB.Location - FighterA.Location));
    FighterB.SetRotation(rotator(FighterA.Location - FighterB.Location));

    // Controller selection: custom packs (DoomPawns2k4, HL2Monsters,
    // KFChar, ...) override ControllerClass with their own AI that holds
    // the pack's attack/firing logic (e.g. DoomController's AttackEnemy
    // states). Detect that and KEEP the monster's own controller - just
    // point it at the rival. Only stock monsters (ControllerClass is the
    // plain MonsterController) get our grudge controller.
    CA = SetupFighterController(FighterA, FighterB);
    CB = SetupFighterController(FighterB, FighterA);

    // Clear out any minions/strays before the bell rings.
    DestroyStrayMonsters();
}

// Pick and prepare the controller for one fighter:
//  - custom pack controllers (anything other than the stock
//    MonsterController) are kept - they know how to fire the pack's
//    weapons - and are pointed at the rival.
//  - stock monsters get our grudge controller so they never camp.
function Controller SetupFighterController(Monster M, Monster Other)
{
    local Controller C;
    local MonsterController MC;
    local class<Controller> NClass;

    if (M == None)
        return None;

    // Same-species matchups (dino vs dino, skaarj vs skaarj): the stock
    // MonsterController refuses same-species targets via SameSpeciesAs().
    // Force OUR grudge controller onto BOTH fighters - it assigns
    // Enemy/Target directly and skips every stock species gate, so they
    // fight no matter how closely related they are.
    if (bSameSpeciesMatchup)
    {
        if (default.bLogDamage)
            log("MFC-AI: same-species fighter " $ M $ " native controller=" $ M.ControllerClass, 'MonsterFightClubV1');
        if (M.Controller != None)
            M.Controller.Destroy();
        C = Spawn(class'MonsterFightClubMonsterController');
        if (C != None)
        {
            MC = MonsterController(C);
            if (MC != None)
            {
                MC.Possess(M);
                MC.InitializeSkill(7.0);
                MonsterFightClubMonsterController(MC).SetGrudgeEnemy(Other);
                MC.WhatToDoNext(1);
            }
        }
        return C;
    }

    NClass = M.ControllerClass;
    if (NClass != None && NClass != class'MonsterController'
        && M.Controller != None)
    {
        // Custom pack controller - keep it, just force the grudge.
        C = M.Controller;
        C.Enemy = Other;
        C.Target = Other;
        MC = MonsterController(C);
        if (MC != None)
        {
            MC.InitializeSkill(7.0);
            MC.WhatToDoNext(1);
        }
        return C;
    }

    // Stock monster - replace the auto-spawned stock controller with our
    // grudge controller (destroy the old one so it doesn't ghost around
    // spamming RestFormation with no pawn).
    if (M.Controller != None)
        M.Controller.Destroy();
    C = Spawn(class'MonsterFightClubMonsterController');
    if (C != None)
    {
        MC = MonsterController(C);
        if (MC != None)
        {
            MC.Possess(M);
            MC.InitializeSkill(7.0);
            MonsterFightClubMonsterController(MC).SetGrudgeEnemy(Other);
            MC.WhatToDoNext(1);
        }
    }
    return C;
}

function Monster TrySpawnFighter(class<Monster> MClass, int SpotIndex)
{
    if (MClass == None || SpotIndex < 0 || SpotIndex >= StartSpots.Length)
        return None;
    return Spawn(MClass,,, StartSpots[SpotIndex].Location, StartSpots[SpotIndex].Rotation);
}

// Pick two player starts for the duel. The pair must be NO MORE than 1024
// units apart; among qualifying pairs the one closest to 1024 wins (close
// enough to be dramatic, far enough that they aren't on top of each other).
// If every pair on the map exceeds 1024, the CLOSEST pair is used so the
// fighters still start within reach of each other.
function bool GetDuelStarts(out int iA, out int iB)
{
    local int i, j, besti, bestj;
    local float d, bestScore, score;

    if (StartSpots.Length < 2)
        return false;

    besti = 0;
    bestj = 1;
    bestScore = 100000000.0;
    for (i = 0; i < StartSpots.Length; i++)
        for (j = i + 1; j < StartSpots.Length; j++)
        {
            d = VSize(StartSpots[i].Location - StartSpots[j].Location);
            if (d <= 1024.0)
                score = Abs(d - 1024.0);   // prefer pairs closest to 1024
            else
                score = 100000.0 + d;      // too far - only used if nothing qualifies
            if (score < bestScore)
            {
                bestScore = score;
                besti = i;
                bestj = j;
            }
        }
    iA = besti;
    iB = bestj;
    return true;
}

// Post-spawn guarantee: pull FighterB to ~900 units from FighterA (well
// inside the 1024 cap) with a clear line of sight, so big maps never need
// teleports to start a duel.
function ClampFightDistance()
{
    local vector Loc, HitLoc, HitNorm;
    local float D;

    if (FighterA == None || FighterB == None)
        return;
    D = VSize(FighterA.Location - FighterB.Location);
    if (D <= 1024.0)
        return;

    Loc = FighterA.Location + Normal(FighterB.Location - FighterA.Location) * 900;
    Loc.Z += 40;
    if (FighterB.Trace(HitLoc, HitNorm, Loc, FighterA.Location) != None)
        Loc = HitLoc + Normal(Loc - FighterA.Location) * 120;
    Loc.Z += FighterB.CollisionHeight;

    FighterB.SetLocation(Loc);
    FighterB.Velocity = vect(0,0,0);
    FighterB.SetPhysics(PHYS_Falling);
}

function vector GetLevelCenter()
{
    local int i;
    local vector C;
    if (StartSpots.Length == 0)
        return vect(0, 0, 200);
    for (i = 0; i < StartSpots.Length; i++)
        C += StartSpots[i].Location;
    C /= StartSpots.Length;
    C.Z += 120;
    return C;
}

function DestroyFighters()
{
    local Controller D;
    local MonsterController C, M;
    local array<MonsterController> Ghosts;
    local int i;

    if (FighterA != None)
    {
        if (FighterA.Controller != None)
            FighterA.Controller.Destroy();
        FighterA.Destroy();
        FighterA = None;
    }
    if (FighterB != None)
    {
        if (FighterB.Controller != None)
            FighterB.Controller.Destroy();
        FighterB.Destroy();
        FighterB = None;
    }

    // Sweep up any ghost controllers left behind by monsters that died
    // outside the normal kill path (they spam RestFormation with no pawn).
    // Snapshot into an array first - destroying controllers while walking
    // Level.ControllerList corrupts the iteration (freed NextController).
    for (D = Level.ControllerList; D != None; D = D.NextController)
    {
        C = MonsterController(D);
        if (C != None && C.Pawn == None)
            Ghosts[Ghosts.Length] = C;
    }

    for (i = 0; i < Ghosts.Length; i++)
    {
        M = Ghosts[i];
        if (M != None)
            M.Destroy();
    }
}

// Keep the monsters on each other instead of wandering off. Works with
// BOTH our grudge controller and custom pack controllers: direct
// Enemy/Target assignment works on any Controller, and the MonsterController-
// specific kicks (WhatToDoNext, Charging) are only used when available.
function EnforceFight(float dt)
{
    local float D;
    local bool bCanSee, bWandering;
    local Controller NCA, NCB;
    local MonsterController CA, CB;

    if (FighterA == None || FighterB == None)
        return;

    NCA = FighterA.Controller;
    NCB = FighterB.Controller;
    CA = MonsterController(NCA);
    CB = MonsterController(NCB);

    if (NCA == None || NCB == None)
    {
        StuckTime += dt;
        if (StuckTime > 3)
        {
            StuckTime = 0;
            SpawnFighters();   // a controller died - redo the round
        }
        return;
    }

    if (NCA.Enemy != FighterB)
    {
        NCA.Enemy = FighterB;
        NCA.Target = FighterB;
        if (CA != None)
            CA.WhatToDoNext(1);
    }
    if (NCB.Enemy != FighterA)
    {
        NCB.Enemy = FighterA;
        NCB.Target = FighterA;
        if (CB != None)
            CB.WhatToDoNext(1);
    }

    D = VSize(FighterA.Location - FighterB.Location);
    bCanSee = NCA.LineOfSightTo(FighterB);
    bWandering = ((CA != None && CA.GetStateName() == 'RestFormation')
               || (CB != None && CB.GetStateName() == 'RestFormation'));

    // If either fighter is sitting in RestFormation (refusing to engage),
    // kick them into an attack state directly - WhatToDoNext alone is
    // ignored by some monsters (e.g. Ice/Fire Skaarj) when already resting.
    if (bWandering)
    {
        if (CA != None && CA.GetStateName() == 'RestFormation' && CA.Enemy == FighterB)
        {
            CA.GotoState('Charging');
            CA.WhatToDoNext(1);
        }
        if (CB != None && CB.GetStateName() == 'RestFormation' && CB.Enemy == FighterA)
        {
            CB.GotoState('Charging');
            CB.WhatToDoNext(1);
        }
    }

    if (D > 2500 || (D > 1200 && !bCanSee) || bWandering)
        StuckTime += dt;
    else
        StuckTime = 0;

    if (StuckTime > 5 && bTeleportStuckFighters)
    {
        StuckTime = 0;
        TeleportFighter(FighterA, FighterB);
        if (NCA.Enemy != FighterB)
        {
            NCA.Enemy = FighterB;
            NCA.Target = FighterB;
            if (CA != None)
                CA.WhatToDoNext(1);
        }
        if (NCB.Enemy != FighterA)
        {
            NCB.Enemy = FighterA;
            NCB.Target = FighterA;
            if (CB != None)
                CB.WhatToDoNext(1);
        }
    }
    else if (StuckTime > 5)
        StuckTime = 0;   // teleports disabled - just keep re-aiming
}

function ReAimFighter(Monster M, Monster Other)
{
    local Controller NC;
    local MonsterController C;

    if (M == None || Other == None)
        return;
    NC = M.Controller;
    if (NC == None)
        return;

    // Direct assignment - never goes through the stock SetEnemy() gate,
    // which refuses same-species monsters (Skaarj vs Skaarj, two of the
    // same dino, ...).
    if (NC.Enemy != Other)
    {
        NC.Enemy = Other;
        NC.Target = Other;
        C = MonsterController(NC);
        if (C != None)
            C.WhatToDoNext(1);
    }
}

function TeleportFighter(Monster M, Monster Other)
{
    local vector Loc, HitLoc, HitNorm;
    local rotator Rot;
    local float Angle;
    local MonsterController C;

    if (M == None || Other == None)
        return;

    // Park M right next to the other fighter so they re-engage instantly
    // (the old code dropped them at a far spawn point, which let them
    // wander apart again).
    Angle = FRand() * 2 * Pi;
    Loc = Other.Location;
    Loc.X += 400 * Cos(Angle);
    Loc.Y += 400 * Sin(Angle);
    Loc.Z = Other.Location.Z;

    if (M.Trace(HitLoc, HitNorm, Loc, Other.Location) != None)
        Loc = HitLoc + Normal(Loc - Other.Location) * 100;

    Loc.Z += M.CollisionHeight;
    Rot = rotator(Other.Location - Loc);

    M.SetLocation(Loc);
    M.SetRotation(Rot);
    M.Velocity = vect(0,0,0);
    M.SetPhysics(PHYS_Falling);

    C = MonsterController(M.Controller);
    if (M.Controller != None)
    {
        M.Controller.Enemy = Other;
        M.Controller.Target = Other;
        C = MonsterController(M.Controller);
        if (C != None)
            C.WhatToDoNext(1);
    }
}

// Same-species grudges: the stock SetEnemy() refuses to hate another
// monster of the same species (SameSpeciesAs), and some pack controllers
// (e.g. DoomPawns MarineController) refuse the exact same class outright.
// Everything in this gametype therefore re-aims fighters with DIRECT
// Enemy/Target assignment - bypassing the gate entirely - and re-asserts
// it every second in EnforceFight() so even a controller that clears or
// swaps its own enemy gets dragged back to the grudge fight.

// Fair-fight enforcement: destroy every Monster in the level that is not
// one of the two booked fighters. Stock SkaarjPack monsters don't spawn
// children, but modded monster classes (which admins can add to the fight
// table) often spawn minions during a fight or on death - this keeps the
// show fair no matter what class is booked. Also sweeps up any strays a
// map spawner might produce.
function DestroyStrayMonsters()
{
    local Monster M;
    local Controller C;

    foreach DynamicActors(class'Monster', M)
    {
        if (M == FighterA || M == FighterB)
            continue;   // the booked fighters stay

        // Destroy the minion's controller too, so it doesn't linger as a
        // ghost in the controller list.
        C = M.Controller;
        if (C != None && PlayerController(C) == None)
            C.Destroy();
        M.Destroy();
    }
}

// Visibility watchdog: some custom monster packs hide their pawns mid-fight
// (stealth spawn fades, phase invisibility, or controller checks that fail
// when the fighter is possessed). Whatever the cause, a fighter that goes
// invisible ruins the show - force both fighters visible every second.
function EnforceFighterVisibility()
{
    if (FighterA != None && FighterA.Health > 0 && FighterA.bHidden)
    {
        FighterA.bHidden = false;
        FighterA.SetInvisibility(0.0);
    }
    if (FighterB != None && FighterB.Health > 0 && FighterB.bHidden)
    {
        FighterB.bHidden = false;
        FighterB.SetInvisibility(0.0);
    }
}

//==============================================================================
// Combat events
//==============================================================================

function Killed(Controller Killer, Controller Killed, Pawn KilledPawn, class<DamageType> damageType)
{
    if (Monster(KilledPawn) != None)
        OnMonsterKilled(Killer, Monster(KilledPawn));
    Super.Killed(Killer, Killed, KilledPawn, damageType);
}

function BroadcastDeathMessage(Controller Killer, Controller Other, class<DamageType> damageType)
{
    if (MonsterController(Killer) != None || MonsterController(Other) != None)
        return;   // monster deaths are covered by the round announcements
    Super.BroadcastDeathMessage(Killer, Other, damageType);
}

function int ReduceDamage(int Damage, pawn injured, pawn instigatedBy, vector HitLocation, out vector Momentum, class<DamageType> DamageType)
{
    local float Scale;

    // Debug: watch every hit on the booked fighters (bLogDamage in the ini).
    if (bLogDamage && (injured == FighterA || injured == FighterB
        || instigatedBy == FighterA || instigatedBy == FighterB))
        log("MFC-DMG: " $ instigatedBy $ " -> " $ injured
            $ " dmg=" $ Damage $ " type=" $ DamageType $ " hp=" $ injured.Health, 'MonsterFightClubV1');

    if (Monster(instigatedBy) != None && Monster(injured) != None)
    {
        Scale = GetFighterDamageScale(Monster(instigatedBy));
        return Super.ReduceDamage(Max(1, int(0.5 + Damage * Scale)), injured, instigatedBy, HitLocation, Momentum, DamageType);
    }
    return Super.ReduceDamage(Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
}

function float GetFighterDamageScale(Monster M)
{
    if (M == FighterA)
        return FighterADamageScale;
    if (M == FighterB)
        return FighterBDamageScale;
    return 1.0;
}

function OnMonsterKilled(Controller Killer, Monster Victim)
{
    local int Winner;   // 1 = A, 2 = B, 0 = draw

    if (Phase != PHASE_FIGHT)
        return;
    if (Victim != FighterA && Victim != FighterB)
        return;

    // Free the dead fighter's controller (custom pack controllers too) so
    // it stops roaming as a ghost and spamming "Accessed None 'Pawn'" in
    // RestFormation.
    if (Victim.Controller != None)
        Victim.Controller.Destroy();

    // The DEAD fighter decides the winner - whoever survived the round
    // wins, no matter what killed the loser (a fall, the environment, a
    // stray projectile, ...). Crediting kills to the dead monster made
    // viewers lose money on rounds they actually won.
    if (Victim == FighterA)
        Winner = 2;   // A died -> B wins
    else
        Winner = 1;   // B died -> A wins

    // simultaneous death = draw
    if (FighterA != None && FighterB != None && FighterA.Health <= 0 && FighterB.Health <= 0)
        Winner = 0;

    if (Winner == 0)
    {
        RoundTimeout();
        return;
    }

    Phase = PHASE_RESULT;
    PhaseClock = 0;
    bBettingOpen = false;

    RoundWins[Winner - 1]++;
    RoundNumber++;

    // The money shot
    TriggerSlowMo(Victim.Location);
    CutToLocation(Victim.Location, true);

    SettleBets(Winner);
    UpdateGRI();
    PushBettingState();

    Broadcast(Self, Caps(GetFighterName(Winner)) $ " DESTROYS " $ Caps(GetFighterName(3 - Winner)) $ "!", 'CriticalEvent');
    Broadcast(Self, "ROUND " $ (RoundNumber - 1) $ " GOES TO " $ Caps(GetFighterName(Winner)) $ " - SCORE " $ RoundWins[0] $ "-" $ RoundWins[1], 'CriticalEvent');
    log("MonsterFightClub: " $ GetFighterName(Winner) $ " wins round " $ (RoundNumber - 1) $ " (" $ RoundWins[0] $ "-" $ RoundWins[1] $ ")", 'MonsterFightClubV1');
}

function RoundTimeout()
{
    if (Phase != PHASE_FIGHT)
        return;

    Phase = PHASE_RESULT;
    PhaseClock = 0;
    bBettingOpen = false;

    RefundBets();
    RoundNumber++;
    UpdateGRI();
    PushBettingState();

    // A draw means BOTH monsters are destroyed - they don't get to keep
    // fighting; the next round books fresh fighters.
    DestroyFighters();

    Broadcast(Self, "TIME! ROUND " $ (RoundNumber - 1) $ " IS A DRAW - BOTH MONSTERS ARE DESTROYED, BETS REFUNDED", 'CriticalEvent');
    CutToFight(None, true);
}

function AdvanceRound()
{
    local int Target;
    Target = (RoundsPerMatch + 1) / 2;

    if (RoundWins[0] >= Target || RoundWins[1] >= Target || RoundNumber > RoundsPerMatch)
        BeginIntermission();
    else
        BeginBettingPhase();
}

function BeginIntermission()
{
    local int Champ;
    local string ChampName;

    Phase = PHASE_INTERMISSION;
    PhaseClock = 0;
    bBettingOpen = false;

    if (RoundWins[0] >= RoundWins[1])
        Champ = 1;
    else
        Champ = 2;
    ChampName = GetFighterName(Champ);

    // Gauntlet mode: the matchup winner becomes the standing champion and
    // will defend against a new challenger in the next matchup.
    if (bWinnerAdvances)
    {
        if (Champ == 1)
        {
            ChampionClass = FighterAClass;
            ChampionName = FighterAName;
        }
        else
        {
            ChampionClass = FighterBClass;
            ChampionName = FighterBName;
        }
        ChampionStreak++;   // won another matchup
        bChampionCrowned = true;
    }

    PublishChampion();

    UpdateGRI();
    PushBettingState();
    Broadcast(Self, Caps(ChampName) $ " TAKES THE MATCHUP " $ RoundWins[Champ - 1] $ "-" $ RoundWins[2 - Champ] $ "!", 'CriticalEvent');
    if (bWinnerAdvances)
    {
        if (ChampionStreak > 1)
            Broadcast(Self, Caps(ChampName) $ " DEFENDS AGAIN - STREAK " $ ChampionStreak $ " IN A ROW!", 'CriticalEvent');
        else
            Broadcast(Self, Caps(ChampName) $ " IS THE NEW CHAMPION!", 'CriticalEvent');
    }
    else
        Broadcast(Self, "NEW CHALLENGERS WILL BE CHOSEN SOON...", 'CriticalEvent');

    // let the cameras enjoy the celebration
    CutToFight(None, true);
}

// Send the current champion + streak to every client.
function PublishChampion()
{
    if (FCGRI != None)
    {
        FCGRI.ChampionName = ChampionName;
        FCGRI.ChampionStreak = ChampionStreak;
        FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
    }
}

//==============================================================================
// Slow motion kill cam
//==============================================================================

function TriggerSlowMo(vector Focus)
{
    if (!bSlowMoOnKill || bSlowMoActive)
        return;
    bSlowMoActive = true;
    SlowMoTimeLeft = SlowMoDuration;
    SavedTimeDilation = Level.TimeDilation;
    Level.TimeDilation = SlowMoScale;
    if (FCGRI != None)
        FCGRI.bSlowMo = true;
}

function RestoreTimeDilation()
{
    if (!bSlowMoActive)
        return;
    bSlowMoActive = false;
    Level.TimeDilation = SavedTimeDilation;
    if (FCGRI != None)
        FCGRI.bSlowMo = false;
}

//==============================================================================
// Bets
//==============================================================================

event Broadcast(Actor Sender, coerce string Msg, optional name Type)
{
    local PlayerController PC;
    local array<string> Parts;
    local int Amount, Fighter;
    local MonsterFightClubPRI MPRI;

    if (Type == 'Say' && PlayerController(Sender) != None)
    {
        PC = PlayerController(Sender);
        if (PC.PlayerReplicationInfo == None)
            return;

        // /reload - broke player tries their luck again with fresh money.
        if (Left(Caps(Msg), 7) == "/RELOAD")
        {
            MPRI = MonsterFightClubPRI(PC.PlayerReplicationInfo);
            if (MPRI != None)
            {
                MPRI.Money = StartMoney;
                MPRI.Score = StartMoney;
                // Fresh bankroll, clean slate: bets-won (mirrored into
                // Deaths for the scoreboard) resets with the money.
                MPRI.BetWins = 0;
                MPRI.Deaths = 0;
                MPRI.bOutOfLives = false;
                MPRI.NetUpdateTime = Level.TimeSeconds - 1;
                MonsterFightClubPlayerController(PC).bVoluntaryOut = false;
                PC.ClientMessage("Fresh $" $ StartMoney $ " - good luck!");
            }
            return;
        }

        // /out - broke player bows out and is marked Out on the scoreboard.
        if (Left(Caps(Msg), 3) == "/OUT")
        {
            MPRI = MonsterFightClubPRI(PC.PlayerReplicationInfo);
            if (MPRI != None)
            {
                MPRI.bOutOfLives = true;
                MPRI.NetUpdateTime = Level.TimeSeconds - 1;
                MonsterFightClubPlayerController(PC).bVoluntaryOut = true;
                PC.ClientMessage("You're Out. Type /reload anytime to rejoin the show.");
            }
            return;
        }

        if (Left(Caps(Msg), 4) == "/BET")
        {
            Split(Msg, " ", Parts);
            if (Parts.Length < 2)
            {
                PC.ClientMessage("Usage: /bet <amount|all> [1|2] - amounts: $" $ BetAmounts[0] $ ", $" $ BetAmounts[1] $ ", $" $ BetAmounts[2] $ ", $" $ BetAmounts[3] $ ", $" $ BetAmounts[4] $ ", $" $ BetAmounts[5] $ ", $" $ BetAmounts[6] $ ", $" $ BetAmounts[7] $ " or ALL. Bet on " $ FighterAName $ " (1) or " $ FighterBName $ " (2).");
                return;
            }

            Amount = -1;
            if (Caps(Parts[1]) != "ALL")
                Amount = int(Parts[1]);
            Fighter = 0;
            if (Parts.Length >= 3)
                Fighter = int(Parts[2]);

            HandleClientBet(PC, Amount, Fighter);
            return;   // swallow the command
        }
    }

    Super.Broadcast(Sender, Msg, Type);
}

// Shared bet validation + placement for the console command AND the menu RPC.
function bool HandleClientBet(PlayerController PC, int Amount, int Fighter)
{
    local MonsterFightClubPRI MPRI;
    local float Payout;

    if (PC == None || PC.PlayerReplicationInfo == None)
        return false;

    MPRI = MonsterFightClubPRI(PC.PlayerReplicationInfo);
    if (MPRI == None)
    {
        PC.ClientMessage("You have no bankroll yet.");
        return false;
    }
    if (!bBettingOpen)
    {
        PC.ClientMessage("Betting is closed right now. Watch the fight!");
        return false;
    }
    if (Amount == -1)
        Amount = MPRI.Money;   // "all" = all-in
    if (Amount <= 0)
    {
        PC.ClientMessage("Enter a valid amount (or ALL for all-in).");
        return false;
    }
    if (Amount > MPRI.Money)
    {
        PC.ClientMessage("You only have $" $ MPRI.Money $ ".");
        return false;
    }
    // NOTE: any amount 1..Money is allowed via /bet - the fixed presets
    // are only a convenience for the menu. Custom console bets work.
    if (Fighter != 1 && Fighter != 2)
    {
        if (FighterAPower >= FighterBPower)
            Fighter = 1;
        else
            Fighter = 2;
    }

    if (PlaceBet(MPRI, Amount, Fighter, PC))
    {
        Payout = Amount + Max(1, int(0.5 + Amount * GetOdds(Fighter)));
        if (Amount >= MPRI.Money)
            PC.ClientMessage("ALL-IN! $" $ Amount $ " on " $ GetFighterName(Fighter) $ ". Pays $" $ Payout $ " if they win.");
        else
            PC.ClientMessage("Bet placed: $" $ Amount $ " on " $ GetFighterName(Fighter) $ ". Pays $" $ Payout $ " if they win.");
        MarkReady(PC);   // placing a bet counts as ready
        return true;
    }
    PC.ClientMessage("Could not place that bet.");
    return false;
}

function bool PlaceBet(MonsterFightClubPRI MPRI, int Amount, int Fighter, Controller Sender)
{
    local BetEntry E;
    local int i;

    if (!bBettingOpen || Phase != PHASE_BETTING)
        return false;
    if (MPRI == None || Amount <= 0 || Amount > MPRI.Money)
        return false;
    if (Fighter != 1 && Fighter != 2)
        return false;

    // one bet per person per round
    for (i = 0; i < Bets.Length; i++)
        if (Bets[i].Bettor == MPRI)
        {
            Bets.Remove(i, 1);
            break;
        }

    E.Bettor = MPRI;
    E.Amount = Amount;
    E.Fighter = Fighter;
    Bets[Bets.Length] = E;

    MPRI.CurrentBet = Amount;
    MPRI.BetFighter = Fighter;
    MPRI.NetUpdateTime = Level.TimeSeconds - 1;
    return true;
}

//==============================================================================
// Ready system - the betting window ends as soon as every bettor has locked
// in (BettingTime is only a fallback so one straggler can't stall the show).
//==============================================================================

function ResetReady()
{
    local Controller C;
    local MonsterFightClubPRI MPRI;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        MPRI = MonsterFightClubPRI(C.PlayerReplicationInfo);
        if (MPRI != None)
        {
            MPRI.bReady = false;
            MPRI.NetUpdateTime = Level.TimeSeconds - 1;
        }
    }
}

function bool AllBettorsReady()
{
    local int i;
    local MonsterFightClubPRI MPRI;
    local bool bFound;
    local GameReplicationInfo GRI;

    // Use the live player list (GRI.PRIArray), NOT Level.ControllerList -
    // controllers of disconnected players linger there forever and would
    // block the round permanently.
    //
    // EVERYONE must be ready - humans AND bots. Bots auto-ready right after
    // they bet, so they never block a round on their own; a human who
    // hasn't readied keeps the betting window open until they do.
    GRI = GameReplicationInfo;
    if (GRI == None)
        return false;

    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        MPRI = MonsterFightClubPRI(GRI.PRIArray[i]);
        if (MPRI == None)
            continue;
        if (MPRI.bOutOfLives)
            continue;   // players who chose Out don't block the round
        bFound = true;
        if (!MPRI.bReady)
            return false;
    }
    return bFound;
}

function MarkReady(Controller C)
{
    local MonsterFightClubPRI MPRI;
    local int ReadyNum, TotalNum;

    if (Phase != PHASE_BETTING || C == None || C.PlayerReplicationInfo == None)
        return;
    MPRI = MonsterFightClubPRI(C.PlayerReplicationInfo);
    if (MPRI == None || MPRI.bReady)
        return;

    MPRI.bReady = true;
    MPRI.NetUpdateTime = Level.TimeSeconds - 1;

    GetReadyStats(ReadyNum, TotalNum);
    // announce humans only; bots quietly ready up after they bet
    if (PlayerController(C) != None)
        Broadcast(Self, C.PlayerReplicationInfo.PlayerName $ " is READY (" $ ReadyNum $ "/" $ TotalNum $ ")", 'CriticalEvent');

    if (AllBettorsReady())
        StartFight();
}

function GetReadyStats(out int ReadyNum, out int TotalNum)
{
    local int i;
    local MonsterFightClubPRI MPRI;
    local GameReplicationInfo GRI;

    GRI = GameReplicationInfo;
    if (GRI == None)
        return;

    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        MPRI = MonsterFightClubPRI(GRI.PRIArray[i]);
        if (MPRI == None)
            continue;
        TotalNum++;
        if (MPRI.bReady)
            ReadyNum++;
    }
}

function bool PlaceBotBet(MonsterFightClubBot B)
{
    local MonsterFightClubPRI MPRI;
    local int Amount, Fighter, i;
    local array<int> Fits;

    if (!bBettingOpen || Phase != PHASE_BETTING)
        return false;
    MPRI = MonsterFightClubPRI(B.PlayerReplicationInfo);
    if (MPRI == None || MPRI.Money < MinBet)
        return false;

    // Only the fixed amounts (plus a 25% all-in chance) - always one the
    // bot can afford.
    for (i = 0; i < 8; i++)
        if (BetAmounts[i] <= MPRI.Money)
            Fits[Fits.Length] = BetAmounts[i];
    if (Fits.Length == 0)
        return false;
    if (FRand() < 0.25)
        Amount = MPRI.Money;
    else
        Amount = Fits[Rand(Fits.Length)];

    // 70% of the time the bots back the favorite
    if (FRand() < 0.7)
    {
        if (FighterAPower >= FighterBPower)
            Fighter = 1;
        else
            Fighter = 2;
    }
    else
        Fighter = 1 + Rand(2);

    return PlaceBet(MPRI, Amount, Fighter, B);
}

function float GetOdds(int Fighter)
{
    if (Fighter == 1)
        return FighterBPower / Max(0.1, FighterAPower);
    return FighterAPower / Max(0.1, FighterBPower);
}

// The betting menu only offers these amounts (plus ALL-IN for the whole
// bankroll). /bet enforces the same list.
static function bool IsAllowedBetAmount(int Amount)
{
    local int i;

    for (i = 0; i < 8; i++)
        if (Amount == default.BetAmounts[i])
            return true;
    return false;
}

function string GetFighterName(int Fighter)
{
    if (Fighter == 2)
        return FighterBName;
    return FighterAName;
}

function RemoveExistingBet(MonsterFightClubPRI MPRI)
{
    local int i;
    for (i = 0; i < Bets.Length; i++)
        if (Bets[i].Bettor == MPRI)
        {
            Bets.Remove(i, 1);
            return;
        }
}

function SettleBets(int Winner)
{
    local int i, Payout;
    local MonsterFightClubPRI MPRI;
    local PlayerController PC;

    for (i = 0; i < Bets.Length; i++)
    {
        MPRI = Bets[i].Bettor;
        if (MPRI == None)
            continue;

        if (Bets[i].Fighter == Winner)
        {
            Payout = Bets[i].Amount + Max(1, int(0.5 + Bets[i].Amount * GetOdds(Winner)));
            AddMoney(MPRI, Payout);
            MPRI.BetWins++;
            MPRI.Deaths = MPRI.BetWins;
            PC = PlayerController(MPRI.Owner);
            if (PC != None)
                PC.ClientMessage("You won $" $ Payout $ "! (" $ Bets[i].Amount $ " stake + $" $ (Payout - Bets[i].Amount) $ " winnings)");
        }
        else
        {
            AddMoney(MPRI, -Bets[i].Amount);
            PC = PlayerController(MPRI.Owner);
            if (PC != None)
                PC.ClientMessage("You lost $" $ Bets[i].Amount $ ". Better luck next round!");
        }
        MPRI.CurrentBet = 0;
        MPRI.BetFighter = 0;
    }
    Bets.Length = 0;
}

function RefundBets()
{
    local int i;
    local MonsterFightClubPRI MPRI;
    local PlayerController PC;

    for (i = 0; i < Bets.Length; i++)
    {
        MPRI = Bets[i].Bettor;
        if (MPRI == None)
            continue;
        PC = PlayerController(MPRI.Owner);
        if (PC != None)
            PC.ClientMessage("Round drawn - your $" $ Bets[i].Amount $ " is refunded.");
        MPRI.CurrentBet = 0;
        MPRI.BetFighter = 0;
    }
    Bets.Length = 0;
}

function AddMoney(MonsterFightClubPRI MPRI, int Delta)
{
    if (MPRI == None)
        return;
    MPRI.Money = Max(0, MPRI.Money + Delta);
    MPRI.Score = MPRI.Money;
    MPRI.NetUpdateTime = Level.TimeSeconds - 1;
}

function MonsterFightClubPRI FindRichestPRI()
{
    local Controller C;
    local MonsterFightClubPRI Best, MPRI;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        MPRI = MonsterFightClubPRI(C.PlayerReplicationInfo);
        if (MPRI == None)
            continue;
        if (Best == None || MPRI.Money > Best.Money
            || (MPRI.Money == Best.Money && MPRI.BetWins > Best.BetWins))
            Best = MPRI;
    }
    return Best;
}

//==============================================================================
// Bot taunts (with portraits, courtesy of PRI.GetPortrait + Say)
//==============================================================================

function MaybeTaunt(MonsterFightClubBot B)
{
    local string S;
    local array<Controller> Candidates;
    local Controller C;
    local PlayerController PC;
    local PlayerReplicationInfo TargetPRI;

    if (Level.TimeSeconds - LastTauntTime < TauntCooldown)
        return;
    if (Phase != PHASE_FIGHT && Phase != PHASE_BETTING)
        return;
    LastTauntTime = Level.TimeSeconds;

    // gather everyone else in the audience
    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        if (C == B || C.PlayerReplicationInfo == None)
            continue;
        PC = PlayerController(C);
        if ((MonsterFightClubBot(C) != None) || (PC != None && PC.Player != None))
            Candidates[Candidates.Length] = C;
    }

    if (Candidates.Length > 0 && FRand() < 0.6)
    {
        TargetPRI = Candidates[Rand(Candidates.Length)].PlayerReplicationInfo;
        S = class'MonsterFightClubTaunts'.default.TargetTaunts[Rand(class'MonsterFightClubTaunts'.default.TargetTaunts.Length)];
        S = Repl(S, "%p", TargetPRI.PlayerName);
    }
    else if (FRand() < 0.5 && FighterAName != "" && FighterBName != ""
             && class'MonsterFightClubTaunts'.default.FighterTaunts.Length > 0)
    {
        // aimed at the CURRENT fighters - %a / %b become their names
        S = class'MonsterFightClubTaunts'.default.FighterTaunts[Rand(class'MonsterFightClubTaunts'.default.FighterTaunts.Length)];
        S = Repl(S, "%a", Caps(FighterAName));
        S = Repl(S, "%b", Caps(FighterBName));
    }
    else
        S = class'MonsterFightClubTaunts'.default.Taunts[Rand(class'MonsterFightClubTaunts'.default.Taunts.Length)];

    B.SayTaunt(S);
}

//==============================================================================
// Cameras
//==============================================================================

function vector GetFightFocus()
{
    if (FighterA != None && FighterB != None)
        return 0.5 * (FighterA.Location + FighterB.Location);
    if (FighterA != None)
        return FighterA.Location;
    if (FighterB != None)
        return FighterB.Location;
    return GetLevelCenter();
}

function UpdateCameras(bool bForce)
{
    local Controller C;
    local PlayerController PC;
    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        PC = PlayerController(C);
        if (PC != None && PC.PlayerReplicationInfo != None)
            SetSpectatorCamera(PC, GetFightFocus(), bForce);
    }
}

function CutToLocation(vector Focus, bool bForce)
{
    local Controller C;
    local PlayerController PC;
    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        PC = PlayerController(C);
        if (PC != None && PC.PlayerReplicationInfo != None)
            SetSpectatorCamera(PC, Focus, bForce);
    }
}

function CutToFight(PlayerController OnlyPC, bool bForce)
{
    if (OnlyPC != None)
        SetSpectatorCamera(OnlyPC, GetFightFocus(), bForce);
    else
        CutToLocation(GetFightFocus(), bForce);
}

function SetSpectatorCamera(PlayerController PC, vector Focus, bool bCut, optional bool bTeleport)
{
    // The STOCK spectator camera handles all camera work now (LMB cycles
    // fighters, RMB free cam, smooth engine chase-cam). Custom camera
    // pushes are disabled entirely so nothing fights the stock camera.
}

//==============================================================================
// Show driver — the MonsterFightClubDriver actor calls RoundTick() once per
// second, independent of the game state machine. The state override below is
// only a fallback in case the driver could not spawn.
//==============================================================================

state MatchInProgress
{
    function Timer()
    {
        // The STOCK time-limit clock: the stock MatchInProgress.Timer
        // decrements RemainingTime every game second and fires
        // EndGame("TimeLimit") at zero - the exact clock every stock
        // gametype uses. The HUD and scoreboard display this same
        // RemainingTime, so the clock on screen and the end of the show are
        // ALWAYS the same clock. No custom clock code.
        Super.Timer();
        if (!bDriverActive)
            RoundTick();
    }
}

auto state PendingMatch
{
    function Timer()
    {
        Super.Timer();
    }
}

function bool ShowHasStarted()
{
    return (Phase != PHASE_IDLE);
}

function RoundTick()
{
    local float PhaseTimeRemaining;

    if (Role != ROLE_Authority || bGameEnded || bShowEnded)
        return;

    // The audience is always listed as real players on the scoreboard.
    SpectatorFlagClock--;
    if (SpectatorFlagClock <= 0)
    {
        SpectatorFlagClock = 5;
        EnforceScoreboardFlags();
    }

    // Keep the fight 2-vs-0: destroy any monster that isn't a fighter
    // (children/minions spawned by some monster classes, strays from map
    // spawners, etc.).
    DestroyStrayMonsters();

    // Some custom monster packs hide their pawn mid-fight (stealth spawn
    // effects, phase-based invisibility, controller checks that fail when
    // possessed). The show must never have an invisible fighter - force
    // both fighters visible every second.
    EnforceFighterVisibility();

    PhaseClock += 1;
    CamClock += 1;
    HealthClock += 1;

    // live state telemetry — visible in System\MonsterFightClubV1.ini
    StatusClock += 1;
    if (StatusClock >= 5)
    {
        StatusClock = 0;
        WriteDebugStatus();
    }

    if (bSlowMoActive)
    {
        SlowMoTimeLeft -= 1;
        if (SlowMoTimeLeft <= 0)
            RestoreTimeDilation();
    }

    if (bMapSwitchPending)
    {
        MapSwitchClock -= 1;
        if (MapSwitchClock <= 0)
            SwitchMap();
    }

    if (HealthClock >= 1)
    {
        HealthClock = 0;
        UpdateGRIHealth();
    }

    // NOTE: no periodic random camera cuts - the client orbits smoothly on
    // its own at fixed framing. Round-start cuts re-anchor the orbit phase.

    switch (Phase)
    {
        case PHASE_BETTING:
            // The round starts ONLY when every bettor (humans AND bots) has
            // readied up. Bots auto-ready after betting, so a round never
            // starts before the human audience has locked in. No time-based
            // force-starts - the show waits for everyone.
            if (AllBettorsReady())
                StartFight();
            break;

        case PHASE_FIGHT:
            if (bSpawnPendingRetry)
            {
                SpawnRetryCount++;
                if (SpawnRetryCount >= 6)
                {
                    bSpawnPendingRetry = false;
                    BeginIntermission();
                }
                else
                    SpawnFighters();
            }
            EnforceFight(1);
            if (PhaseClock >= RoundTimeLimit)
                RoundTimeout();
            break;

        case PHASE_RESULT:
            if (PhaseClock >= ResultTime)
                AdvanceRound();
            break;

        case PHASE_INTERMISSION:
            if (PhaseClock >= IntermissionTime)
                StartNewMatchup();
            break;
    }

    // replicated countdown for the HUD
    if (FCGRI != None)
    {
        switch (Phase)
        {
            case PHASE_BETTING:     PhaseTimeRemaining = BettingTime;     break;
            case PHASE_FIGHT:       PhaseTimeRemaining = RoundTimeLimit;  break;
            case PHASE_RESULT:      PhaseTimeRemaining = ResultTime;      break;
            case PHASE_INTERMISSION:PhaseTimeRemaining = IntermissionTime;break;
            default:                PhaseTimeRemaining = 0;               break;
        }
        if (FCGRI.PhaseTimeLeft != Max(0, int(PhaseTimeRemaining - PhaseClock)))
        {
            FCGRI.PhaseTimeLeft = Max(0, int(PhaseTimeRemaining - PhaseClock));
            FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
        }
    }

    // Keep every viewer's betting/show state fresh - this heals any dropped
    // RPC and covers players who joined mid-phase.
    PushBettingState();
}

function bool HasHumanPlayers()
{
    local int i;
    local MonsterFightClubPRI MPRI;
    local GameReplicationInfo GRI;

    GRI = GameReplicationInfo;
    if (GRI == None)
        return false;

    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        MPRI = MonsterFightClubPRI(GRI.PRIArray[i]);
        if (MPRI != None && !MPRI.bBot)
            return true;
    }
    return false;
}

// The round the HUD/scoreboard should show. RoundNumber is incremented at
// round END, so during RESULT and INTERMISSION it already points at the
// NEXT round - which may not exist (a 2-0 sweep in best-of-3 has no round
// 3). Show the round that actually just happened instead.
function int GetDisplayRound()
{
    if (Phase == PHASE_RESULT || Phase == PHASE_INTERMISSION)
        return Max(1, RoundNumber - 1);
    return RoundNumber;
}

function UpdateGRI()
{
    if (FCGRI == None)
        return;
    FCGRI.Phase = Phase;
    // RoundNumber is incremented at round END, so clamp what we display
    // to the actual best-of-N total (otherwise the HUD shows "4/3").
    FCGRI.RoundNumber = Min(GetDisplayRound(), RoundsPerMatch);
    FCGRI.MatchupNumber = MatchupNumber;
    FCGRI.bBettingOpen = bBettingOpen;
}

// Admin-friendly periodic status line
function WriteDebugStatus()
{
    local string S;

    S = "phase=" $ Phase $ " round=" $ RoundNumber $ " matchups=" $ MatchupNumber;
    if (FighterA != None)
        S = S $ " fa=" $ FighterAName $ ":" $ FighterA.Health;
    else
        S = S $ " fa=none";
    if (FighterB != None)
        S = S $ " fb=" $ FighterBName $ ":" $ FighterB.Health;
    else
        S = S $ " fb=none";
    S = S $ " bets=" $ Bets.Length $ " slowmo=" $ bSlowMoActive;

    // silent ini telemetry only - no log spam
    default.DebugStatus = S;
    StaticSaveConfig();
}

function DebugWrite(string S)
{
    default.DebugStatus = S;
    StaticSaveConfig();
    log("MonsterFightClub: " $ S, 'MonsterFightClubV1');
}

function UpdateGRIHealth()
{
    if (FCGRI == None)
        return;
    // During BETTING the fighters don't exist yet - publish the PROBED
    // health (read from a spawned copy, which applies the pack's own ini
    // override). During a FIGHT/RESULT, a None fighter means it DIED - show
    // 0, never refill the bar with the probe value!
    if (FighterA != None)
    {
        FCGRI.FighterAHealth = FighterA.Health;
        FCGRI.FighterAMaxHealth = FighterA.HealthMax;
    }
    else if (Phase == PHASE_BETTING)
    {
        FCGRI.FighterAHealth = ProbeHealthA;
        FCGRI.FighterAMaxHealth = ProbeHealthA;
    }
    else
    {
        FCGRI.FighterAHealth = 0;
        FCGRI.FighterAMaxHealth = ProbeHealthA;
    }
    if (FighterB != None)
    {
        FCGRI.FighterBHealth = FighterB.Health;
        FCGRI.FighterBMaxHealth = FighterB.HealthMax;
    }
    else if (Phase == PHASE_BETTING)
    {
        FCGRI.FighterBHealth = ProbeHealthB;
        FCGRI.FighterBMaxHealth = ProbeHealthB;
    }
    else
    {
        FCGRI.FighterBHealth = 0;
        FCGRI.FighterBMaxHealth = ProbeHealthB;
    }
    FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
}

// High-frequency camera targets - called by the driver ~4x/sec so the
// client can keep the monsters centered between camera cuts. Also streams
// the focus straight to every viewer via a client RPC (no GRI dependency).
// Only sends when the focus actually moved, so the network stays quiet
// (avoids ping spikes on low-netspeed clients).
function CameraTick()
{
    local Controller C;
    local MonsterFightClubPlayerController MPC;
    local bool bAny, bChanged;
    local vector FA, FB;
    local Actor Hit;
    local vector HitLoc, HitNorm;

    FA = vect(0,0,0);
    FB = vect(0,0,0);
    if (FighterA != None)
    {
        FA = FighterA.Location;
        bAny = true;
    }
    if (FighterB != None)
    {
        FB = FighterB.Location;
        bAny = true;
    }

    if (FCGRI != None)
    {
        if (VSize(FCGRI.FighterALocation - FA) > 2 || VSize(FCGRI.FighterBLocation - FB) > 2
            || FCGRI.bFightersActive != bAny)
            bChanged = true;
        FCGRI.FighterALocation = FA;
        FCGRI.FighterBLocation = FB;
        FCGRI.bFightersActive = bAny;
        if (bChanged)
            FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
    }

    // Camera watchdog: if a viewer's camera is hopelessly far from the
    // fight (stuck against geometry, dropped RPC, glide stalled) OR has no
    // line of sight to the fight (stuck behind a wall/mesh/terrain even
    // when close), yank it to a fresh hard cut. Runs even when the focus
    // hasn't moved, so a stuck camera is always recovered within ~125ms.
    if (bAny)
    {
        for (C = Level.ControllerList; C != None; C = C.NextController)
        {
            MPC = MonsterFightClubPlayerController(C);
            if (MPC == None || MPC.PlayerReplicationInfo == None)
                continue;
            if (VSize(MPC.Location - GetFightFocus()) > 900)
            {
                SetSpectatorCamera(MPC, GetFightFocus(), true, true);
                continue;
            }
            // Close but no line of sight (buried in/behind geometry): force
            // a fresh cut so the camera never stares at a wall. Rate-limited
            // to once per 1.5s per player so a mid-glide camera isn't
            // spammed with cuts.
            if (Level.TimeSeconds - MPC.LastCamRescueTime > 1.5)
            {
                Hit = MPC.Trace(HitLoc, HitNorm, GetFightFocus(), MPC.Location, true, vect(0,0,0));
                if (Hit != None && Hit != FighterA && Hit != FighterB)
                {
                    MPC.LastCamRescueTime = Level.TimeSeconds;
                    SetSpectatorCamera(MPC, GetFightFocus(), true, true);
                }
            }
        }
    }

    if (!bChanged)
        return;   // nothing moved - don't spam the clients

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        MPC = MonsterFightClubPlayerController(C);
        if (MPC != None && MPC.PlayerReplicationInfo != None)
            MPC.ClientUpdateFocus(FA, FB, bAny);
    }
}

// Push the current betting/show state to every connected viewer.
// Only sends when the state actually changed, so a steady 1Hz stream
// doesn't hammer the clients' connections (keeps ping sane).
function PushBettingState()
{
    local Controller C;
    local MonsterFightClubPlayerController MPC;
    local int TimeLeft;
    local int OldPhase, OldRound, OldMatchup;
    local bool bChanged;

    if (FCGRI == None)
        return;

    switch (Phase)
    {
        case PHASE_BETTING:      TimeLeft = int(BettingTime - PhaseClock);     break;
        case PHASE_FIGHT:        TimeLeft = int(RoundTimeLimit - PhaseClock);  break;
        case PHASE_RESULT:       TimeLeft = int(ResultTime - PhaseClock);      break;
        case PHASE_INTERMISSION: TimeLeft = int(IntermissionTime - PhaseClock);break;
        default:                 TimeLeft = 0;                                 break;
    }
    TimeLeft = Max(0, TimeLeft);

    OldPhase = FCGRI.Phase;
    OldRound = FCGRI.RoundNumber;
    OldMatchup = FCGRI.MatchupNumber;
    if (OldPhase != Phase || OldRound != GetDisplayRound() || OldMatchup != MatchupNumber
        || FCGRI.bBettingOpen != bBettingOpen
        || FCGRI.FighterAName != FighterAName || FCGRI.FighterBName != FighterBName)
        bChanged = true;

    // always keep the GRI itself fresh (cheap, local)
    FCGRI.Phase = Phase;
    FCGRI.RoundNumber = Min(GetDisplayRound(), RoundsPerMatch);
    FCGRI.MatchupNumber = MatchupNumber;
    FCGRI.bBettingOpen = bBettingOpen;
    FCGRI.FighterAName = FighterAName;
    FCGRI.FighterBName = FighterBName;
    if (bChanged)
        FCGRI.NetUpdateTime = Level.TimeSeconds - 1;

    if (!bChanged)
        return;   // no state change - no need to push to clients

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        MPC = MonsterFightClubPlayerController(C);
        if (MPC != None && MPC.PlayerReplicationInfo != None)
            MPC.ClientBettingState(bBettingOpen, Phase, RoundNumber, MatchupNumber,
                                   FighterAName, FighterBName, TimeLeft);
    }
}

//==============================================================================
// Match end — the richest bankroll wins the show.
// IMPORTANT: the show must NOT restart the level when it ends — that would
// boot the audience. Override RestartGame to keep the server on the same map.
//==============================================================================

function EndGame(PlayerReplicationInfo Winner, string Reason)
{
    local MonsterFightClubPRI MPRI;

    // The show ONLY ends on the time limit. Score-limit endings (the stock
    // DM "25 kills" style checks) must never fire - a bankroll isn't a kill
    // score, and the show should keep running until the clock runs out.
    if (Reason ~= "ScoreLimit" || Reason ~= "KillLimit" || Reason ~= "FragLimit")
        return;

    // Once the time limit ends the show, never end it again. The stock
    // overtime loop re-fires EndGame every second, which used to spam the
    // winner message into the console forever.
    if (bShowEnded)
        return;
    bShowEnded = true;

    // The betting window dies with the show: close it everywhere so the
    // menu can't be opened (or stay open) during the end sequence. The
    // GRI flag is replicated so clients reject E until the next show.
    bBettingOpen = false;
    Phase = PHASE_INTERMISSION;
    if (FCGRI != None)
    {
        FCGRI.bShowEnded = true;
        FCGRI.bBettingOpen = false;
        FCGRI.Phase = PHASE_INTERMISSION;
        FCGRI.NetUpdateTime = Level.TimeSeconds - 1;
    }
    PushBettingState();

    if (Reason ~= "TimeLimit")
    {
        MPRI = FindRichestPRI();
        if (MPRI != None)
        {
            Winner = MPRI;
            if (GameReplicationInfo != None)
                GameReplicationInfo.Winner = Winner;
            Broadcast(Self, "SHOW'S OVER! " $ MPRI.PlayerName $ " WINS WITH $" $ MPRI.Money $ "!", 'CriticalEvent');
            log("MonsterFightClub: show over — " $ MPRI.PlayerName $ " wins with $" $ MPRI.Money, 'MonsterFightClubV1');
        }
    }
    Super.EndGame(Winner, Reason);
    DestroyFighters();
}

// The stock CheckEndGame rejects TIED team scores - and this show always
// has tied scores (nobody gets frags), so the stock EndGame could never
// actually END: it flipped into overtime and re-fired forever. When our
// show clock says it's over, the game must end, no questions asked.
function bool CheckEndGame(PlayerReplicationInfo Winner, string Reason)
{
    if (bShowEnded)
    {
        EndTime = Level.TimeSeconds + EndTimeDelay;
        return true;
    }
    return Super.CheckEndGame(Winner, Reason);
}

// The stock DM end-of-match announcements are irrelevant here - the show
// announces its own winner.
function PlayEndOfMatchMessage() { }

// Prevent the stock DeathMatch flow from traveling to "?restart" and booting
// the audience. The show simply keeps running on the same map.
function RestartGame()
{
    if ((GameRulesModifiers != None) && GameRulesModifiers.HandleRestartGame())
        return;
    if (bGameRestarted)
        return;
    bGameRestarted = true;

    if (VotingHandler != None && !VotingHandler.HandleRestartGame())
        return;

    // Never change levels / restart — the Monster Fight Club show is endless.
    log("MonsterFightClub: restart suppressed (show continues)", 'MonsterFightClubV1');
}

//==============================================================================
// Defaults
//==============================================================================

defaultproperties
{
     StartMoney=100
     MinBet=20
     AudienceMin=4
     RoundTimeLimit=60
     RoundsPerMatch=3
     BettingTime=10.000000
     ResultTime=5.000000
     IntermissionTime=7.000000
     CamInterval=6.000000
     TauntCooldown=12.000000
     bOnly1on1Maps=True
     bFilmGrain=True
     GrainAlpha=28
     bLetterbox=True
     bSlowMoOnKill=True
     SlowMoScale=0.300000
     SlowMoDuration=1.500000
     bTeleportStuckFighters=True
     bWinnerAdvances=False
     ChampionStreakLimit=3
     SpeciesGroupBases(0)="Dinotopia.Dinosaur"

     BellSound=sound'MonsterFightClubV1.BellSound'

     BellVolume=255
     bLogDamage=False
     BetAmounts(0)=1
     BetAmounts(1)=5
     BetAmounts(2)=10
     BetAmounts(3)=20
     BetAmounts(4)=50
     BetAmounts(5)=100
     BetAmounts(6)=500
     BetAmounts(7)=1000

     MinPlayers=4
     MaxPlayers=32
     MaxSpectators=32
     TimeLimit=15
     GoalScore=0

     GameName="Monster Fight Club"
     Description="Two random monsters fight a best-of-three grudge match while the audience bets on the outcome. Richest bankroll wins the show!"
     Acronym="MFC"
     ScreenShotName="UT2004Thumbnails.DMShots"
     DecoTextName="MonsterFightClubV1.MonsterFightClubGame"
     BeaconName="MFC"

     HUDType="MonsterFightClubV1.MonsterFightClubHUD"
     ScoreBoardType="MonsterFightClubV1.MonsterFightClubScoreboard"
     MapListType="MonsterFightClubV1.MapListMonsterFightClub"
     MapPrefix="DM"
     GameReplicationInfoClass=Class'MonsterFightClubV1.MonsterFightClubGRI'
     PlayerControllerClassName="MonsterFightClubV1.MonsterFightClubPlayerController"
}
