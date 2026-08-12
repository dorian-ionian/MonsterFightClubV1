//=============================================================================
// MonsterFightClubBot
// A pawn-less member of the audience: places bets and fires off text taunts.
// Taunts go through the Say channel so the HUD shows the bot's portrait.
//=============================================================================
class MonsterFightClubBot extends AIController;

var bool bHasBetThisRound;

function SayTaunt(string Text)
{
    if (Text == "")
        return;
    Level.Game.Broadcast(self, Text, 'Say');
}

auto state BettingLounge
{
    function BeginState()
    {
        SetTimer(2.0 + FRand() * 3.0, false);
    }

    function Timer()
    {
        local MonsterFightClubGame G;

        G = MonsterFightClubGame(Level.Game);
        if (G != None)
        {
            if (G.bBettingOpen && !bHasBetThisRound)
            {
                bHasBetThisRound = true;
                // Try to bet, then ALWAYS ready up - even if the bot is
                // broke (below min bet). Otherwise AllBettorsReady() never
                // passes and the round stalls forever.
                G.PlaceBotBet(self);
                G.MarkReady(self);
            }
            else if (FRand() < 0.4)
            {
                G.MaybeTaunt(self);
            }
        }
        SetTimer(3.0 + FRand() * 4.0, false);
    }
}

defaultproperties
{
     bIsPlayer=True
     PlayerReplicationInfoClass=Class'MonsterFightClub.MonsterFightClubPRI'
}
