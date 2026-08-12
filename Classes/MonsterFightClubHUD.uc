//=============================================================================
// MonsterFightClubHUD
// TV-frame presentation: letterbox bars, fight info with health bars,
// bankroll/bet status, animated film grain, the interactive betting menu
// and chat portraits for pawn-less bots.
//=============================================================================
class MonsterFightClubHUD extends HudCDeathMatch;

var bool bHudStateLogged;
var PlayerReplicationInfo ChatPortraitPRI;
var float ChatPortraitTime;
var MonsterFightClubPreviewActor PreviewActorA, PreviewActorB;   // 3D fighter previews
var string PreviewAClass, PreviewBClass;   // class names the previews were built for

simulated event PostRender(Canvas C)
{
    Super.PostRender(C);
    if (PlayerOwner == None || PlayerOwner.PlayerReplicationInfo == None)
        return;

    // The scoreboard (Tab) is a full-screen replacement - it draws its
    // own letterbox frame and fits itself between the bars, so none of
    // the in-game overlays should render on top of it.
    if (bShowScoreBoard)
        return;

    LogHudStateOnce();

    if (class'MonsterFightClubGame'.default.bLetterbox)
        DrawLetterbox(C);
    DrawFightInfo(C);
    DrawChampionBanner(C);
    DrawFighterPreview(C);
    DrawBetList(C);
    DrawChatPortrait(C);
    DrawBetMenu(C);
    if (class'MonsterFightClubGame'.default.bFilmGrain)
        DrawFilmGrain(C);
}

// One-time diagnostic so we can confirm from the client log that the
// custom HUD/GRI/PRI are actually in use on the viewer's machine.
simulated function LogHudStateOnce()
{
    local string GS, PS;

    if (bHudStateLogged)
        return;
    bHudStateLogged = true;

    if (PlayerOwner.GameReplicationInfo != None)
        GS = string(PlayerOwner.GameReplicationInfo.Class);
    else
        GS = "None";
    if (PlayerOwner.PlayerReplicationInfo != None)
        PS = string(PlayerOwner.PlayerReplicationInfo.Class);
    else
        PS = "None";

    log("MFC HUD active: GRI=" $ GS $ " PRI=" $ PS $ " HUD=" $ string(Class));
}

//------------------------------------------------------------------------------
// Cinematic frame
//------------------------------------------------------------------------------

simulated function DrawLetterbox(Canvas C)
{
    local float H;
    local float XL, YL;
    local MonsterFightClubGRI GRI;

    H = 0.055 * C.ClipY;

    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(0, 0, 0, 255);
    C.SetPos(0, 0);
    C.DrawTile(Texture'Engine.BlackTexture', C.ClipX, H, 0, 0, 4, 4);
    C.SetPos(0, C.ClipY - H);
    C.DrawTile(Texture'Engine.BlackTexture', C.ClipX, H, 0, 0, 4, 4);

    // station title
    C.Font = GetMediumFontFor(C);
    C.StrLen("MONSTER FIGHT CLUB", XL, YL);
    C.SetDrawColor(255, 200, 40, 255);
    C.SetPos(10, (H - YL) * 0.5);
    C.DrawText("MONSTER FIGHT CLUB");

    // LIVE dot + label
    C.SetDrawColor(255, 40, 40, 255);
    C.SetPos(14, H + 8);
    C.DrawTile(Texture'Engine.WhiteTexture', 7, 7, 0, 0, 2, 2);
    C.Font = GetConsoleFont(C);
    C.SetPos(24, H + 4);
    C.DrawText("LIVE");

    // match clock - the STOCK RemainingTime (the same clock the stock
    // gametypes use). The stock MatchInProgress.Timer decrements it and
    // ends the show at zero, so this display always matches the end.
    GRI = MonsterFightClubGRI(PlayerOwner.GameReplicationInfo);
    if (GRI != None)
    {
        C.Font = GetMediumFontFor(C);
        C.StrLen("SHOW ENDS " $ FormatTime(GRI.RemainingTime), XL, YL);
        C.SetDrawColor(255, 255, 255, 255);
        C.SetPos(C.ClipX - XL - 12, (H - YL) * 0.5);
        C.DrawText("SHOW ENDS " $ FormatTime(GRI.RemainingTime));
    }
}

simulated function string FormatTime(int Seconds)
{
    local int M, S;
    M = Seconds / 60;
    S = Seconds - M * 60;
    if (S < 10)
        return string(M) $ ":0" $ string(S);
    return string(M) $ ":" $ string(S);
}

//------------------------------------------------------------------------------
// Fight information panel
//------------------------------------------------------------------------------

simulated function DrawFightInfo(Canvas C)
{
    local MonsterFightClubPlayerController MPC;
    local MonsterFightClubGRI G;
    local MonsterFightClubPRI MPRI;
    local float BW, BH, Y, XL, YL;
    local string NameA, NameB, S;

    MPC = MonsterFightClubPlayerController(PlayerOwner);
    G = MonsterFightClubGRI(PlayerOwner.GameReplicationInfo);
    if (G == None)
        return;

    // Prefer the server-pushed names (always fresh via reliable RPC),
    // falling back to the GRI before the first state arrives.
    NameA = G.FighterAName;
    NameB = G.FighterBName;
    if (MPC != None && MPC.bBetStateReceived)
    {
        if (MPC.ClientFighterAName != "")
            NameA = MPC.ClientFighterAName;
        if (MPC.ClientFighterBName != "")
            NameB = MPC.ClientFighterBName;
    }

    // round line
    if (NameA != "")
    {
        C.Font = GetMediumFontFor(C);
        C.SetDrawColor(255, 220, 120, 255);
        S = "ROUND " $ Min(G.RoundNumber, G.RoundsTotal) $ " OF " $ G.RoundsTotal $ "  -  "
            $ Caps(NameA) $ " VS " $ Caps(NameB);
        C.StrLen(S, XL, YL);
        C.SetPos((C.ClipX - XL) * 0.5, 0.74 * C.ClipY);
        C.DrawText(S);
    }

    // phase status line
    C.Font = GetConsoleFont(C);
    C.SetDrawColor(255, 255, 255, 255);
    if (G.bBettingOpen)
        S = "BET NOW: E = menu  |  /bet <amount> [1|2]";
    else if (G.Phase == 2)
        S = "FIGHT!";
    else if (G.Phase == 3)
        S = "ROUND OVER";
    else if (G.Phase == 4)
        S = "MATCHUP OVER";
    else
        S = "";
    if (S != "")
    {
        C.StrLen(S, XL, YL);
        C.SetPos((C.ClipX - XL) * 0.5, 0.79 * C.ClipY);
        C.DrawText(S);
    }

    if (NameA == "")
        return;

    // health bars - kept above the bottom letterbox, cleanly spaced from
    // the status line so nothing overlaps
    BW = 0.26 * C.ClipX;
    BH = 0.026 * C.ClipY;
    Y = 0.88 * C.ClipY;

    DrawHealthBar(C, NameA, G.FighterAHealth, G.FighterAMaxHealth,
                  C.ClipX * 0.5 - BW - 40, Y, BW, BH, 1);
    DrawHealthBar(C, NameB, G.FighterBHealth, G.FighterBMaxHealth,
                  C.ClipX * 0.5 + 40, Y, BW, BH, 2);

    // VS
    C.Font = GetFontSizeIndex(C, -2);
    C.SetDrawColor(255, 255, 255, 255);
    C.StrLen("VS", XL, YL);
    C.SetPos(C.ClipX * 0.5 - XL * 0.5, Y + (BH - YL) * 0.5);
    C.DrawText("VS");

    // bankroll / bet status
    MPRI = MonsterFightClubPRI(PlayerOwner.PlayerReplicationInfo);
    if (MPRI != None)
    {
        C.Font = GetConsoleFont(C);
        C.SetDrawColor(200, 255, 160, 255);
        S = "Bankroll: $" $ MPRI.Money;
        if (MPRI.CurrentBet > 0)
            S = S $ "   |   Bet: $" $ MPRI.CurrentBet $ " on " $ GetFighterNameFor(G, MPRI.BetFighter);
        C.StrLen(S, XL, YL);
        C.SetPos((C.ClipX - XL) * 0.5, Y + BH + 6);
        C.DrawText(S);
    }
}

simulated function string GetFighterNameFor(MonsterFightClubGRI G, int Fighter)
{
    if (Fighter == 2)
        return G.FighterBName;
    return G.FighterAName;
}

simulated function DrawHealthBar(Canvas C, string Name, int Health, int MaxHealth,
                                 float X, float Y, float W, float H, int Fighter)
{
    local float Pct, XL, YL;
    local Color BarColor;
    local string S;

    // background
    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(0, 0, 0, 170);
    C.SetPos(X, Y);
    C.DrawTile(Texture'Engine.BlackTexture', W, H, 0, 0, 4, 4);

    // fill
    Pct = 0;
    if (MaxHealth > 0)
        Pct = float(Health) / float(MaxHealth);
    Pct = FClamp(Pct, 0, 1);

    if (Fighter == 1)
        BarColor = class'HUD'.default.RedColor;
    else
        BarColor = class'HUD'.default.BlueColor;
    C.SetDrawColor(BarColor.R, BarColor.G, BarColor.B, 220);
    C.SetPos(X, Y);
    if (Pct > 0.01)
        C.DrawTile(Texture'Engine.WhiteTexture', W * Pct, H, 0, 0, 2, 2);

    // name
    C.Font = GetMediumFontFor(C);
    C.SetDrawColor(255, 255, 255, 255);
    C.SetPos(X, Y - 0.022 * C.ClipY);
    C.DrawText(Caps(Name));

    // hit points
    C.Font = GetConsoleFont(C);
    C.SetDrawColor(255, 255, 255, 255);
    S = Health $ "/" $ MaxHealth;
    C.StrLen(S, XL, YL);
    C.SetPos(X + W - XL - 4, Y + (H - YL) * 0.5);
    C.DrawText(S);
}

//------------------------------------------------------------------------------
// Pre-fight monster preview - a TV "VS" card during the betting window:
// each fighter rendered as a real 3D spinning model (via a local preview
// actor + Canvas.DrawActorClipped, same technique as the stock character
// select menus), plus name and stats (health, speed, jump, melee/ranged).
//------------------------------------------------------------------------------

simulated function DrawFighterPreview(Canvas C)
{
    local MonsterFightClubGRI G;
    local class<Monster> CA, CB;
    local float Y, W, H, XL, YL;

    G = MonsterFightClubGRI(PlayerOwner.GameReplicationInfo);
    if (G == None || G.Phase != 1)   // PHASE_BETTING only
        return;
    if (G.FighterAClassName == "" || G.FighterBClassName == "")
        return;

    CA = class<Monster>(DynamicLoadObject(G.FighterAClassName, class'Class'));
    CB = class<Monster>(DynamicLoadObject(G.FighterBClassName, class'Class'));
    if (CA == None || CB == None)
        return;

    // top band, clear of the fight info / betting menu below
    W = C.ClipX * 0.28;
    H = C.ClipY * 0.30;
    Y = C.ClipY * 0.08;

    DrawPreviewPanel(C, CA, G.FighterAName, C.ClipX * 0.10, Y, W, H, true);

    // VS badge in the middle
    C.Font = GetFontSizeIndex(C, 3);
    C.SetDrawColor(255, 255, 255, 255);
    C.StrLen("VS", XL, YL);
    C.SetPos((C.ClipX - XL) * 0.5, Y + H * 0.30);
    C.DrawText("VS");

    DrawPreviewPanel(C, CB, G.FighterBName, C.ClipX * 0.62, Y, W, H, false);
}

simulated function DrawPreviewPanel(Canvas C, class<Monster> MClass, string MName,
                                    float X, float Y, float W, float H, bool bIsA)
{
    local MonsterFightClubPreviewActor PA;
    local MonsterFightClubGRI G;
    local MonsterFightClubPlayerController MPC;
    local vector CamPos;
    local rotator CamRot, PreviewRot;
    local vector XAxis, YAxis, ZAxis;
    local float oOrgX, oOrgY, oClipX, oClipY;
    local float XL, YL, TargetH, PreviewZoom;
    local string S;

    // backdrop
    C.SetDrawColor(0, 0, 0, 190);
    C.SetPos(X, Y);
    C.DrawTile(Texture'Engine.WhiteSquareTexture', W, H, 0, 0, 2, 2);

    // thin TV-style border
    C.SetDrawColor(255, 255, 255, 160);
    C.SetPos(X, Y);            C.DrawTile(Texture'Engine.WhiteSquareTexture', W, 2, 0, 0, 2, 2);
    C.SetPos(X, Y + H - 2);    C.DrawTile(Texture'Engine.WhiteSquareTexture', W, 2, 0, 0, 2, 2);
    C.SetPos(X, Y);            C.DrawTile(Texture'Engine.WhiteSquareTexture', 2, H, 0, 0, 2, 2);
    C.SetPos(X + W - 2, Y);    C.DrawTile(Texture'Engine.WhiteSquareTexture', 2, H, 0, 0, 2, 2);

    // 3D model area (top ~55% of the panel). SKELETAL meshes render the 3D
    // spinning model; sprites render as billboards; vertex meshes (U1/Doom
    // DoomPawns) don't render reliably on this client, so they show the
    // "Preview Unavailable" text instead.
    PA = GetPreviewActor(bIsA, MClass);
    if (PA != None && (PA.DrawType == DT_Mesh
        || (PA.DrawType == DT_StaticMesh && PA.StaticMesh != None)))
    {
        // Park the preview actor dead ahead of THIS player's camera, then
        // render it with DrawActorClipped - the same path InvasionPro uses,
        // which renders U1 vertex-mesh monsters fine. The model's base
        // orientation follows the camera (roll zeroed) so it stays face-on
        // in the card; the turntable spin is added to the yaw.
        C.GetCameraLocation(CamPos, CamRot);
        GetAxes(CamRot, XAxis, YAxis, ZAxis);

        const PreviewDist = 292.0;   // InvasionPro's proven zoom for U1 monsters
        const PreviewFOV = 55.0;
        // Mouse-wheel zoom: the card's base fit is scaled by the player's
        // PreviewZoom (set in the PlayerController). The target world
        // height scales with it, so the on-screen size follows the zoom
        // cleanly and the model stays centered in the card.
        MPC = MonsterFightClubPlayerController(PlayerOwner);
        PreviewZoom = 1.0;
        if (MPC != None)
            PreviewZoom = MPC.PreviewZoom;
        // Fill ~85% of the model area: project the target pixel height
        // back through the same FOV/distance the render uses. (The old 55%
        // factor shrank U1 monsters to a speck - they looked invisible.)
        TargetH = 0.85 * (H * 0.55) * PreviewZoom * 2.0 * Tan(PreviewFOV * 0.5 * Pi / 180.0)
                  * PreviewDist / Max(1.0, C.ClipY);
        PA.FitToCard(TargetH);
        // The actor's base (feet) projects to the clip center; drop it by
        // half the model's world height so the model is vertically centered
        // in the model area (between the top border and the stats text).
        PA.SetLocation(CamPos + XAxis * PreviewDist - ZAxis * (TargetH * 0.5));

        // Free 3D object: only the turntable spin rotates the model, so
        // orbiting the free camera shows it from different angles.
        PreviewRot.Pitch = 0;
        PreviewRot.Yaw = int(PA.SpinYaw) & 65535;
        PreviewRot.Roll = 0;
        PA.SetRotation(PreviewRot);

        oOrgX = C.OrgX;  oOrgY = C.OrgY;  oClipX = C.ClipX;  oClipY = C.ClipY;
        C.OrgX = X;      C.OrgY = Y;      C.ClipX = W;      C.ClipY = H * 0.55;
        C.DrawActorClipped(PA, false, X, Y, W, H * 0.55, true, PreviewFOV);
        C.OrgX = oOrgX;  C.OrgY = oOrgY;  C.ClipX = oClipX; C.ClipY = oClipY;
    }
    else if (PA != None && PA.DrawType == DT_Sprite)
    {
        // Sprite billboards (DoomPawns2k4) don't render through
        // DrawActorClipped on this client - draw the billboard texture
        // directly into the model area instead.
        DrawSpritePreview(C, PA, X, Y, W, H);
    }
    else
    {
        // Can't render this draw type - show a placeholder.
        C.Font = GetFontSizeIndex(C, 0);
        C.SetDrawColor(180, 180, 180, 255);
        S = "Preview Unavailable";
        C.StrLen(S, XL, YL);
        C.SetPos(X + (W - XL) * 0.5, Y + (H * 0.55 - YL) * 0.5);
        C.DrawText(S);
    }

    // wheel-zoom indicator (only shown when zoomed away from the default)
    if (PreviewZoom != 1.0)
    {
        C.Font = GetFontSizeIndex(C, -2);
        C.SetDrawColor(255, 255, 255, 200);
        S = "ZOOM x" $ (int(PreviewZoom * 10) / 10.0);
        C.StrLen(S, XL, YL);
        C.SetPos(X + W - XL - 6, Y + 4);
        C.DrawText(S);
    }

    // name
    C.Font = GetFontSizeIndex(C, 1);
    C.SetDrawColor(255, 220, 80, 255);
    C.StrLen(MName, XL, YL);
    C.SetPos(X + (W - XL) * 0.5, Y + H * 0.57);
    C.DrawText(MName);

    // stats - show the fighter's REAL spawn health. Packs like Dinotopia
    // override health from their own ini files; the server probes the real
    // value and publishes it in the GRI at betting time.
    G = MonsterFightClubGRI(PlayerOwner.GameReplicationInfo);
    if (bIsA && G != None && G.FighterAMaxHealth > 0)
        S = "HP " $ G.FighterAMaxHealth;
    else if (!bIsA && G != None && G.FighterBMaxHealth > 0)
        S = "HP " $ G.FighterBMaxHealth;
    else
        S = "HP " $ MClass.default.Health;
    C.Font = GetFontSizeIndex(C, -1);
    C.SetDrawColor(220, 220, 220, 255);
    C.StrLen(S, XL, YL);
    C.SetPos(X + (W - XL) * 0.5, Y + H * 0.57 + YL);
    C.DrawText(S);

    if (MClass.default.bCanFly)
        S = "SPEED " $ int(MClass.default.AirSpeed);
    else
        S = "SPEED " $ int(MClass.default.GroundSpeed);
    C.StrLen(S, XL, YL);
    C.SetPos(X + (W - XL) * 0.5, Y + H * 0.57 + 2 * YL);
    C.DrawText(S);

    S = "JUMP " $ int(MClass.default.JumpZ);
    C.StrLen(S, XL, YL);
    C.SetPos(X + (W - XL) * 0.5, Y + H * 0.57 + 3 * YL);
    C.DrawText(S);

    // Fighting style: a monster can be melee, ranged, or BOTH. Most packs
    // (U1Pawns, Dinotopia, Doom, KF...) never declare AmmunitionClass or
    // bMeleeFighter, so we ask the class's own virtuals too and default
    // undeclared monsters to Melee (the dominant style in the roster).
    if (HasMeleeAttack(MClass) && HasRangedAttackStyle(MClass))
        S = "Melee, Ranged";
    else if (HasMeleeAttack(MClass))
        S = "Melee";
    else if (HasRangedAttackStyle(MClass))
        S = "Ranged";
    else
        S = "Melee";
    C.SetDrawColor(140, 220, 255, 255);
    C.StrLen(S, XL, YL);
    C.SetPos(X + (W - XL) * 0.5, Y + H * 0.57 + 4 * YL);
    C.DrawText(S);
}

// Does this monster class declare a melee attack? Only the bMeleeFighter
// flag is reliable at class-default level (the PreferMelee virtual is
// runtime-stateful and can't be queried on the default object).
simulated function bool HasMeleeAttack(class<Monster> M)
{
    if (M == None)
        return false;
    return M.default.bMeleeFighter;
}

// Does this monster class have a ranged attack? A declared AmmunitionClass
// with a real projectile or hitscan weapon. (The HasRangedAttack virtual
// can't be queried at class-default level - UnrealScript only resolves
// properties through "Class.default", and spawning a live instance just to
// ask is overkill for a card label.)
simulated function bool HasRangedAttackStyle(class<Monster> M)
{
    local class<Ammunition> A;

    if (M == None)
        return false;
    A = M.default.AmmunitionClass;
    if (A != None)
        return (A.default.ProjectileClass != None) || A.default.bInstantHit;
    return false;
}

// Draw a DT_Sprite billboard texture into the model area. Sprites don't
// render through DrawActorClipped on the 64-bit client (same as vertex
// meshes), so the billboard is drawn as a plain 2D texture instead.
simulated function DrawSpritePreview(Canvas C, MonsterFightClubPreviewActor PA,
                                     float X, float Y, float W, float H)
{
    local Material Tex;
    local float TA, TB, DW, DH, MaxW, MaxH;

    if (PA == None)
        return;
    Tex = PA.Texture;
    if (Tex == None)
        Tex = Texture'Engine.WhiteSquareTexture';
    TA = Tex.MaterialUSize();
    TB = Tex.MaterialVSize();
    if (TA <= 0 || TB <= 0)
        return;

    // fit into the model area, preserving aspect ratio
    MaxW = W * 0.9;
    MaxH = H * 0.55 * 0.9;
    DW = MaxW;
    DH = DW * TB / TA;
    if (DH > MaxH)
    {
        DH = MaxH;
        DW = DH * TA / TB;
    }
    C.SetDrawColor(255, 255, 255, 255);
    C.SetPos(X + (W - DW) * 0.5, Y + (H * 0.55 - DH) * 0.5);
    C.DrawTile(Tex, DW, DH, 0, 0, TA, TB);
}

// Get (or lazily create) the local 3D preview actor for one fighter,
// rebuilding it if the matchup's monster class changed.
simulated function MonsterFightClubPreviewActor GetPreviewActor(bool bIsA, class<Monster> MClass)
{
    local MonsterFightClubPreviewActor PA;
    local string CName;

    CName = string(MClass);
    if (bIsA)
    {
        PA = PreviewActorA;
        if (PA != None && PreviewAClass == CName)
            return PA;
        if (PA == None)
            PA = PlayerOwner.Spawn(class'MonsterFightClubPreviewActor', PlayerOwner);
    }
    else
    {
        PA = PreviewActorB;
        if (PA != None && PreviewBClass == CName)
            return PA;
        if (PA == None)
            PA = PlayerOwner.Spawn(class'MonsterFightClubPreviewActor', PlayerOwner);
    }
    if (PA != None)
    {
        PA.SetupFor(MClass);
        if (bIsA)
        {
            PreviewActorA = PA;
            PreviewAClass = CName;
        }
        else
        {
            PreviewActorB = PA;
            PreviewBClass = CName;
        }
    }
    return PA;
}

//------------------------------------------------------------------------------
// Champion win-streak banner (gauntlet mode). Shows the standing champion
// and their consecutive-matchup win streak during betting and fights.
//------------------------------------------------------------------------------

simulated function DrawChampionBanner(Canvas C)
{
    local MonsterFightClubGRI G;
    local float XL, YL;
    local string S;

    G = MonsterFightClubGRI(PlayerOwner.GameReplicationInfo);
    if (G == None || G.ChampionName == "" || G.ChampionStreak <= 0)
        return;

    C.Font = GetFontSizeIndex(C, -1);
    C.SetDrawColor(255, 200, 40, 255);
    if (G.ChampionStreak == 1)
        S = "CHAMPION: " $ Caps(G.ChampionName);
    else
        S = "CHAMPION: " $ Caps(G.ChampionName) $ "  -  WIN STREAK " $ G.ChampionStreak;
    C.StrLen(S, XL, YL);
    C.SetPos((C.ClipX - XL) * 0.5, C.ClipY * 0.065);
    C.DrawText(S);
}

//------------------------------------------------------------------------------
// Bet list - everyone's current wager, shown on the right side of the
// screen (vertically centered) during the betting window.
//------------------------------------------------------------------------------

simulated function DrawBetList(Canvas C)
{
    local MonsterFightClubGRI G;
    local MonsterFightClubPRI MPRI;
    local GameReplicationInfo GRI;
    local string S;
    local float XL, YL, X, Y;
    local int i;
    local int Count;

    G = MonsterFightClubGRI(PlayerOwner.GameReplicationInfo);
    if (G == None || G.Phase != 1)   // betting only
        return;

    // Count how many bets are down first.
    GRI = PlayerOwner.GameReplicationInfo;
    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        MPRI = MonsterFightClubPRI(GRI.PRIArray[i]);
        if (MPRI != None && MPRI.CurrentBet > 0)
            Count++;
    }
    if (Count == 0)
        return;

    C.Font = GetFontSizeIndex(C, -2);
    C.SetDrawColor(0, 0, 0, 160);

    // Measure the rows so the panel fits its content.
    C.StrLen("CURRENT BETS", XL, YL);
    X = C.ClipX * 0.74;
    // Top-anchored: the panel starts at a fixed height and grows ONLY
    // downward as more bets come in - it can never creep up into the
    // fighter cards above (it was vertically centered before).
    Y = C.ClipY * 0.40;

    // Backdrop.
    C.SetPos(X - 8, Y - 6);
    C.DrawTile(Texture'Engine.BlackTexture', C.ClipX * 0.24 + 16, (Count + 1) * YL + 14, 0, 0, 4, 4);

    // Header.
    C.SetDrawColor(255, 220, 80, 255);
    C.StrLen("CURRENT BETS", XL, YL);
    C.SetPos(X, Y);
    C.DrawText("CURRENT BETS");
    Y += YL;

    // Each bettor.
    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        MPRI = MonsterFightClubPRI(GRI.PRIArray[i]);
        if (MPRI == None || MPRI.CurrentBet <= 0)
            continue;

        C.SetDrawColor(220, 220, 220, 255);
        S = MPRI.PlayerName $ "  $" $ MPRI.CurrentBet;
        if (MPRI.BetFighter == 2)
            S = S $ " on " $ G.FighterBName;
        else
            S = S $ " on " $ G.FighterAName;
        C.StrLen(S, XL, YL);
        C.SetPos(X, Y);
        C.DrawText(S);
        Y += YL;
    }
}

//------------------------------------------------------------------------------
// Film grain
//------------------------------------------------------------------------------

simulated function DrawFilmGrain(Canvas C)
{
    local int Alpha;

    Alpha = class'MonsterFightClubGame'.default.GrainAlpha;
    if (Alpha <= 0)
        return;

    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(255, 255, 255, Alpha);
    C.SetPos(0, 0);
    C.bNoSmooth = true;
    C.DrawTile(Material'XGameShaders.ModuNoise', C.ClipX, C.ClipY, Rand(512), Rand(512), 512, 512);
    C.bNoSmooth = false;
}

//------------------------------------------------------------------------------
// Bot portraits on chat messages
//------------------------------------------------------------------------------

simulated function Message(PlayerReplicationInfo PRI, coerce string Msg, name MsgType)
{
    Super.Message(PRI, Msg, MsgType);
    if (PRI != None && (MsgType == 'Say' || MsgType == 'TeamSay'))
    {
        ChatPortraitPRI = PRI;
        ChatPortraitTime = Level.TimeSeconds + 4;
        DisplayPortrait(PRI);
    }
}

simulated function DisplayPortrait(PlayerReplicationInfo PRI)
{
    local Material NewPortrait;

    if (PRI == None)
        return;

    NewPortrait = PRI.GetPortrait();
    if (NewPortrait == None)
        return;
    if (Portrait == None)
        PortraitX = 1;
    Portrait = NewPortrait;
    PortraitTime = Level.TimeSeconds + 3;
    PortraitPRI = PRI;
}

//------------------------------------------------------------------------------
// Chat portraits — drawn by us so they always show, even for pawn-less bots
//------------------------------------------------------------------------------

simulated function DrawChatPortrait(Canvas C)
{
    local Material P;
    local float PW, PH, XL, YL, X, Y;

    if (ChatPortraitPRI == None || ChatPortraitTime < Level.TimeSeconds)
        return;

    P = ChatPortraitPRI.GetPortrait();
    if (P == None)
        return;

    // left side of the screen, vertically centered. Portraits are
    // rectangular, so preserve the texture's true aspect ratio.
    PH = 0.10 * C.ClipY;
    PW = PH * P.MaterialUSize() / Max(1, P.MaterialVSize());
    if (PW > 0.16 * C.ClipX)
        PW = 0.16 * C.ClipX;
    X = 12;
    Y = (C.ClipY - PH) * 0.5;

    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(255, 255, 255, 255);
    C.SetPos(X, Y);
    C.DrawTile(P, PW, PH, 0, 0, P.MaterialUSize(), P.MaterialVSize());

    // name plate, vertically centered to the right of the portrait
    C.Font = GetMediumFontFor(C);
    C.SetDrawColor(255, 220, 120, 255);
    C.StrLen(ChatPortraitPRI.PlayerName, XL, YL);
    C.SetPos(X + PW + 8, Y + (PH - YL) * 0.5);
    C.DrawText(ChatPortraitPRI.PlayerName);
}

//------------------------------------------------------------------------------
// Interactive betting menu
//------------------------------------------------------------------------------

simulated function DrawBetMenu(Canvas C)
{
    local MonsterFightClubPlayerController MPC;
    local MonsterFightClubGRI G;
    local MonsterFightClubPRI MPRI;
    local float X, Y, W, H, XL, YL, RowH, Pad, TY, BoxW, Gap;
    local int ReadyNum, TotalNum;
    local bool bCanBet, bSelfReady;
    local string S;

    MPC = MonsterFightClubPlayerController(PlayerOwner);
    if (MPC == None || !MPC.bBetMenuOpen)
        return;

    G = MonsterFightClubGRI(PlayerOwner.GameReplicationInfo);
    MPRI = MonsterFightClubPRI(PlayerOwner.PlayerReplicationInfo);

    W = 0.46 * C.ClipX;
    H = 0.62 * C.ClipY;
    X = (C.ClipX - W) * 0.5;
    Y = (C.ClipY - H) * 0.5;
    Pad = 0.012 * C.ClipX;
    RowH = 0.042 * C.ClipY;
    TY = Y + 8;

    // panel + gold border
    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(0, 0, 0, 205);
    C.SetPos(X, Y);
    C.DrawTile(Texture'Engine.BlackTexture', W, H, 0, 0, 4, 4);
    C.SetDrawColor(255, 200, 40, 255);
    C.SetPos(X, Y);
    C.DrawTile(Texture'Engine.WhiteTexture', W, 2, 0, 0, 2, 2);
    C.SetPos(X, Y + H - 2);
    C.DrawTile(Texture'Engine.WhiteTexture', W, 2, 0, 0, 2, 2);
    C.SetPos(X, Y);
    C.DrawTile(Texture'Engine.WhiteTexture', 2, H, 0, 0, 2, 2);
    C.SetPos(X + W - 2, Y);
    C.DrawTile(Texture'Engine.WhiteTexture', 2, H, 0, 0, 2, 2);

    // title
    C.Font = GetMediumFontFor(C);
    C.SetDrawColor(255, 220, 120, 255);
    S = "BET ON THE FIGHT";
    C.StrLen(S, XL, YL);
    C.SetPos(X + (W - XL) * 0.5, TY);
    C.DrawText(S);
    TY += YL + 10;

    // ready status (bots included)
    GetReadyDisplay(ReadyNum, TotalNum);
    bSelfReady = (MPRI != None && MPRI.bReady);

    C.Font = GetConsoleFont(C);
    if (bSelfReady)
        C.SetDrawColor(140, 255, 140, 255);
    else
        C.SetDrawColor(255, 255, 255, 255);
    S = "READY " $ ReadyNum $ "/" $ TotalNum;
    if (bSelfReady)
        S = S $ "  -  YOU ARE READY";
    C.StrLen(S, XL, YL);
    C.SetPos(X + (W - XL) * 0.5, TY);
    C.DrawText(S);
    TY += YL + 10;

    bCanBet = false;
    if (MPC.bBetStateReceived)
        bCanBet = MPC.bBettingOpenClient;
    else if (G != None)
        bCanBet = G.bBettingOpen;

    // The menu can only be opened while betting is open (ToggleBetMenu
    // blocks it otherwise), so this branch is always the betting UI.
    // fighter rows
    DrawMenuRow(C, X + Pad, TY, W - 2 * Pad, RowH,
                "1   " $ Caps(GetMenuFighterName(MPC, G, 1)), MPC.BetMenuFighter == 1);
    TY += RowH + 6;
    DrawMenuRow(C, X + Pad, TY, W - 2 * Pad, RowH,
                "2   " $ Caps(GetMenuFighterName(MPC, G, 2)), MPC.BetMenuFighter == 2);
    TY += RowH + 10;

    // amount label
    C.Font = GetConsoleFont(C);
    C.SetDrawColor(255, 255, 255, 255);
    S = "AMOUNT (MOUSE WHEEL):";
    C.StrLen(S, XL, YL);
    C.SetPos(X + Pad, TY);
    C.DrawText(S);
    TY += YL + 6;

    // quick amount boxes - 3x3 grid: 1 5 10 / 20 50 100 / 500 1000 ALL-IN
    Gap = 6;
    BoxW = (W - 2 * Pad - 2 * Gap) / 3;
    DrawMenuRow(C, X + Pad, TY, BoxW, RowH, "$1", MPC.BetMenuPreset == 0);
    DrawMenuRow(C, X + Pad + (BoxW + Gap), TY, BoxW, RowH, "$5", MPC.BetMenuPreset == 1);
    DrawMenuRow(C, X + Pad + 2 * (BoxW + Gap), TY, BoxW, RowH, "$10", MPC.BetMenuPreset == 2);
    TY += RowH + 6;
    DrawMenuRow(C, X + Pad, TY, BoxW, RowH, "$20", MPC.BetMenuPreset == 3);
    DrawMenuRow(C, X + Pad + (BoxW + Gap), TY, BoxW, RowH, "$50", MPC.BetMenuPreset == 4);
    DrawMenuRow(C, X + Pad + 2 * (BoxW + Gap), TY, BoxW, RowH, "$100", MPC.BetMenuPreset == 5);
    TY += RowH + 6;
    DrawMenuRow(C, X + Pad, TY, BoxW, RowH, "$500", MPC.BetMenuPreset == 6);
    DrawMenuRow(C, X + Pad + (BoxW + Gap), TY, BoxW, RowH, "$1000", MPC.BetMenuPreset == 7);
    DrawMenuRow(C, X + Pad + 2 * (BoxW + Gap), TY, BoxW, RowH, "ALL-IN", MPC.BetMenuPreset == 8);
    TY += RowH + 6;

    // bankroll
    C.SetDrawColor(200, 255, 160, 255);
    if (MPRI != None)
        S = "BANKROLL: $" $ MPRI.Money;
    else
        S = "BANKROLL: -";
    C.StrLen(S, XL, YL);
    C.SetPos(X + (W - XL) * 0.5, TY);
    C.DrawText(S);
    TY += YL + 10;

    // single action button: place bet (auto-readies) + ready up
    if (bSelfReady)
        DrawMenuRow(C, X + Pad, TY, W - 2 * Pad, RowH, "PLACE BET + READY  (LMB)  -  YOU ARE READY", true);
    else
        DrawMenuRow(C, X + Pad, TY, W - 2 * Pad, RowH, "PLACE BET + READY  (LMB)", true);
    TY += RowH + 8;

    // instructions
    C.Font = GetFontSizeIndex(C, -2);
    C.SetDrawColor(255, 200, 40, 255);
    S = "INSTRUCTIONS";
    C.StrLen(S, XL, YL);
    C.SetPos(X + Pad, TY);
    C.DrawText(S);
    TY += YL + 2;

    C.SetDrawColor(200, 200, 200, 255);
    S = "E: Toggle Menu   |   1/2: Fighter Selection   |   Mouse Wheel: Amount";
    C.SetPos(X + Pad, TY);  C.DrawText(S);  TY += YL + 1;
    S = "Left Mouse Button: Place Bet + Ready Up";
    C.SetPos(X + Pad, TY);  C.DrawText(S);  TY += YL + 1;
    S = "Backslash: Toggles Between Spectator Cam & Action Cam (Experimental)";
    C.SetPos(X + Pad, TY);  C.DrawText(S);  TY += YL + 1;
    S = "/bet <amount> [1|2] in console for custom amounts";
    C.SetPos(X + Pad, TY);  C.DrawText(S);
}

simulated function GetReadyDisplay(out int ReadyNum, out int TotalNum)
{
    local int i;
    local MonsterFightClubPRI P;

    ReadyNum = 0;
    TotalNum = 0;
    if (PlayerOwner == None || PlayerOwner.GameReplicationInfo == None)
        return;
    for (i = 0; i < PlayerOwner.GameReplicationInfo.PRIArray.Length; i++)
    {
        P = MonsterFightClubPRI(PlayerOwner.GameReplicationInfo.PRIArray[i]);
        if (P == None)
            continue;
        TotalNum++;
        if (P.bReady)
            ReadyNum++;
    }
}

simulated function string GetMenuFighterName(MonsterFightClubPlayerController MPC, MonsterFightClubGRI G, int Fighter)
{
    if (MPC != None && MPC.bBetStateReceived && MPC.ClientFighterAName != "")
    {
        if (Fighter == 2)
            return MPC.ClientFighterBName;
        return MPC.ClientFighterAName;
    }
    if (G != None)
    {
        if (Fighter == 2)
            return G.FighterBName;
        return G.FighterAName;
    }
    if (Fighter == 2)
        return "FIGHTER B";
    return "FIGHTER A";
}

simulated function DrawMenuRow(Canvas C, float X, float Y, float W, float H,
                               string Text, bool bSelected)
{
    local float XL, YL;
    local Color BorderC, FillC, TextC;

    if (bSelected)
    {
        BorderC = class'HUD'.default.GoldColor;
        FillC.R = 60; FillC.G = 60; FillC.B = 20;
        TextC = class'HUD'.default.GoldColor;
    }
    else
    {
        BorderC.R = 120; BorderC.G = 120; BorderC.B = 120;
        FillC.R = 20; FillC.G = 20; FillC.B = 20;
        TextC.R = 255; TextC.G = 255; TextC.B = 255;
    }
    FillC.A = 220;
    BorderC.A = 255;
    TextC.A = 255;

    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(FillC.R, FillC.G, FillC.B, FillC.A);
    C.SetPos(X, Y);
    C.DrawTile(Texture'Engine.BlackTexture', W, H, 0, 0, 4, 4);
    C.SetDrawColor(BorderC.R, BorderC.G, BorderC.B, BorderC.A);
    C.SetPos(X, Y);
    C.DrawTile(Texture'Engine.WhiteTexture', W, 2, 0, 0, 2, 2);
    C.SetPos(X, Y + H - 2);
    C.DrawTile(Texture'Engine.WhiteTexture', W, 2, 0, 0, 2, 2);
    C.SetPos(X, Y);
    C.DrawTile(Texture'Engine.WhiteTexture', 2, H, 0, 0, 2, 2);
    C.SetPos(X + W - 2, Y);
    C.DrawTile(Texture'Engine.WhiteTexture', 2, H, 0, 0, 2, 2);

    C.Font = GetMediumFontFor(C);
    C.SetDrawColor(TextC.R, TextC.G, TextC.B, TextC.A);
    C.StrLen(Text, XL, YL);
    C.SetPos(X + 10, Y + (H - YL) * 0.5);
    C.DrawText(Text);
}

defaultproperties
{
     bShowPortrait=True
}
