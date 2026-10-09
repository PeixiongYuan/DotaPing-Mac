using System;
using System.Reflection;
using DotaPing.Core;
using Forms = System.Windows.Forms;

namespace DotaPing;

/// <summary>Notification-area icon with the same menu as the macOS menu bar item.</summary>
sealed class Tray : IDisposable
{
    readonly AppController app;
    readonly Forms.NotifyIcon icon;
    readonly Forms.ToolStripMenuItem state, enable, settings, quit;

    public Tray(AppController app)
    {
        this.app = app;
        state = new Forms.ToolStripMenuItem { Enabled = false };
        enable = new Forms.ToolStripMenuItem();
        enable.Click += (_, _) => app.SetEnabled(!app.IsEnabled);
        settings = new Forms.ToolStripMenuItem();
        settings.Click += (_, _) => app.ShowSettings();
        quit = new Forms.ToolStripMenuItem();
        quit.Click += (_, _) => app.Quit();
        var menu = new Forms.ContextMenuStrip();
        menu.Items.AddRange([state, enable, settings, new Forms.ToolStripSeparator(), quit]);
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DotaPing.ico");
        icon = new Forms.NotifyIcon
        {
            Icon = stream is null ? System.Drawing.SystemIcons.Application : new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize),
            ContextMenuStrip = menu,
            Visible = true,
        };
        icon.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) app.ShowSettings(); };
        app.Changed += Update;
        Update();
    }

    void Update()
    {
        var l = app.Language;
        string status = app.IsEnabled ? l.Pick("On", "已开启") : l.Pick("Off", "已关闭");
        state.Text = l.Pick($"DotaPing: {status}", $"DotaPing：{status}");
        enable.Text = l.Pick("Enable", "启用");
        enable.Checked = app.IsEnabled;
        settings.Text = l.Pick("Settings…", "设置…");
        quit.Text = l.Pick("Quit DotaPing", "退出 DotaPing");
        icon.Text = state.Text;
    }

    public void Dispose()
    {
        app.Changed -= Update;
        icon.Visible = false;
        icon.Dispose();
    }
}
