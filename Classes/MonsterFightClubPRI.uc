//=============================================================================
// MonsterFightClubPRI
// Bankroll + betting state + bot portrait for the scoreboard and chat.
//=============================================================================
class MonsterFightClubPRI extends xPlayerReplicationInfo;

var int Money;          // current bankroll (mirrored into Score for the scoreboard)
var int BetWins;        // number of winning bets (mirrored into Deaths)
var int CurrentBet;     // amount wagered on the current round
var int BetFighter;     // 1 or 2 - which fighter the current bet is on
var Material Portrait;  // portrait shown when a pawn-less bot chats (Material, not
                        // Texture - many player records use shaders/combiners and
                        // a Texture cast would silently fail -> question mark)
var bool bReady;        // this bettor has locked in for the current round

replication
{
    reliable if (bNetDirty && Role == ROLE_Authority)
        Money, BetWins, Portrait, bReady;

    unreliable if (Role == ROLE_Authority)
        CurrentBet, BetFighter;
}

simulated function Material GetPortrait()
{
    local array<xUtil.PlayerRecord> Recs;
    local int i;

    if (Portrait != None)
        return Portrait;

    // The name replicates reliably even when the portrait material doesn't
    // arrive in time (package/precache timing). Re-look-up the portrait by
    // name, case-insensitively, so bots never fall through to the generic
    // question-mark picture.
    if (PlayerName != "")
    {
        class'xUtil'.static.GetPlayerList(Recs);
        for (i = 0; i < Recs.Length; i++)
            if (Recs[i].DefaultName ~= PlayerName && Recs[i].Portrait != None)
                return Recs[i].Portrait;
    }
    return Super.GetPortrait();
}

defaultproperties
{
}
