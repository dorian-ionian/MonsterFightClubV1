//=============================================================================
// MonsterFightClubInputInteraction
// A client-side Interaction that intercepts the MIDDLE MOUSE button (and
// Backslash as a backup) and toggles the action/boxing camera - WITHOUT
// requiring players to edit their User.ini bindings. Added automatically
// when the player's controller spawns.
//
// Interactions receive every raw key event BEFORE the input bindings are
// processed, so this works regardless of what MiddleMouse is bound to in
// the player's ini (default is MoveForward). Returning true consumes the
// key so the default binding never fires.
//=============================================================================
class MonsterFightClubInputInteraction extends Interaction;

var bool bInitialized;

event Initialized()
{
    Super.Initialized();
    bInitialized = true;
}

function bool KeyEvent(out EInputKey Key, out EInputAction Action, float Delta)
{
    local MonsterFightClubPlayerController MPC;

    if (ViewportOwner == None || ViewportOwner.Actor == None)
        return false;

    // Backslash: handled here (consume press AND release so the binding
    // can't double-fire). Middle mouse is deliberately NOT consumed - it
    // falls through to the User.ini binding (MiddleMouse=ToggleActionCam),
    // which works on every client including the 64-bit preview.
    if (Key == IK_Backslash)
    {
        if (Action == IST_Press)
        {
            MPC = MonsterFightClubPlayerController(ViewportOwner.Actor);
            if (MPC != None)
            {
                if (MPC.bLogInput)
                    log("MFC-INPUT: KeyEvent caught key=" $ Key $ " action=" $ Action, 'MonsterFightClubV1');
                MPC.ToggleActionCam();
            }
        }
        return true;   // consume press AND release - the binding never fires
    }
    if (Key == IK_MiddleMouse && Action == IST_Press && MPC != None && MPC.bLogInput)
        log("MFC-INPUT: MMB seen - passing to User.ini binding", 'MonsterFightClubV1');

    // DIAGNOSTIC: log every key that reaches the interaction (bLogInput).
    if (Action == IST_Press && Key != IK_LeftMouse && Key != IK_RightMouse
        && MPC != None && MPC.bLogInput)
        log("MFC-INPUT: key=" $ Key $ " action=" $ Action, 'MonsterFightClubV1');
    return false;
}

defaultproperties
{
     bActive=True
     bVisible=False
     bRequiresTick=False
}
