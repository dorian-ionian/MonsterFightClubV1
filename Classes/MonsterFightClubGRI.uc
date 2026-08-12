//=============================================================================
// MonsterFightClubGRI
// Replicated fight state so every spectator's HUD can show the show.
//=============================================================================
class MonsterFightClubGRI extends GameReplicationInfo;

var string FighterAName, FighterBName;
var string FighterAClassName, FighterBClassName;   // full class paths for the HUD preview
var string ChampionName;        // gauntlet mode: the standing champion ("" if none)
var int ChampionStreak;         // gauntlet mode: consecutive matchup wins by the champion
var int FighterAHealth, FighterBHealth;
var int FighterAMaxHealth, FighterBMaxHealth;
var byte Phase;                 // see MonsterFightClubGame phase constants
var int RoundNumber;
var int RoundsTotal;
var int MatchupNumber;
var int PhaseTimeLeft;
var bool bBettingOpen;
var bool bShowEnded;          // the time limit fired - no more betting
var bool bSlowMo;
var bool bFightersActive;     // at least one fighter is alive
var vector FighterALocation;  // live positions — the client camera tracks these
var vector FighterBLocation;
var byte CameraCutID;         // bumped on every server camera cut

replication
{
    // Names must keep replicating on every matchup change, not just the
    // initial GRI send - otherwise the HUD shows stale challengers.
    reliable if ((bNetInitial || bNetDirty) && Role == ROLE_Authority)
        FighterAName, FighterBName, FighterAClassName, FighterBClassName, RoundsTotal;

    reliable if (bNetDirty && Role == ROLE_Authority)
        ChampionName, ChampionStreak;

    reliable if (bNetDirty && Role == ROLE_Authority)
        Phase, RoundNumber, MatchupNumber, PhaseTimeLeft, bBettingOpen, bShowEnded, bSlowMo;

    // Health replicates RELIABLY - unreliable drops (flaky connections)
    // left the cards showing the stock 100 default for dinos/dragons.
    reliable if (bNetDirty && Role == ROLE_Authority)
        FighterAHealth, FighterBHealth, FighterAMaxHealth, FighterBMaxHealth, bFightersActive;

    unreliable if (Role == ROLE_Authority)
        FighterALocation, FighterBLocation, CameraCutID;
}

defaultproperties
{
}
