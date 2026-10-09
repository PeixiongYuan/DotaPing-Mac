using System;
using System.Windows;
using System.Windows.Threading;
using DotaPing.Core;
using Trigger = DotaPing.Core.Trigger;
using Microsoft.Win32;

namespace DotaPing;

/// <summary>App state shared by the tray icon and the settings window.</summary>
sealed class AppController
{
    public enum State { Off, Ready, InputUnavailable }

    public event Action? Changed;
    public GlobalInput Input { get; }
    public OverlayController Overlay { get; } = new();
    public SoundPlayer Sound { get; } = new();
    public bool IsEnabled { get; private set; }
    public State Status { get; private set; } = State.Off;
    readonly Settings settings;
    readonly bool persist;
    Tray? tray;
    SettingsWindow? window;

    public AppController(Dispatcher dispatcher, Settings settings, bool persist)
    {
        this.settings = settings; this.persist = persist;
        Input = new GlobalInput(dispatcher);
        Input.ActionReceived += Handle;
        Sound.UseGameSounds = UseGameSounds;
    }

    public Trigger Trigger
    {
        get => Enum.TryParse<Trigger>(settings.Trigger, out var t) ? t : Trigger.HoldCtrlAltShift;
        set { settings.Trigger = value.ToString(); Save(); Restart(); }
    }
    public PlayerColor Player
    {
        get => Enum.IsDefined((PlayerColor)settings.PlayerColor) ? (PlayerColor)settings.PlayerColor : PlayerColor.Blue;
        set { settings.PlayerColor = (int)value; Save(); Changed?.Invoke(); }
    }
    public Language Language
    {
        get => Languages.FromCode(settings.Language);
        set { settings.Language = value.Code(); Save(); Changed?.Invoke(); }
    }
    public double Volume
    {
        get => Math.Clamp(settings.Volume, 0, 1);
        set { settings.Volume = value; Save(); }
    }
    public double Scale
    {
        get => Math.Clamp(settings.Scale, 0.75, 1.5);
        set { settings.Scale = value; Save(); Restart(); }
    }
    public bool UseGameSounds
    {
        get => settings.Sounds != "synthesized";
        set { settings.Sounds = value ? "game" : "synthesized"; Sound.UseGameSounds = value; Save(); Changed?.Invoke(); }
    }

    public string Message => Status switch
    {
        State.Ready => Trigger.Ready(Language),
        State.InputUnavailable => Language.Pick("Couldn't install the keyboard and mouse hooks.", "无法安装键盘和鼠标钩子。"),
        _ => Language.Pick("Off. You can still preview pings below.", "已关闭。下方仍可预览。"),
    };

    public void Start()
    {
        tray = new Tray(this);
        SystemEvents.DisplaySettingsChanged += (_, _) => CancelEffects();
        SystemEvents.SessionSwitch += (_, _) => CancelEffects();
        SystemEvents.PowerModeChanged += (_, _) => CancelEffects();
        if (settings.Enabled) SetEnabled(true);
        ShowSettings();
    }

    public void SetEnabled(bool value)
    {
        CancelEffects();
        if (value && Input.Start(Trigger, Scale)) { IsEnabled = true; Status = State.Ready; }
        else
        {
            Input.Stop();
            IsEnabled = false;
            Status = value ? State.InputUnavailable : State.Off;
        }
        settings.Enabled = IsEnabled; Save();
        Changed?.Invoke();
    }

    public void ShowSettings()
    {
        window ??= new SettingsWindow(this);
        window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate();
    }

    public void CancelEffects() { Input.CancelCurrent(); Overlay.Clear(); Sound.StopAll(); }

    public void Quit()
    {
        Input.Stop(); Overlay.Clear(); Sound.StopAll();
        tray?.Dispose();
        Application.Current.Shutdown();
    }

    void Restart()
    {
        CancelEffects();
        if (IsEnabled) SetEnabled(true); else Changed?.Invoke();
    }

    void Save() { if (persist) settings.Save(); }

    void Handle(GestureAction action)
    {
        if (!IsEnabled) return;
        switch (action)
        {
            case GestureAction.Show show:
                Input.SetWheelCenter(Overlay.ShowWheel(GlobalInput.ToPixel(show.Point), Scale, Player, Language));
                break;
            case GestureAction.Hover hover:
                Overlay.Select(hover.Kind, hover.Angle);
                break;
            case GestureAction.Hide:
                Overlay.HideWheel(false);
                break;
            case GestureAction.Dismiss:
                Overlay.HideWheel();
                break;
            case GestureAction.Commit commit:
                Overlay.ShowPing(commit.Kind, GlobalInput.ToPixel(commit.Point), Scale, Player, Language);
                Sound.Play(commit.Kind, Volume);
                break;
        }
    }
}
