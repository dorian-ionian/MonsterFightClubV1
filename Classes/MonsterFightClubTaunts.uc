//=============================================================================
// MonsterFightClubTaunts
// Text taunts used by the bots. Editable in System\MonsterFightClubV1.ini:
//   [MonsterFightClubV1.MonsterFightClubTaunts]
// %p in TargetTaunts is replaced with the taunted player's name.
// %a / %b in FighterTaunts are replaced with the CURRENT fighter names.
//=============================================================================
class MonsterFightClubTaunts extends Object
    config(MonsterFightClubV1);

var() config array<string> Taunts;         // generic show commentary
var() config array<string> TargetTaunts;   // aimed at a specific audience member
var() config array<string> FighterTaunts;  // aimed at the current fighters (%a / %b)

defaultproperties
{
     Taunts(0)="This is the best show on television!"
     Taunts(1)="I've seen tougher fights in a Nali village."
     Taunts(2)="That Skaarj has been training hard. I can tell."
     Taunts(3)="Someone get these two a manager!"
     Taunts(4)="My money's on the one with bigger claws."
     Taunts(5)="The Brute doesn't even feel pain. That's a problem."
     Taunts(6)="Keep your eyes on the Gasbag. It's sneaky!"
     Taunts(7)="I could take both of them, honestly."
     Taunts(8)="This is why I pay for cable!"
     Taunts(9)="The WarLord hasn't lost a fight all season!"
     Taunts(10)="That Behemoth hits like a freight train!"
     Taunts(11)="Somebody get the medic. Actually, don't bother."
     Taunts(12)="I've seen this episode. It ends badly for one of them."
     Taunts(13)="The RazorFly is fast, but it hits like a mosquito."
     Taunts(14)="Betting against the Skaarj is a rookie mistake."
     Taunts(15)="What a match! I need more popcorn!"
     Taunts(16)="That monster's got a chin like a Nali fortress."
     Taunts(17)="Did you see that swing? My grandmother hits harder!"
     Taunts(18)="The bookies are sweating more than the fighters."
     Taunts(19)="One of these two is about to have a very bad day."
     Taunts(20)="I'd put money on the one still standing, but that's just me."
     Taunts(21)="This is better than the finals. Don't tell the finals."
     Taunts(22)="That roar gave me chills. The other one's in trouble."
     Taunts(23)="You call that a fight? My pet Krall fights harder!"
     Taunts(24)="The arena cleaners are going to earn their pay tonight."
     Taunts(25)="Somewhere, a god is smiling at this bloodsport."
     Taunts(26)="I've seen more ferocity at a Nali dinner party."
     Taunts(27)="That hit sounded expensive. Someone's paying for it!"
     Taunts(28)="The underdog just landed a haymaker! Get in there!"
     Taunts(29)="You can't teach that kind of instinct. You just bet on it."
     Taunts(30)="This crowd is loving it. I'd say the feeling's mutual."
     Taunts(31)="Round two is where the real monsters come out."

     TargetTaunts(0)="%p is about to lose their lunch money!"
     TargetTaunts(1)="Hey %p, the betting window is that way. Don't blow it all."
     TargetTaunts(2)="%p couldn't pick a winner if their life depended on it."
     TargetTaunts(3)="I heard %p bet on the underdog. Bold. Stupid. Bold."
     TargetTaunts(4)="Nice bet, %p. I'll be taking that money."
     TargetTaunts(5)="%p is sweating harder than the fighters."
     TargetTaunts(6)="Don't worry %p, you can win it back next round!"
     TargetTaunts(7)="%p's wallet is already crying."
     TargetTaunts(8)="%p just bet the house. Literally."
     TargetTaunts(9)="I saw %p flinch on that last hit."
     TargetTaunts(10)="%p's pick is about to become a cautionary tale."
     TargetTaunts(11)="Easy money, thanks to %p."
     TargetTaunts(12)="%p should have watched the fight instead of the menu."
     TargetTaunts(13)="The house always wins, %p. The house always wins."
     TargetTaunts(14)="%p's confidence is adorable. Financially speaking."
     TargetTaunts(15)="Somebody get %p a tissue. And a new betting strategy."

     FighterTaunts(0)="%a looks mean, but %b's got that look in their eyes."
     FighterTaunts(1)="I've got $50 on %a. Don't let me down, big guy."
     FighterTaunts(2)="Come on %a, show %b what you're made of!"
     FighterTaunts(3)="%b's been pacing like they know something we don't."
     FighterTaunts(4)="If %a wins this, I'm buying a round for the whole arena."
     FighterTaunts(5)="%b doesn't look impressed. That's either brave or stupid."
     FighterTaunts(6)="My money's on %a. That jaw can take a hit."
     FighterTaunts(7)="%a vs %b - this is the fight of the century!"
     FighterTaunts(8)="Someone tell %b this is a fight, not a stroll."
     FighterTaunts(9)="%a's got reach, %b's got rage. Classic matchup."
     FighterTaunts(10)="I'd hate to be in %a's corner right now... actually no, I'd love it."
     FighterTaunts(11)="%b is about to learn why %a is undefeated at home."
     FighterTaunts(12)="Look at %a warming up. That's a champion's walk."
     FighterTaunts(13)="%b's entrance was weak. %a's was legendary."
     FighterTaunts(14)="The bookies have %a as the favorite. Don't trust the bookies."
     FighterTaunts(15)="If %a and %b don't tear each other apart, I want my money back."
}
