//=============================================================================
// MonsterFightClubPreviewActor
// A client-local, non-colliding spinning mesh actor used to render a 3D
// preview of a fighter on the HUD "VS" card.
//
// Modeled on InvasionPro's InvasionProSpinnyMonster, with one crucial
// difference for a TRANSPARENT HUD: bHidden=True keeps the world renderer
// from drawing the actor (no ghost model in the middle of the screen),
// while Canvas.DrawActorClipped still renders hidden actors into the card.
// Spin is a constant per-tick increment (InvasionPro's exact formula,
// minus the TimeDilation divisor so slow-mo doesn't make it spin faster).
//=============================================================================
class MonsterFightClubPreviewActor extends Actor;

var() int SpinRate;                 // yaw units per second (65536 = full turn)
var float SpinYaw;                  // accumulated spin yaw - the HUD applies it
var float DrawScaleBaseHeight;      // monster's real collision height (for fitting)
var EDrawType PreviewDrawType;      // DT_Mesh or DT_Sprite - what SetupFor chose

simulated function SetupFor(class<Monster> MClass)
{
    local int i;

    if (MClass == None)
        return;

    // Fit base height accounts for the monster's own scale - some packs
    // (especially U1Pawns) render their mesh much larger or smaller than
    // their collision box, which made them invisible on the cards.
    DrawScaleBaseHeight = Max(1.0, MClass.default.CollisionHeight)
                          * FMax(0.01, MClass.default.DrawScale)
                          * FMax(0.01, MClass.default.DrawScale3D.Z);

    // Copy the monster's own draw type / mesh / texture / skins - exactly
    // what InvasionPro's UpdateSpinnyDude does. This covers skeletal-mesh
    // monsters, VERTEX-mesh monsters (U1Pawns), static-mesh monsters, and
    // sprite monsters (DT_Sprite billboards use Texture in UT2004 -
    // DoomPawns2k4 needs it or the preview renders nothing). LinkMesh
    // FIRST (it sets the mesh), then SetDrawType - the order matters for
    // vertex meshes.
    LinkMesh(MClass.default.Mesh);
    SetStaticMesh(MClass.default.StaticMesh);
    SetDrawType(MClass.default.DrawType);
    PreviewDrawType = MClass.default.DrawType;
    Texture = MClass.default.Texture;
    Style = MClass.default.Style;
    ScaleGlow = MClass.default.ScaleGlow;
    PrePivot = MClass.default.PrePivot;   // keeps U1 meshes centered

    Skins.Length = MClass.default.Skins.Length;
    for (i = 0; i < MClass.default.Skins.Length; i++)
        Skins[i] = MClass.default.Skins[i];
    if (MClass.default.Skins.Length == 0)
        Skins[0] = None;

    // Turntable spin: the model rotates around its own vertical axis. The
    // HUD adds this to the camera-relative yaw every frame, so the spin is
    // stable no matter how the free camera is aimed.
    SpinRate = 4096;
}

// Size the model so it fills most of the card's model area, computed from
// the actual canvas dimensions, render distance and FOV - resolution and
// aspect independent.
simulated function FitToCard(float TargetWorldHeight)
{
    if (TargetWorldHeight <= 0)
        return;
    SetDrawScale(FClamp(TargetWorldHeight / Max(1.0, DrawScaleBaseHeight), 0.15, 2.0));
}

simulated event PostBeginPlay()
{
    Super.PostBeginPlay();
    SetCollision(false, false, false);
    bCollideWorld = false;
    bUnlit = true;
    bFixedRotationDir = true;   // vertex meshes need this to render rotated
    SetPhysics(PHYS_None);
}

// Spin accumulator only - the HUD applies the rotation each frame so the
// model keeps a camera-relative facing PLUS this turntable spin. The spin
// is stable no matter how the free camera is aimed.
simulated function Tick(float Delta)
{
    if (SpinRate != 0)
        SpinYaw += Delta * SpinRate;
}

defaultproperties
{
     DrawType=DT_StaticMesh
     // InvasionPro's exact setup: NOT hidden (bHidden blocks vertex-mesh
     // rendering through DrawActorClipped on some clients), only drawn for
     // the owning player, and only drawn in the world if ATTACHED (it never
     // is, so no floating model in the arena - but DrawActorClipped still
     // renders it into the HUD card).
     bHidden=False
     bOnlyOwnerSee=True
     bOnlyDrawIfAttached=True
     RemoteRole=ROLE_None
     LODBias=100000.000000
     DrawScale=0.500000
     bUnlit=True
     bAlwaysTick=True
     bNoRepMesh=True
     bFixedRotationDir=True
}
