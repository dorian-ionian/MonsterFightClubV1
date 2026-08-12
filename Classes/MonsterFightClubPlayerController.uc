//=============================================================================
// MonsterFightClubPlayerController
// Locked cinematic spectator. No pawn, no input, no view switching —
// the show's cameras do all the work, and the camera smoothly tracks the
// fighters every frame so the monsters stay centered.
//
// Betting menu (no console needed):
//   E            toggle the menu
//   1 / 2        pick fighter A / B
//   wheel        amount (menu open) / zoom the fighter cards (menu closed)
//   LMB          place the bet (auto-readies)
//   RMB          close the menu
//   Backslash    spectator cam <-> action cam
//=============================================================================
class MonsterFightClubPlayerController extends XPlayer;

var() config bool bLogCamera;   // debug: log the camera state once per second
var() config bool bLogInput;    // debug: log input/key events
var float CamLogClock;          // debug: accumulator for the camera log

var bool bBetMenuOpen;
var int BetMenuPreset;      // 0=$1 1=$5 2=$10 3=$20 4=$50 5=$100 6=$500 7=$1000 8=ALL-IN
var int BetMenuFighter;     // 1 or 2
var vector CamOffset;       // current camera offset from the fight midpoint
var vector DesiredOffset;   // where the server wants the camera (latest cut)
var bool bCamOffsetValid;
var bool bCutPending;       // gliding into a fresh camera angle
var int LastCutID;          // last applied camera cut
var vector SmoothedMid;     // client-smoothed fight focus (kills 8Hz jumps)
var bool bSmoothedMidValid;
var int CamRigIndex;        // which broadcast rig is live (0 = main, 1 = corner A, 2 = corner B)
var float CutClock;         // time until the next director's cut (8-14s)
var float BlockedTime;      // how long the current shot has been blocked by geometry
var float CamOrbitAngle;    // persistent orbit phase - the rigs revolve around the fight
var bool bActionCam;        // true = boxing/action camera (rigs), false = stock spectator cam

// Client state pushed from the server via RPCs (independent of GRI
// replication, which proved unreliable on the client).
var bool bFocusActive;      // at least one fighter is alive
var vector FightFocusA, FightFocusB;
var bool bBetStateReceived;
var bool bBettingOpenClient;
var int ClientPhase;
var int ClientRound;
var int ClientMatchup;
var int ClientPhaseTimeLeft;
var string ClientFighterAName, ClientFighterBName;
var float LastCamRescueTime;    // rate-limiter for the server's LOS camera watchdog
var bool bInputInteractionAdded; // the MMB/Backslash interaction is attached
var bool bVoluntaryOut;         // player chose /out - keep them marked Out
var float PreviewZoom;          // client-side zoom for the fighter cards (wheel)

replication
{
    // Change-gated (only sent when the fight focus moves), so reliable is
    // cheap and guarantees the client never loses tracking - an unreliable
    // RPC dropped by packet loss left the camera frozen on a stale focus.
    reliable if (Role == ROLE_Authority)
        ClientUpdateFocus;

    reliable if (Role == ROLE_Authority)
        ClientBettingState, ClientCameraCut;

    reliable if (Role < ROLE_Authority)
        ServerReadyUp;
}

// Server -> client: live fight focus, ~4x/sec.
simulated function ClientUpdateFocus(vector FA, vector FB, bool bActive)
{
    FightFocusA = FA;
    FightFocusB = FB;
    bFocusActive = bActive;
}

// Server -> client: current betting/show state, on every phase change.
simulated function ClientBettingState(bool bOpen, int PhaseNum, int RoundNum, int MatchupNum,
                                      coerce string NameA, coerce string NameB, int TimeLeft)
{
    bBettingOpenClient = bOpen;
    ClientPhase = PhaseNum;
    ClientRound = RoundNum;
    ClientMatchup = MatchupNum;
    ClientFighterAName = NameA;
    ClientFighterBName = NameB;
    ClientPhaseTimeLeft = TimeLeft;
    bBetStateReceived = true;
}

// Server -> client: a fresh camera angle (only sent at round starts now).
// The client's over-the-shoulder camera is fully self-driven; cuts just
// re-validate the local state.
simulated function ClientCameraCut(vector Offset, int CutID, bool bSnap)
{
    DesiredOffset = Offset;
    LastCutID = CutID;
    if (bSnap || !bCamOffsetValid)
    {
        bCamOffsetValid = true;
        bCutPending = false;
    }
}

//------------------------------------------------------------------------------
// Class-level hooks — these run in ANY state, so the betting menu and the
// monster-tracking camera work even if the client hasn't reached the
// Spectating state yet (e.g. right after joining).
//------------------------------------------------------------------------------

// On the CLIENT only (Player != None), attach the input interaction that
// catches the middle mouse button / Backslash and toggles the action
// camera - no User.ini editing needed for any player.
simulated event PostBeginPlay()
{
    Super.PostBeginPlay();
    if (Role < ROLE_Authority && Player != None)
        RegisterInputInteraction();
}

// Register the MMB/Backslash input interaction (client only). Retries
// each tick if the InteractionMaster isn't ready yet - never gives up.
simulated function RegisterInputInteraction()
{
    local Interaction I;

    if (bInputInteractionAdded)
        return;
    if (Player == None || Player.InteractionMaster == None)
        return;   // not ready - try again next tick

    I = Player.InteractionMaster.AddInteraction(
        string(class'MonsterFightClubInputInteraction'), Player);
    if (I != None)
    {
        bInputInteractionAdded = true;
        if (bLogInput)
            log("MFC-INPUT: interaction registered (MMB toggles action cam)", 'MonsterFightClubV1');
    }
}

exec function Use()
{
    // DIAGNOSTIC: log every Use trigger (bLogInput in the ini).
    if (bLogInput)
        log("MFC-INPUT: Use() called", 'MonsterFightClubV1');
    if (!bBetMenuOpen)
    {
        ToggleBetMenu();
        return;
    }
    CloseBetMenu();
}

simulated function PlayerTick(float DeltaTime)
{
    Super.PlayerTick(DeltaTime);
    ClearSpectatorFlags();

    // Fallback registration: if PostBeginPlay ran before Player attached,
    // add the input interaction now (client-side only).
    if (Role < ROLE_Authority)
        RegisterInputInteraction();

    // The betting menu only lives while the window is open. If the window
    // closes (round starts, show ends) any open menu closes with it, so it
    // can never linger over a fight or the end sequence.
    if (bBetMenuOpen && !IsBettingOpenClient())
        CloseBetMenu();

    if (bActionCam)
        TrackFighters(DeltaTime);
}

// Middle mouse / Backslash: toggle between the boxing/action camera and
// the standard spectator camera.
exec function ThrowWeapon()
{
    ToggleActionCam();
}

// Also bindable directly (e.g. set MiddleMouse=ToggleActionCam in User.ini).
exec function ToggleActionCam()
{
    bActionCam = !bActionCam;
    if (bLogInput)
        log("MFC-INPUT: ToggleActionCam -> " $ bActionCam, 'MonsterFightClubV1');
    if (bActionCam)
    {
        // The rig camera drives the PC's own location/rotation, so the
        // view target must be SELF (same as freecam) - the engine chase
        // cam on a fighter would override our camera every frame.
        ServerViewSelf();
        ClientMessage("ACTION CAMERA: boxing broadcast rigs");
        // Re-anchor the rig to the current position so there's no jump.
        bCamOffsetValid = true;
        CamRigIndex = Rand(3);
        CutClock = 6.0 + FRand() * 4.0;
    }
    else
    {
        ClientMessage("STANDARD CAMERA: LMB = cycle fighters, RMB = free cam");
        // Hand control back to the stock spectator camera - lock onto a
        // fighter so the transition is smooth.
        ServerViewNextPlayer();
    }
}

state Spectating
{
    ignores SeePlayer, HearNoise, KilledBy, NotifyBump, HitWall,
           NotifyHeadVolumeChange, NotifyPhysicsVolumeChange, Falling,
           TakeDamage;

    function BeginState()
    {
        Super.BeginState();
        ClearSpectatorFlags();
        // Lock onto a fighter with the STOCK spectator chase camera
        // (server-side only - the replicated ViewTarget updates the
        // client). No custom camera code - the engine handles everything.
        if (Role == ROLE_Authority)
            ServerViewNextPlayer();
    }

    // LMB: with the betting menu open, place bet + ready. Otherwise use
    // the STANDARD spectator camera - cycle the view to the next fighter.
    // (In action-cam mode the custom camera owns the view, so LMB is a no-op.)
    exec function Fire(optional float F)
    {
        if (bBetMenuOpen)
        {
            PressActionButton();
            return;
        }
        if (!bActionCam)
            ServerViewNextPlayer();
    }

    // RMB: with the menu open, close it. Otherwise switch to FREE CAM
    // (standard spectator behavior - WASD + mouse to fly around).
    exec function AltFire(optional float F)
    {
        if (bBetMenuOpen)
        {
            CloseBetMenu();
            return;
        }
        if (!bActionCam)
            ServerViewSelf();
    }

    exec function SwitchWeapon(byte T) { HandleMenuKey(T); }
    exec function Suicide() {}
    function ServerReStartPlayer() {}

    // In action-cam mode TrackFighters (PlayerTick) owns the camera -
    // block the stock freecam movement so WASD/mouse can't fight it.
    function PlayerMove(float DeltaTime)
    {
        if (bActionCam)
            return;
        Super.PlayerMove(DeltaTime);
    }

    // NOTE: no PlayerMove/ProcessMove overrides here - the stock
    // BaseSpectating versions provide the free-cam movement (WASD + mouse)
    // and smooth spectator view handling.
}

// Safety net: if the client is still in the stock waiting state when the
// player presses a key, route the menu keys anyway.
state PlayerWaiting
{
    function BeginState()
    {
        Super.BeginState();
        ClearSpectatorFlags();
    }

    exec function Fire(optional float F)
    {
        local MonsterFightClubGRI G;

        if (bBetMenuOpen)
        {
            PressActionButton();
            return;
        }
        G = MonsterFightClubGRI(GameReplicationInfo);
        if (bBettingOpenClient || (G != None && G.bBettingOpen))
            ToggleBetMenu();
        else
            Super.Fire(F);
    }

    exec function AltFire(optional float F)
    {
        if (bBetMenuOpen)
        {
            CloseBetMenu();
            return;
        }
        Super.AltFire(F);
    }

    exec function Use()
    {
        ToggleBetMenu();
    }

    exec function SwitchWeapon(byte T)
    {
        if (bBetMenuOpen)
        {
            HandleMenuKey(T);
            return;
        }
        Super.SwitchWeapon(T);
    }

    function PlayerMove(float DeltaTime)
    {
    }

    function ServerReStartPlayer() {}   // the audience never joins the fight
}

// The audience stays on the scoreboard like real players. The stock
// spectator code keeps re-flagging bIsSpectator/bOnlySpectator/bOut, so
// this runs every tick to keep the row alive. Players who chose /out keep
// their Out status on the scoreboard until they /reload or reconnect.
simulated function ClearSpectatorFlags()
{
    local MonsterFightClubPRI MPRI;

    MPRI = MonsterFightClubPRI(PlayerReplicationInfo);
    if (MPRI == None)
        return;

    if (bVoluntaryOut)
    {
        // Stay Out on the scoreboard, but never a pure spectator.
        MPRI.bIsSpectator = false;
        MPRI.bOnlySpectator = false;
        MPRI.bOutOfLives = true;
        MPRI.NetUpdateTime = Level.TimeSeconds - 1;
        return;
    }

    if (MPRI.bIsSpectator || MPRI.bOnlySpectator || MPRI.bOutOfLives)
    {
        MPRI.bIsSpectator = false;
        MPRI.bOnlySpectator = false;
        MPRI.bOutOfLives = false;
        MPRI.NetUpdateTime = Level.TimeSeconds - 1;
    }
}

//------------------------------------------------------------------------------
// Betting menu
//------------------------------------------------------------------------------

simulated function ToggleBetMenu()
{
    local MonsterFightClubGRI G;

    if (bBetMenuOpen)
    {
        CloseBetMenu();
        return;
    }
    if (PlayerReplicationInfo == None)
        return;

    // Betting must actually be open to open the menu. Also require the
    // GRI phase to be betting (1) - the pushed bool alone can be stale
    // right as a fight starts.
    G = MonsterFightClubGRI(GameReplicationInfo);
    if (G != None && G.bShowEnded)
    {
        ClientMessage("The show is over!");
        return;
    }
    if (G != None && G.Phase != 1)
    {
        ClientMessage("Betting is closed - watch the fight!");
        return;
    }
    if (bBetStateReceived)
    {
        if (!bBettingOpenClient)
        {
            ClientMessage("Betting is closed - watch the fight!");
            return;
        }
    }
    else
    {
        if (G == None || !G.bBettingOpen)
        {
            ClientMessage("Betting is closed - watch the fight!");
            return;
        }
    }

    BetMenuPreset = 0;
    BetMenuFighter = 1;
    bBetMenuOpen = true;
}

simulated function CloseBetMenu()
{
    bBetMenuOpen = false;
}

simulated function HandleMenuKey(byte T)
{
    if (!bBetMenuOpen)
        return;

    // Number keys select the fighter ONLY - the bet amount is controlled
    // with the mouse wheel (custom amounts via /bet in the console).
    if (T == 1 || T == 2)
        BetMenuFighter = T;
}

// Mouse wheel: with the betting menu open it cycles the amount; with the
// menu CLOSED while the fighter cards are up it zooms the preview models
// (same direction as the freecam: wheel UP = zoom OUT, wheel DOWN = zoom
// IN). Everywhere else (fight in progress) it falls through to the stock
// path, which zooms the spectator camera via CameraDist.
exec function NextWeapon()
{
    if (bBetMenuOpen)
    {
        CycleAmount(1);
        return;
    }
    if (IsBettingOpenClient())
    {
        ZoomPreview(-1);   // wheel up = zoom out (matches freecam)
        return;
    }
    Super.NextWeapon();
}

exec function PrevWeapon()
{
    if (bBetMenuOpen)
    {
        CycleAmount(-1);
        return;
    }
    if (IsBettingOpenClient())
    {
        ZoomPreview(1);   // wheel down = zoom in (matches freecam)
        return;
    }
    Super.PrevWeapon();
}

// True while the betting window is open (either the pushed client state
// or the replicated GRI flag - whichever arrived first).
simulated function bool IsBettingOpenClient()
{
    local MonsterFightClubGRI G;

    if (bBetStateReceived)
        return bBettingOpenClient;
    G = MonsterFightClubGRI(GameReplicationInfo);
    if (G != None)
        return G.bBettingOpen;
    return false;
}

// Wheel zoom for the fighter preview cards. 0.15 per notch, clamped so
// the model stays around the card's default fit.
simulated function ZoomPreview(int Dir)
{
    PreviewZoom = FClamp(PreviewZoom + Dir * 0.15, 0.6, 2.5);
    if (bLogInput)
        log("MFC-INPUT: preview zoom -> " $ PreviewZoom, 'MonsterFightClubV1');
}

simulated function CycleAmount(int Dir)
{
    BetMenuPreset = BetMenuPreset + Dir;
    if (BetMenuPreset > 8)
        BetMenuPreset = 0;
    if (BetMenuPreset < 0)
        BetMenuPreset = 8;
}

// Lock in as ready for the current round. The fight starts as soon as
// everyone has readied up (placing a bet also readies you).
function ServerReadyUp()
{
    local MonsterFightClubGame G;

    G = MonsterFightClubGame(Level.Game);
    if (G != None)
        G.MarkReady(self);
}

simulated function int GetMenuAmount()
{
    local MonsterFightClubPRI MPRI;

    if (BetMenuPreset == 8)
    {
        // ALL-IN
        MPRI = MonsterFightClubPRI(PlayerReplicationInfo);
        if (MPRI != None)
            return MPRI.Money;
        return 0;
    }
    return class'MonsterFightClubGame'.default.BetAmounts[BetMenuPreset];
}

simulated function PlaceBetFromMenu()
{
    local int Amt;

    if (!bBetMenuOpen)
        return;
    Amt = GetMenuAmount();
    if (Amt > 0 && (BetMenuFighter == 1 || BetMenuFighter == 2))
        Mutate("bet " $ Amt $ " " $ BetMenuFighter);
    // Bet placed - close the menu so the player watches the fight.
    CloseBetMenu();
}

// The single action button: place the selected bet (which auto-readies).
// ALWAYS attempts the bet - the server validates (stale client state can
// never make LMB silently do nothing).
simulated function PressActionButton()
{
    if (!bBetMenuOpen)
        return;
    PlaceBetFromMenu();
    ServerReadyUp();
}

// The stock exec Mutate() sends its string to the server via this RPC.
// We intercept our "bet ..." payload here and route it to the game;
// everything else keeps flowing to the mutator chain as usual.
function ServerMutate(string MutateString)
{
    local MonsterFightClubGame G;
    local array<string> Parts;
    local int Amount, Fighter;

    if (Left(Caps(MutateString), 4) == "BET ")
    {
        G = MonsterFightClubGame(Level.Game);
        if (G != None)
        {
            Split(MutateString, " ", Parts);
            Amount = 0;
            if (Parts.Length >= 2)
                Amount = int(Parts[1]);
            Fighter = 0;
            if (Parts.Length >= 3)
                Fighter = int(Parts[2]);

            G.HandleClientBet(self, Amount, Fighter);
        }
        return;
    }

    Super.ServerMutate(MutateString);
}

//------------------------------------------------------------------------------
// Camera: boxing-broadcast style.
//
// Three FIXED ring-side camera rigs around the fight (main + two corners),
// like real TV cameras bolted to the arena floor. The director hard-cuts
// between them every 8-14s (a real "cut to camera 2"), and between cuts the
// live camera smoothly re-centers on the action like a cameraman tracking
// the fighters. There is NO orbit - the rigs never move around the fight.
//
// The camera sits at the SAME height as its aim point (torso level), so
// the view is perfectly parallel to the floor/terrain - never top-down.
//------------------------------------------------------------------------------

simulated function TrackFighters(float DeltaTime)
{
    local vector Mid, Aim, TargetLoc, NewLoc, HitLoc, HitNorm;
    local rotator NewRot;
    local Actor Hit;
    local int NewRig;
    local bool bBlocked;

    if (!bCamOffsetValid)
        return;

    // --- Fight midpoint (smoothed against 8Hz focus updates) ---
    if (!GetFightMidpoint(Mid, DeltaTime))
        return;

    // --- Debug camera log (1/sec, config-gated) ---
    if (bLogCamera)
    {
        CamLogClock -= DeltaTime;
        if (CamLogClock <= 0)
        {
            CamLogClock = 1.0;
            log("MFC-CAM loc=" $ int(Location.X) $ "," $ int(Location.Y) $ "," $ int(Location.Z)
                $ " mid=" $ int(Mid.X) $ "," $ int(Mid.Y) $ "," $ int(Mid.Z)
                $ " rig=" $ CamRigIndex $ " blocked=" $ int(BlockedTime * 10)
                $ " cut=" $ int(CutClock), 'MonsterFightClubV1');
        }
    }

    Aim = Mid;
    Aim.Z += 70;   // aim at the fighters' torsos

    // --- Director: cut to a different rig periodically, or NOW when the
    // current shot has been blocked by a wall for too long (stuck escape) ---
    CutClock -= DeltaTime;
    Hit = Trace(HitLoc, HitNorm, Mid + vect(0,0,70), Location, true, vect(0,0,0));
    bBlocked = (Hit != None && Hit.bWorldGeometry && HitNorm.Z < 0.7);
    if (bBlocked)
    {
        BlockedTime += DeltaTime;
        if (BlockedTime > 1.0)
            CutClock = Min(CutClock, 0.0);   // stuck - cut NOW to a different rig
    }
    else
        BlockedTime = 0;

    if (CutClock <= 0)
    {
        CutClock = 8.0 + FRand() * 6.0;   // next cut in 8-14s
        NewRig = CamRigIndex;
        while (NewRig == CamRigIndex)
            NewRig = Rand(3);             // always cut to a DIFFERENT rig
        CamRigIndex = NewRig;
        bCutPending = true;
    }

    TargetLoc = GetRigPosition(Mid);
    TargetLoc = PopOutOfGeometry(TargetLoc);

    // The rigs slowly orbit the fight midpoint - once one fighter is down
    // that IS the winner, so the camera circles the champion like a
    // broadcast cameraman. Smooth and constant, no jumps.
    CamOrbitAngle += DeltaTime * 0.15;

    if (bCutPending)
    {
        // Hard TV cut: snap instantly to the new rig's position.
        bCutPending = false;
        NewLoc = TargetLoc;
        NewRot = rotator(Aim - NewLoc);
        SetLocation(NewLoc);            // server-side only on cuts - see below
        SetRotation(NewRot);
        ClientSetLocation(NewLoc, NewRot);
    }
    else
    {
        // Smooth re-center: a cameraman tracking the action. Constant
        // damping, no orbit, no snap - the rig only translates to keep the
        // fighters centered as they move. Client-side ONLY: SetLocation
        // every frame replicated the camera position to the server and
        // spiked latency.
        NewLoc = Location + (TargetLoc - Location) * FMin(1.0, 4.0 * DeltaTime);
        NewRot = rotator(Aim - NewLoc);
        ClientSetLocation(NewLoc, NewRot);
    }
}

// The world position of the current rig around the fight midpoint. The
// rigs sit at the shared orbit angle (plus a 120-degree offset each), so
// the whole camera setup revolves around the fight/winner.
simulated function vector GetRigPosition(vector Mid)
{
    local float RigAngle;
    local vector Loc;

    switch (CamRigIndex)
    {
        case 0:   RigAngle = CamOrbitAngle;          break;   // main camera
        case 1:   RigAngle = CamOrbitAngle + 2.094;  break;   // corner camera A (120 deg)
        default:  RigAngle = CamOrbitAngle + 4.189;  break;   // corner camera B (240 deg)
    }

    Loc = Mid;
    Loc.X += 320 * Cos(RigAngle);
    Loc.Y += 320 * Sin(RigAngle);
    Loc.Z += 70;   // same height as the aim - perfectly parallel view
    return Loc;
}

// Compute the fight midpoint to track: the smoothed center of the two
// fighters (or the lone survivor). Returns false if there's nothing yet.
simulated function bool GetFightMidpoint(out vector Mid, float DeltaTime)
{
    local vector MidRaw;

    if (bFocusActive)
    {
        if (FightFocusA != vect(0,0,0) && FightFocusB != vect(0,0,0))
            MidRaw = 0.5 * (FightFocusA + FightFocusB);
        else if (FightFocusA != vect(0,0,0))
            MidRaw = FightFocusA;
        else if (FightFocusB != vect(0,0,0))
            MidRaw = FightFocusB;
        else
            return false;

        if (!bSmoothedMidValid)
        {
            SmoothedMid = MidRaw;
            bSmoothedMidValid = true;
        }
        else
            SmoothedMid += (MidRaw - SmoothedMid) * FMin(1.0, 8.0 * DeltaTime);
        Mid = SmoothedMid;
        return true;
    }

    if (!bSmoothedMidValid)
        return false;
    Mid = SmoothedMid;
    return true;
}

//------------------------------------------------------------------------------
// Robust geometry escape. Traces DOWN from 2500 units above the camera
// (starting OUTSIDE the geometry). If the first solid hit is ABOVE the
// camera, the camera is buried inside a floor / terrain / BSP / static
// mesh - pop it onto the surface, 90 units above. This is far more
// reliable than an up-trace from the camera itself, because traces started
// INSIDE a static mesh often return nothing in UT2004 - which is why the
// camera used to stay stuck in floors and meshes.
//------------------------------------------------------------------------------

simulated function vector PopOutOfGeometry(vector Loc)
{
    local Actor Hit;
    local vector HitLoc, HitNorm;

    // bTraceActors=false: only world geometry (BSP, terrain, static meshes)
    // counts - monsters and players walking overhead don't trigger it.
    Hit = Trace(HitLoc, HitNorm, Loc + vect(0,0,2500), Loc, false, vect(0,0,0));
    if (Hit != None && HitLoc.Z > Loc.Z + 10)
        return HitLoc + vect(0,0,90);
    return Loc;
}

defaultproperties
{
     PlayerReplicationInfoClass=Class'MonsterFightClubV1.MonsterFightClubPRI'
     CamRigIndex=0
     CutClock=8.000000
     bActionCam=False
     PreviewZoom=1.000000
     bLogCamera=False
     bLogInput=False
}
