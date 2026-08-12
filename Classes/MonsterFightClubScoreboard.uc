//=============================================================================
// MonsterFightClubScoreboard
// Bankroll replaces the score column, winning bets replace deaths.
// (Money is mirrored into Score and BetWins into Deaths by the GameInfo.)
//=============================================================================
class MonsterFightClubScoreboard extends ScoreBoardDeathMatch;

var float ScoreboardBarH;   // letterbox bar height (0 when letterbox is off)

simulated function Init()
{
    // Base PostBeginPlay already called InitGRI(); just ensure a valid link
    if (GRI == None)
        GRI = Level.GRI;
    Super.Init();
}

// The scoreboard renders as a full-screen replacement, so when letterbox
// is enabled we draw the same black bars as the HUD frame and shrink the
// drawing canvas to the region between them. NOTE: we must NOT shift the
// board with Canvas.OrgY - the stock row boxes are drawn with
// DrawTileStretched, which ignores OrgX/OrgY on this engine, so the boxes
// would detach from the text. Instead every element of the board derives
// its Y from HeaderOffsetY, so we add the bar height there (see
// UpdateScoreBoard below) and everything moves together.
simulated event DrawScoreboard(Canvas C)
{
    local float XL, YL;

    ScoreboardBarH = 0;
    if (class'MonsterFightClubGame'.default.bLetterbox)
    {
        ScoreboardBarH = 0.055 * C.ClipY;

        // top and bottom bars - full-screen coords, before shrinking
        C.Style = ERenderStyle.STY_Alpha;
        C.SetDrawColor(0, 0, 0, 255);
        C.SetPos(0, 0);
        C.DrawTile(Texture'Engine.BlackTexture', C.ClipX, ScoreboardBarH, 0, 0, 4, 4);
        C.SetPos(0, C.ClipY - ScoreboardBarH);
        C.DrawTile(Texture'Engine.BlackTexture', C.ClipX, ScoreboardBarH, 0, 0, 4, 4);

        // station title in the top bar, matching the HUD frame
        C.Font = HUDClass.static.GetMediumFontFor(C);
        C.StrLen("MONSTER FIGHT CLUB", XL, YL);
        C.SetDrawColor(255, 200, 40, 255);
        C.SetPos(10, (ScoreboardBarH - YL) * 0.5);
        C.DrawText("MONSTER FIGHT CLUB");

        // the board draws into the region between the bars
        C.ClipY -= 2 * ScoreboardBarH;
    }
    Super.DrawScoreboard(C);
}

// Title and score-info line, placed inside the letterboxed area instead of
// at the stock screen edges (which would sit behind the bars).
simulated function DrawTitle(Canvas Canvas, float HeaderOffsetY, float PlayerAreaY, float PlayerBoxSizeY)
{
    local string TitleString, ScoreInfoString;
    local float TitleXL, ScoreInfoXL, YL;

    if ( Canvas.ClipX < 512 )
        return;

    TitleString = GetTitleString();
    ScoreInfoString = GetDefaultScoreInfoString();

    Canvas.StrLen(TitleString, TitleXL, YL);
    Canvas.DrawColor = HUDClass.default.GoldColor;
    Canvas.SetPos(0.5*(Canvas.ClipX-TitleXL), ScoreboardBarH + 0.5 * YL);
    Canvas.DrawText(TitleString,true);

    if ( ScoreInfoString != "" )
    {
        Canvas.StrLen(ScoreInfoString, ScoreInfoXL, YL);
        Canvas.DrawColor = HUDClass.default.WhiteColor;
        Canvas.SetPos(0.5*(Canvas.ClipX-ScoreInfoXL), Canvas.ClipY - 1.5 * YL + ScoreboardBarH);
        Canvas.DrawText(ScoreInfoString,true);
    }
}

// Full board layout, copied from the stock ScoreBoardDeathMatch and adapted:
//  - HeaderOffsetY is offset by the letterbox bar height, which shifts the
//    row boxes, names, scores, headers and owner line all together.
//  - No net/ping info and no match ID (irrelevant for the show).
//  - GRI guard so the board always renders even if Init never linked it.
simulated function UpdateScoreBoard(Canvas Canvas)
{
    local PlayerReplicationInfo PRI, OwnerPRI;
    local int i, FontReduction, OwnerPos, PlayerCount, HeaderOffsetY, HeadFoot, MessageFoot, PlayerBoxSizeY, BoxSpaceY, NameXPos, BoxTextOffsetY, OwnerOffset, ScoreXPos, DeathsXPos, BoxXPos, TitleYPos, BoxWidth;
    local float XL, YL, MaxScaling;
    local float deathsXL, scoreXL, MaxNamePos, LongestNameLength;
    local string playername[MAXPLAYERS], LongestName;
    local font ReducedFont;

    if (GRI == None)
        GRI = Level.GRI;
    if (GRI == None)
        return;

    OwnerPRI = PlayerController(Owner).PlayerReplicationInfo;
    for (i=0; i<GRI.PRIArray.Length; i++)
    {
        PRI = GRI.PRIArray[i];
        if ( !PRI.bOnlySpectator && (!PRI.bIsSpectator || PRI.bWaitingPlayer) )
        {
            if ( PRI == OwnerPRI )
                OwnerOffset = i;
            PlayerCount++;
        }
    }
    PlayerCount = Min(PlayerCount,MAXPLAYERS);

    // Select best font size and box size to fit as many players as possible
    // (same ladder as the stock board, driven by the shrunk ClipY).
    Canvas.Font = HUDClass.static.GetMediumFontFor(Canvas);
    Canvas.StrLen("Test", XL, YL);
    BoxSpaceY = 0.25 * YL;
    PlayerBoxSizeY = 1.5 * YL;
    HeadFoot = 5*YL;
    MessageFoot = 1.5 * HeadFoot;
    if ( PlayerCount > (Canvas.ClipY - 1.5 * HeadFoot)/(PlayerBoxSizeY + BoxSpaceY) )
    {
        BoxSpaceY = 0.125 * YL;
        PlayerBoxSizeY = 1.25 * YL;
        if ( PlayerCount > (Canvas.ClipY - 1.5 * HeadFoot)/(PlayerBoxSizeY + BoxSpaceY) )
        {
            PlayerBoxSizeY = 1.125 * YL;
            if ( PlayerCount > (Canvas.ClipY - 1.5 * HeadFoot)/(PlayerBoxSizeY + BoxSpaceY) )
            {
                FontReduction++;
                Canvas.Font = GetSmallerFontFor(Canvas,FontReduction);
                Canvas.StrLen("Test", XL, YL);
                BoxSpaceY = 0.125 * YL;
                PlayerBoxSizeY = 1.125 * YL;
                HeadFoot = 5*YL;
                if ( PlayerCount > (Canvas.ClipY - HeadFoot)/(PlayerBoxSizeY + BoxSpaceY) )
                {
                    FontReduction++;
                    Canvas.Font = GetSmallerFontFor(Canvas,FontReduction);
                    Canvas.StrLen("Test", XL, YL);
                    BoxSpaceY = 0.125 * YL;
                    PlayerBoxSizeY = 1.125 * YL;
                    HeadFoot = 5*YL;
                    if ( (Canvas.ClipY >= 768) && (PlayerCount > (Canvas.ClipY - HeadFoot)/(PlayerBoxSizeY + BoxSpaceY)) )
                    {
                        FontReduction++;
                        Canvas.Font = GetSmallerFontFor(Canvas,FontReduction);
                        Canvas.StrLen("Test", XL, YL);
                        BoxSpaceY = 0.125 * YL;
                        PlayerBoxSizeY = 1.125 * YL;
                        HeadFoot = 5*YL;
                    }
                }
            }
        }
    }
    if ( Canvas.ClipX < 512 )
        PlayerCount = Min(PlayerCount, 1+(Canvas.ClipY - HeadFoot)/(PlayerBoxSizeY + BoxSpaceY) );
    else
        PlayerCount = Min(PlayerCount, (Canvas.ClipY - HeadFoot)/(PlayerBoxSizeY + BoxSpaceY) );
    if ( OwnerOffset >= PlayerCount )
        PlayerCount -= 1;

    if ( FontReduction > 2 )
        MaxScaling = 3;
    else
        MaxScaling = 2.125;
    PlayerBoxSizeY = FClamp((1+(Canvas.ClipY - 0.67 * MessageFoot))/PlayerCount - BoxSpaceY, PlayerBoxSizeY, MaxScaling * YL);

    bDisplayMessages = (PlayerCount <= (Canvas.ClipY - MessageFoot)/(PlayerBoxSizeY + BoxSpaceY));
    // The whole board is pushed below the top letterbox bar. Every element
    // below derives its Y from HeaderOffsetY (rows, boxes, headers) or from
    // BoxTextOffsetY (which is HeaderOffsetY + half a box), so this single
    // offset moves everything - and keeps boxes aligned with their text.
    HeaderOffsetY = 3 * YL + ScoreboardBarH;
    BoxWidth = 0.9375 * Canvas.ClipX;
    BoxXPos = 0.5 * (Canvas.ClipX - BoxWidth);
    BoxWidth = Canvas.ClipX - 2*BoxXPos;
    NameXPos = BoxXPos + 0.0625 * BoxWidth;
    ScoreXPos = BoxXPos + 0.5 * BoxWidth;
    DeathsXPos = BoxXPos + 0.6875 * BoxWidth;

    // draw background boxes
    Canvas.Style = ERenderStyle.STY_Alpha;
    Canvas.DrawColor = HUDClass.default.WhiteColor * 0.5;
    for ( i=0; i<PlayerCount; i++ )
    {
        Canvas.SetPos(BoxXPos, HeaderOffsetY + (PlayerBoxSizeY + BoxSpaceY)*i);
        Canvas.DrawTileStretched( BoxMaterial, BoxWidth, PlayerBoxSizeY);
    }
    Canvas.Style = ERenderStyle.STY_Translucent;

    // title + score info
    Canvas.Style = ERenderStyle.STY_Normal;
    DrawTitle(Canvas, HeaderOffsetY, (PlayerCount+1)*(PlayerBoxSizeY + BoxSpaceY), PlayerBoxSizeY);

    // headers
    TitleYPos = HeaderOffsetY - 1.25*YL;
    Canvas.StrLen(PointsText, ScoreXL, YL);
    Canvas.StrLen(DeathsText, DeathsXL, YL);

    Canvas.DrawColor = HUDClass.default.WhiteColor;
    Canvas.SetPos(NameXPos, TitleYPos);
    Canvas.DrawText(PlayerText,true);
    Canvas.SetPos(ScoreXPos - 0.5*ScoreXL, TitleYPos);
    Canvas.DrawText(PointsText,true);
    Canvas.SetPos(DeathsXPos - 0.5*DeathsXL, TitleYPos);
    Canvas.DrawText(DeathsText,true);

    if ( PlayerCount <= 0 )
        return;

    // names - truncate anything wider than the name column
    MaxNamePos = 0.9 * (ScoreXPos - NameXPos);
    LongestNameLength = 0;
    for ( i=0; i<PlayerCount; i++ )
    {
        playername[i] = GRI.PRIArray[i].PlayerName;
        Canvas.StrLen(playername[i], XL, YL);
        if ( XL > MaxNamePos )
        {
            while ( XL > MaxNamePos && Len(playername[i]) > 1 )
            {
                playername[i] = Left(playername[i], Len(playername[i])-1);
                Canvas.StrLen(playername[i], XL, YL);
            }
            LongestName = playername[i];
            LongestNameLength = XL;
        }
    }
    if ( OwnerOffset >= PlayerCount )
    {
        playername[OwnerOffset] = GRI.PRIArray[OwnerOffset].PlayerName;
        Canvas.StrLen(playername[OwnerOffset], XL, YL);
        if ( XL > MaxNamePos )
        {
            while ( XL > MaxNamePos && Len(playername[OwnerOffset]) > 1 )
            {
                playername[OwnerOffset] = Left(playername[OwnerOffset], Len(playername[OwnerOffset])-1);
                Canvas.StrLen(playername[OwnerOffset], XL, YL);
            }
            LongestName = playername[OwnerOffset];
            LongestNameLength = XL;
        }
    }

    if ( LongestNameLength > 0 )
    {
        Canvas.Font = GetSmallerFontFor(Canvas,FontReduction+1);
        Canvas.StrLen(LongestName, XL, YL);
        if ( XL > MaxNamePos )
        {
            Canvas.Font = GetSmallerFontFor(Canvas,FontReduction+2);
            Canvas.StrLen(LongestName, XL, YL);
            if ( XL > MaxNamePos )
                Canvas.Font = GetSmallerFontFor(Canvas,FontReduction+3);
        }
        ReducedFont = Canvas.Font;
    }

    BoxTextOffsetY = HeaderOffsetY + 0.5 * (PlayerBoxSizeY - YL);

    // names
    Canvas.Style = ERenderStyle.STY_Normal;
    Canvas.DrawColor = HUDClass.default.WhiteColor;
    for ( i=0; i<PlayerCount; i++ )
        if ( i != OwnerOffset )
        {
            Canvas.SetPos(NameXPos, (PlayerBoxSizeY + BoxSpaceY)*i + BoxTextOffsetY);
            Canvas.DrawText(playername[i],true);
        }
    if ( LongestNameLength > 0 )
        Canvas.Font = GetSmallerFontFor(Canvas,FontReduction);

    // bankroll (score column)
    Canvas.DrawColor = HUDClass.default.WhiteColor;
    for ( i=0; i<PlayerCount; i++ )
        if ( i != OwnerOffset )
        {
            Canvas.SetPos(ScoreXPos, (PlayerBoxSizeY + BoxSpaceY)*i + BoxTextOffsetY);
            if ( GRI.PRIArray[i].bOutOfLives )
                Canvas.DrawText(OutText,true);
            else
                Canvas.DrawText(int(GRI.PRIArray[i].Score),true);
        }

    // bets won (deaths column)
    Canvas.DrawColor = HUDClass.default.WhiteColor;
    for ( i=0; i<PlayerCount; i++ )
        if ( i != OwnerOffset )
        {
            Canvas.SetPos(DeathsXPos, (PlayerBoxSizeY + BoxSpaceY)*i + BoxTextOffsetY);
            Canvas.DrawText(int(GRI.PRIArray[i].Deaths),true);
        }

    // owner line
    if ( OwnerOffset >= PlayerCount )
    {
        OwnerPos = (PlayerBoxSizeY + BoxSpaceY)*PlayerCount + BoxTextOffsetY;
        Canvas.Style = ERenderStyle.STY_Alpha;
        Canvas.DrawColor = HUDClass.default.TurqColor * 0.5;
        Canvas.SetPos(BoxXPos, HeaderOffsetY + (PlayerBoxSizeY + BoxSpaceY)*PlayerCount);
        Canvas.DrawTileStretched( BoxMaterial, BoxWidth, PlayerBoxSizeY);
        Canvas.Style = ERenderStyle.STY_Normal;
    }
    else
        OwnerPos = (PlayerBoxSizeY + BoxSpaceY)*OwnerOffset + BoxTextOffsetY;

    Canvas.DrawColor = HUDClass.default.GoldColor;
    Canvas.SetPos(NameXPos, OwnerPos);
    if ( LongestNameLength > 0 )
        Canvas.Font = ReducedFont;
    Canvas.DrawText(playername[OwnerOffset],true);
    if ( LongestNameLength > 0 )
        Canvas.Font = GetSmallerFontFor(Canvas,FontReduction);
    Canvas.SetPos(ScoreXPos, OwnerPos);
    if ( GRI.PRIArray[OwnerOffset].bOutOfLives )
        Canvas.DrawText(OutText,true);
    else
        Canvas.DrawText(int(GRI.PRIArray[OwnerOffset].Score),true);
    Canvas.SetPos(DeathsXPos, OwnerPos);
    Canvas.DrawText(int(GRI.PRIArray[OwnerOffset].Deaths),true);
}

simulated function String GetTitleString()
{
    local MonsterFightClubGRI G;
    local string Title;

    Title = "MONSTER FIGHT CLUB";
    if (GRI == None)
        return Title;

    G = MonsterFightClubGRI(GRI);
    if (G != None && G.FighterAName != "")
        Title = Title $ "  -  " $ Caps(G.FighterAName) $ " VS " $ Caps(G.FighterBName)
                $ "  (Round " $ G.RoundNumber $ " of " $ G.RoundsTotal $ ")";
    return Title;
}

defaultproperties
{
     PointsText="BANKROLL"
     DeathsText="BETS WON"
     TimeLimit="SHOW ENDS IN:"
}
