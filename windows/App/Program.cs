using System;
using System.Threading;
using System.Windows;

namespace DotaPing;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        // Standard controls in the Windows 11 Fluent style, following the system light or dark setting.
        app.ThemeMode = ThemeMode.System;
        if (args.Length > 0 && args[0].StartsWith("--", StringComparison.Ordinal)) return Diagnostics.Run(app, args);

        using var instance = new Mutex(true, @"Local\DotaPing.SingleInstance", out bool first);
        if (!first) return 0;
        var controller = new AppController(app.Dispatcher, Settings.Load(), persist: true);
        app.Startup += (_, _) => controller.Start();
        return app.Run();
    }
}
