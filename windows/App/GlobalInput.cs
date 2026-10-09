using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using DotaPing.Core;
using static DotaPing.NativeMethods;

namespace DotaPing;

/// <summary>
/// Low-level keyboard and mouse hooks feeding the shared gesture machine. The
/// hooks run on the UI thread; UI work is posted so they return quickly.
/// Points reach the machine in physical pixels with y flipped to point up,
/// the convention the wheel geometry uses.
/// </summary>
sealed class GlobalInput : IDisposable
{
    /// <summary>Marks DotaPing's own injected key so the hook ignores it.</summary>
    static readonly UIntPtr MaskMarker = new(0x444F5441);
    /// <summary>An unassigned key: pressing it while Alt is down stops Alt's release from opening an app's menu bar.</summary>
    const ushort MenuMaskKey = 0xE8;

    public event Action<GestureAction>? ActionReceived;
    public GestureMachine Machine { get; } = new();
    readonly Dispatcher dispatcher;
    readonly HookProc keyboardProc, mouseProc;
    IntPtr keyboardHook, mouseHook;
    DispatcherTimer? timer;
    readonly HashSet<uint> keysDown = [], swallowedKeys = [], modifierKeys = [];
    bool leftDown, rightDown, swallowedRight;
    double effectScale = 1;

    public GlobalInput(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        keyboardProc = KeyboardProc;
        mouseProc = MouseProc;
    }

    public bool Running => keyboardHook != IntPtr.Zero && mouseHook != IntPtr.Zero;

    public bool Start(Trigger trigger, double scale)
    {
        Stop();
        Machine.Trigger = trigger;
        effectScale = scale;
        foreach (uint vk in new uint[] { 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C })
            if ((GetAsyncKeyState((int)vk) & 0x8000) != 0) modifierKeys.Add(vk);
        var held = CurrentModifiers();
        Machine.Reset(!trigger.UsesPrimaryButton() && (held & trigger.Modifiers()) != 0, held);
        var module = GetModuleHandle(null);
        keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, keyboardProc, module, 0);
        mouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseProc, module, 0);
        if (Running) return true;
        Stop();
        return false;
    }

    public void Stop()
    {
        timer?.Stop(); timer = null;
        if (keyboardHook != IntPtr.Zero) UnhookWindowsHookEx(keyboardHook);
        if (mouseHook != IntPtr.Zero) UnhookWindowsHookEx(mouseHook);
        keyboardHook = mouseHook = IntPtr.Zero;
        keysDown.Clear(); swallowedKeys.Clear(); modifierKeys.Clear();
        leftDown = rightDown = swallowedRight = false;
        Machine.Reset();
    }

    public void Dispose() => Stop();

    public void CancelCurrent()
    {
        timer?.Stop(); timer = null;
        Dispatch(Machine.Cancel());
    }

    /// <summary>Wheel centre in physical pixels (y down), after edge clamping.</summary>
    public void SetWheelCenter(Point2 pixel) => Dispatch(Machine.SetWheelCenter(ToMachine(pixel.X, pixel.Y)));

    public static Point2 ToMachine(double x, double y) => new(x, -y);
    public static Point2 ToPixel(Point2 machine) => new(machine.X, -machine.Y);

    static bool IsModifier(uint vk) => vk is >= 0xA0 and <= 0xA5 or 0x10 or 0x11 or 0x12 or 0x5B or 0x5C;

    Modifiers CurrentModifiers()
    {
        var result = Modifiers.None;
        foreach (var vk in modifierKeys)
            result |= vk switch
            {
                0xA0 or 0xA1 or 0x10 => Modifiers.Shift,
                0xA2 or 0xA3 or 0x11 => Modifiers.Control,
                0xA4 or 0xA5 or 0x12 => Modifiers.Alt,
                _ => Modifiers.Win,
            };
        return result;
    }

    bool Active => Machine.Phase is Phase.Arming or Phase.Open;

    static Point2 CursorPoint()
    {
        GetCursorPos(out var p);
        return ToMachine(p.X, p.Y);
    }

    IntPtr KeyboardProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var info = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            if (info.dwExtraInfo != MaskMarker && HandleKey((int)wParam, info.vkCode)) return new IntPtr(1);
        }
        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    bool HandleKey(int message, uint vk)
    {
        bool down = message is WM_KEYDOWN or WM_SYSKEYDOWN;
        if (IsModifier(vk))
        {
            var before = CurrentModifiers();
            if (down) modifierKeys.Add(vk); else modifierKeys.Remove(vk);
            var after = CurrentModifiers();
            // Auto-repeat resends a held modifier; only real changes count.
            if (after != before) Dispatch(Machine.FlagsChanged(after, CursorPoint(), leftDown || rightDown || keysDown.Count > 0));
            return false;
        }
        if (down)
        {
            keysDown.Add(vk);
            bool wasActive = Active;
            if (swallowedKeys.Contains(vk)) return true;
            CancelCurrent();
            if (wasActive && vk == VK_ESCAPE) { swallowedKeys.Add(vk); return true; }
            return false;
        }
        keysDown.Remove(vk);
        return swallowedKeys.Remove(vk);
    }

    IntPtr MouseProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var info = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            if (HandleMouse((int)wParam, ToMachine(info.pt.X, info.pt.Y))) return new IntPtr(1);
        }
        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    bool HandleMouse(int message, Point2 point)
    {
        switch (message)
        {
            case WM_MOUSEMOVE:
                // Moves are never swallowed: that would freeze the pointer.
                if (leftDown) Respond(Machine.PrimaryDragged(point));
                else Dispatch(Machine.Moved(point));
                return false;
            case WM_LBUTTONDOWN:
                leftDown = true;
                SyncModifiers();
                bool consumed = Respond(Machine.PrimaryDown(point, rightDown || keysDown.Count > 0));
                if (consumed && Machine.Trigger.UsesPrimaryButton()) PostMenuMask();
                return consumed;
            case WM_LBUTTONUP:
                leftDown = false;
                return Respond(Machine.PrimaryUp(point));
            case WM_RBUTTONDOWN:
            {
                // Includes a two-finger tap on a touchpad.
                rightDown = true;
                bool wasActive = Active;
                CancelCurrent();
                if (wasActive) { swallowedRight = true; return true; }
                return false;
            }
            case WM_RBUTTONUP:
                rightDown = false;
                if (swallowedRight) { swallowedRight = false; return true; }
                return false;
            case WM_MBUTTONDOWN or WM_XBUTTONDOWN:
                CancelCurrent();
                return false;
            case WM_MOUSEWHEEL or WM_MOUSEHWHEEL:
                // Touchpads keep scrolling after a flick; never cancel on it. While
                // the wheel is visible, keep the window below from scrolling.
                return Machine.Phase == Phase.Open;
        }
        return false;
    }

    /// <summary>A key-up can be lost (a secure desktop, a stalled hook); re-read the real state before a click.</summary>
    void SyncModifiers()
    {
        var before = CurrentModifiers();
        modifierKeys.Clear();
        foreach (uint vk in new uint[] { 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C })
            if ((GetAsyncKeyState((int)vk) & 0x8000) != 0) modifierKeys.Add(vk);
        var after = CurrentModifiers();
        if (after != before) Dispatch(Machine.FlagsChanged(after, CursorPoint(), keysDown.Count > 0));
    }

    bool Respond(GestureResponse response)
    {
        Dispatch(response.Actions);
        return response.Consume;
    }

    void Dispatch(IReadOnlyList<GestureAction> actions)
    {
        foreach (var action in actions)
        {
            switch (action)
            {
                case GestureAction.Arm arm:
                    var (_, dpi) = Screens.At(arm.Point.X, -arm.Point.Y);
                    Machine.DeadZone = WheelGeometry.CenterRadius * effectScale * dpi;
                    timer?.Stop();
                    timer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = TimeSpan.FromMilliseconds(180) };
                    timer.Tick += (_, _) => { timer?.Stop(); timer = null; Dispatch(Machine.DelayElapsed()); };
                    timer.Start();
                    break;
                case GestureAction.Hide or GestureAction.Dismiss:
                    timer?.Stop(); timer = null;
                    Post(action);
                    break;
                case GestureAction.Show:
                    if ((Machine.Trigger.Modifiers() & Modifiers.Alt) != 0 && !Machine.Trigger.UsesPrimaryButton()) PostMenuMask();
                    Post(action);
                    break;
                default:
                    Post(action);
                    break;
            }
        }
    }

    void Post(GestureAction action) => dispatcher.InvokeAsync(() => ActionReceived?.Invoke(action));

    void PostMenuMask() => dispatcher.InvokeAsync(() =>
    {
        var inputs = new[] { Key(MenuMaskKey, false, MaskMarker), Key(MenuMaskKey, true, MaskMarker) };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    });
}
