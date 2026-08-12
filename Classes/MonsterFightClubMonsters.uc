//=============================================================================
// MonsterFightClubMonsters
// Config object holding the fight roster. Editable in
// System\MonsterFightClubV1.ini under:
//   [MonsterFightClubV1.MonsterFightClubMonsters]
//
// Simple format:
//   MonsterTable=(MonsterName="Pupae",MonsterClassName="SkaarjPack.SkaarjPupae")
//=============================================================================
class MonsterFightClubMonsters extends Object
    config(MonsterFightClubV1);

struct MonsterEntry
{
    var() string MonsterName;
    var() string MonsterClassName;
};

var() config array<MonsterEntry> MonsterTable;

defaultproperties
{
     MonsterTable(0)=(MonsterName="Pupae",MonsterClassName="SkaarjPack.SkaarjPupae")
     MonsterTable(1)=(MonsterName="RazorFly",MonsterClassName="SkaarjPack.Razorfly")
     MonsterTable(2)=(MonsterName="Manta",MonsterClassName="SkaarjPack.Manta")
     MonsterTable(3)=(MonsterName="Krall",MonsterClassName="SkaarjPack.Krall")
     MonsterTable(4)=(MonsterName="Elite Krall",MonsterClassName="SkaarjPack.EliteKrall")
     MonsterTable(5)=(MonsterName="Gasbag",MonsterClassName="SkaarjPack.Gasbag")
     MonsterTable(6)=(MonsterName="Brute",MonsterClassName="SkaarjPack.Brute")
     MonsterTable(7)=(MonsterName="Fire Skaarj",MonsterClassName="SkaarjPack.FireSkaarj")
     MonsterTable(8)=(MonsterName="Ice Skaarj",MonsterClassName="SkaarjPack.IceSkaarj")
     MonsterTable(9)=(MonsterName="Skaarj",MonsterClassName="SkaarjPack.Skaarj")
     MonsterTable(10)=(MonsterName="Behemoth",MonsterClassName="SkaarjPack.Behemoth")
     MonsterTable(11)=(MonsterName="WarLord",MonsterClassName="SkaarjPack.WarLord")
}
