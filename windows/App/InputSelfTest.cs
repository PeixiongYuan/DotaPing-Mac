using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using DotaPing.Core;
using static DotaPing.NativeMethods;

namespace DotaPing;

/// <summary>
/// End-to-end check of the real hooks: injects keyboard and mouse input with
/// SendInput and checks what the gesture machine reports. Needs an interactive
/// desktop; reports SKIP when input cannot be injected.
/// </summary>
static class InputSelfTest
{
    const ushort LShift = 0xA0, LControl = 0xA2, LAlt = 0xA4, Escape = 0x1B;

    static bool Send(params INPUT[] inputs) => SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>()) == inputs.Length;

    static INPUT Mouse(uint flags, int x = 0, int y = 0) => new()
    {
        type = INPUT_MOUSE,
        u = new InputUnion { mi = new MOUSEINPUT { dx = x, dy = y, dwFlags = flags } },
    };

    static bool MoveTo(int x, int y)
    {
        int vx = GetSystemMetrics(SM_XVIRTUALSCREEN), vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int vw = Math.Max(2, GetSystemMetrics(SM_CXVIRTUALSCREEN)), vh = Math.Max(2, GetSystemMetrics(SM_CYVIRTUALSCREEN));
        int nx = (int)Math.Round((x - vx) * 65535.0 / (vw - 1)), ny = (int)Math.Round((y - vy) * 65535.0 / (vh - 1));
        return Send(Mouse(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK, nx, ny));
    }

    static void Keys(bool up, params ushort[] keys)
    {
        foreach (var key in keys) { Send(Key(key, up)); Thread.Sleep(25); }
    }

    static void Click(int holdMilliseconds = 40)
    {
        Send(Mouse(MOUSEEVENTF_LEFTDOWN)); Thread.Sleep(holdMilliseconds); Send(Mouse(MOUSEEVENTF_LEFTUP));
    }

    public static async Task<int> Run(Dispatcher dispatcher)
    {
        var actions = new List<GestureAction>();
        var input = new GlobalInput(dispatcher);
        input.ActionReceived += actions.Add;
        GetCursorPos(out var start);
        int cx = start.X, cy = start.Y, failures = 0;
        if (cx < 200 || cy < 200) { cx = 400; cy = 400; }

        var scenarios = new (string Name, Trigger Trigger, Action Steps, Func<List<GestureAction>, bool> Expect)[]
        {
            ("Hold Ctrl+Alt+Shift, move up, release", Trigger.HoldCtrlAltShift, () =>
            {
                Keys(false, LControl, LAlt, LShift); Thread.Sleep(350);
                MoveTo(cx, cy - 120); Thread.Sleep(80);
                Keys(true, LShift, LAlt, LControl);
            }, got => Commits(got).SequenceEqual([PingKind.Caution]) && got.OfType<GestureAction.Show>().Any()),
            ("Esc cancels", Trigger.HoldCtrlAltShift, () =>
            {
                Keys(false, LControl, LAlt, LShift); Thread.Sleep(350);
                Keys(false, Escape); Keys(true, Escape);
                Keys(true, LShift, LAlt, LControl);
            }, got => !Commits(got).Any() && got.OfType<GestureAction.Hide>().Any()),
            ("Tap confirms once", Trigger.HoldCtrlAltShift, () =>
            {
                Keys(false, LControl, LAlt, LShift); Thread.Sleep(350);
                MoveTo(cx + 120, cy); Thread.Sleep(80);
                Click(); Thread.Sleep(50);
                Keys(true, LShift, LAlt, LControl);
            }, got => Commits(got).SequenceEqual([PingKind.OnMyWay])),
            ("Alt-click sends a Ping", Trigger.AltClick, () =>
            {
                Keys(false, LAlt); Click(); Keys(true, LAlt);
            }, got => Commits(got).SequenceEqual([PingKind.Regular])),
            ("Alt-hold, drag left, release", Trigger.AltClick, () =>
            {
                Keys(false, LAlt);
                Send(Mouse(MOUSEEVENTF_LEFTDOWN)); Thread.Sleep(350);
                MoveTo(cx - 120, cy); Thread.Sleep(80);
                Send(Mouse(MOUSEEVENTF_LEFTUP));
                Keys(true, LAlt);
            }, got => Commits(got).SequenceEqual([PingKind.EnemyWard])),
            ("Ctrl+Alt-click sends a Warning", Trigger.AltClick, () =>
            {
                Keys(false, LControl, LAlt); Click(); Keys(true, LAlt, LControl);
            }, got => Commits(got).SequenceEqual([PingKind.Warning])),
        };

        foreach (var (name, trigger, steps, expect) in scenarios)
        {
            if (!input.Start(trigger, 1)) { Console.WriteLine("SKIP hooks could not be installed"); return 0; }
            actions.Clear();
            bool injected = await Task.Run(() => MoveTo(cx, cy));
            if (!injected) { input.Stop(); Console.WriteLine("SKIP input injection is not available on this desktop"); return 0; }
            await Task.Delay(100);
            await Task.Run(steps);
            await Task.Delay(250);
            input.Stop();
            var got = actions.ToList();
            bool ok = expect(got);
            if (!ok) failures++;
            Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}{(ok ? "" : ": " + string.Join(", ", got))}");
        }
        Console.WriteLine($"{scenarios.Length} input scenarios, {failures} failures");
        return failures == 0 ? 0 : 1;
    }

    static IEnumerable<PingKind> Commits(List<GestureAction> actions) => actions.OfType<GestureAction.Commit>().Select(c => c.Kind);
}
