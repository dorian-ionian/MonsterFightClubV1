@echo off
:10
ucc server DM-Gael?game=MonsterFightClubV1.MonsterFightClubGame?Mutator=2009Dragonv2.MutDragon,MonsterRagdollOverrideV1.MutMonsterRagdollOverride?GamePassword=CHANGE_ME -ini=UT2004MFC.ini -log=MFC_server.log
copy MFC_server.log MFC_servercrash.log
goto 10

