namespace DotaPing.Core;

public enum Phase { Idle, Arming, Open, Blocked }

public abstract record GestureAction
{
    public sealed record Arm(Point2 Point) : GestureAction;
    public sealed record Show(Point2 Point) : GestureAction;
    public sealed record Hover(PingKind Kind, double? Angle) : GestureAction;
    public sealed record Hide() : GestureAction;
    public sealed record Dismiss() : GestureAction;
    public sealed record Commit(PingKind Kind, Point2 Point) : GestureAction;
}

/// <summary>Consume tells the input hook to keep a button event from the app below.</summary>
public sealed record GestureResponse(IReadOnlyList<GestureAction> Actions, bool Consume)
{
    public static readonly GestureResponse None = new([], false);
    public bool Matches(bool consume, params GestureAction[] actions) => Consume == consume && Actions.SequenceEqual(actions);
}

/// <summary>
/// Pure state machine, ported from the macOS PingCore. Coordinates have y
/// increasing upwards. Chord triggers open the wheel while the modifiers are
/// held; releasing any of them sends, and so does a primary click or touchpad
/// tap while the wheel is open. The left-button trigger follows the game:
/// Alt-click pings, Ctrl+Alt-click warns, and holding the button opens the
/// wheel until it is released.
/// </summary>
public sealed class GestureMachine
{
    public Phase Phase { get; private set; } = Phase.Idle;
    public PingKind Selected { get; private set; } = PingKind.Regular;
    public Point2 Anchor { get; private set; }
    public Modifiers CurrentModifiers { get; private set; }
    /// <summary>A primary press DotaPing swallowed; its drags and release are swallowed too.</summary>
    public bool OwnsPrimaryPress { get; private set; }
    public Trigger Trigger { get; set; } = Trigger.HoldCtrlAltShift;
    public double DeadZone { get; set; } = WheelGeometry.CenterRadius;
    Point2 center, pointer;

    public IReadOnlyList<GestureAction> FlagsChanged(Modifiers flags, Point2 point, bool otherInputHeld)
    {
        CurrentModifiers = flags;
        // Modifiers only qualify the press; once the button is down, its release ends the gesture.
        if (Trigger.UsesPrimaryButton()) return [];
        var chord = Trigger.Modifiers();
        if (Phase == Phase.Blocked)
        {
            if ((flags & chord) == 0) Phase = Phase.Idle;
            return [];
        }
        if (Phase == Phase.Idle)
        {
            if (flags != chord) return [];
            if (otherInputHeld) { Phase = Phase.Blocked; return []; }
            Begin(point);
            return [new GestureAction.Arm(point)];
        }
        // Adding another modifier is a different shortcut, never a commit.
        if ((flags & ~chord) != 0) return Cancel();
        if (flags != chord)
        {
            bool wasOpen = Phase == Phase.Open;
            Phase = (flags & chord) == 0 ? Phase.Idle : Phase.Blocked;
            return wasOpen ? [new GestureAction.Dismiss(), new GestureAction.Commit(Selected, Anchor)] : [new GestureAction.Hide()];
        }
        return [];
    }

    public IReadOnlyList<GestureAction> DelayElapsed()
    {
        if (Phase != Phase.Arming) return [];
        if (Trigger.UsesPrimaryButton() ? !OwnsPrimaryPress : CurrentModifiers != Trigger.Modifiers()) return [];
        Phase = Phase.Open;
        return [new GestureAction.Show(Anchor)];
    }

    public IReadOnlyList<GestureAction> SetWheelCenter(Point2 point)
    {
        center = point;
        // At an edge the wheel moves inwards, but the original ping anchor stays fixed.
        if (Distance(pointer, Anchor) <= 4) return [];
        return Moved(pointer);
    }

    public IReadOnlyList<GestureAction> Moved(Point2 point)
    {
        pointer = point;
        if (Phase != Phase.Open) return [];
        Selected = WheelGeometry.Selection(point, center, DeadZone);
        return [new GestureAction.Hover(Selected, WheelGeometry.Direction(point, center, DeadZone))];
    }

    /// <summary>Primary button: left click, touchpad press or tap.</summary>
    public GestureResponse PrimaryDown(Point2 point, bool otherInputHeld)
    {
        if (Trigger.UsesPrimaryButton())
        {
            if (Phase != Phase.Idle || OwnsPrimaryPress || otherInputHeld) return GestureResponse.None;
            if (CurrentModifiers == Trigger.Modifiers())
            {
                Begin(point); OwnsPrimaryPress = true;
                return new([new GestureAction.Arm(point)], true);
            }
            if (Trigger.WarningModifiers() is { } warning && CurrentModifiers == warning)
            {
                OwnsPrimaryPress = true;
                return new([new GestureAction.Commit(PingKind.Warning, point)], true);
            }
            return GestureResponse.None;
        }
        if (Phase != Phase.Open) return new(Cancel(), false);
        // A click or tap confirms. The chord must then be fully released before the next one.
        OwnsPrimaryPress = true;
        Phase = Phase.Blocked;
        return new([new GestureAction.Dismiss(), new GestureAction.Commit(Selected, Anchor)], true);
    }

    public GestureResponse PrimaryDragged(Point2 point)
    {
        // Without a press of its own, a drag belongs to the app; keep the original cancel.
        if (!OwnsPrimaryPress) return new(Cancel(), false);
        return new(Moved(point), true);
    }

    public GestureResponse PrimaryUp(Point2 point)
    {
        if (!OwnsPrimaryPress) return GestureResponse.None;
        OwnsPrimaryPress = false;
        if (!Trigger.UsesPrimaryButton()) return new([], true);
        switch (Phase)
        {
            case Phase.Arming:
                // Released before the wheel opened: an ordinary Alt-click ping.
                Phase = Phase.Idle;
                return new([new GestureAction.Hide(), new GestureAction.Commit(PingKind.Regular, Anchor)], true);
            case Phase.Open:
                Phase = Phase.Idle;
                return new([new GestureAction.Dismiss(), new GestureAction.Commit(Selected, Anchor)], true);
            default:
                return new([], true);
        }
    }

    public IReadOnlyList<GestureAction> Cancel()
    {
        bool hadGesture = Phase is Phase.Arming or Phase.Open;
        if (Trigger.UsesPrimaryButton()) Phase = Phase.Idle;
        else Phase = (CurrentModifiers & Trigger.Modifiers()) == 0 ? Phase.Idle : Phase.Blocked;
        Selected = PingKind.Regular;
        return hadGesture ? [new GestureAction.Hide()] : [];
    }

    public void Reset(bool blockUntilRelease = false, Modifiers modifiers = Modifiers.None)
    {
        Phase = blockUntilRelease ? Phase.Blocked : Phase.Idle;
        Selected = PingKind.Regular;
        CurrentModifiers = modifiers;
        OwnsPrimaryPress = false;
    }

    void Begin(Point2 point)
    {
        Anchor = point; center = point; pointer = point; Selected = PingKind.Regular;
        Phase = Phase.Arming;
    }

    static double Distance(Point2 a, Point2 b) => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));
}
