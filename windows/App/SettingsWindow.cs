using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using DotaPing.Core;
using Trigger = DotaPing.Core.Trigger;

namespace DotaPing;

/// <summary>Settings window, built in code. Standard controls in the system theme (Fluent on Windows 11).</summary>
sealed class SettingsWindow : Window
{
    readonly AppController app;
    readonly CheckBox enable = new() { VerticalAlignment = VerticalAlignment.Center };
    readonly TextBlock enableLabel = new(), status = Secondary(), usage = Secondary(), footer = Secondary(), placeholder = Secondary();
    readonly TextBlock triggerLabel = RowLabel(), colorLabel = RowLabel(), sizeLabel = RowLabel(), volumeLabel = RowLabel(), soundsLabel = RowLabel(), languageLabel = RowLabel(), previewHeading = new();
    readonly ComboBox trigger = Combo(), sounds = Combo(), language = Combo();
    readonly Slider size = new() { Minimum = 0.75, Maximum = 1.5, TickFrequency = 0.05, IsSnapToTickEnabled = true, Width = 220, VerticalAlignment = VerticalAlignment.Center };
    readonly Slider volume = new() { Minimum = 0, Maximum = 1, Width = 220, VerticalAlignment = VerticalAlignment.Center };
    readonly StackPanel swatches = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    readonly Grid previewStage = new() { ClipToBounds = true };
    readonly Border previewFrame;
    readonly UniformGrid pingButtons = new() { Columns = 3, Margin = new Thickness(0, 8, 0, 0) };
    readonly Button customSounds = new(), quit = new();
    readonly Dictionary<PingKind, Button> buttons = new();
    EffectVisual? preview;
    bool updating;

    public SettingsWindow(AppController app)
    {
        this.app = app;
        Title = "DotaPing";
        Width = 540; Height = 780; MinWidth = 480; MinHeight = 520;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DotaPing.ico"))
            if (stream is not null) Icon = BitmapFrame.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);

        enable.Content = enableLabel;
        enable.Click += (_, _) => app.SetEnabled(enable.IsChecked == true);
        trigger.SelectionChanged += (_, _) => { if (!updating && trigger.SelectedIndex >= 0) app.Trigger = Core.Triggers.All[trigger.SelectedIndex]; };
        sounds.SelectionChanged += (_, _) => { if (!updating && sounds.SelectedIndex >= 0) app.UseGameSounds = sounds.SelectedIndex == 0; };
        language.SelectionChanged += (_, _) => { if (!updating && language.SelectedIndex >= 0) app.Language = (Core.Language)language.SelectedIndex; };
        size.ValueChanged += (_, _) => { if (!updating) { app.Scale = size.Value; ResizePreview(); } };
        volume.ValueChanged += (_, _) => { if (!updating) app.Volume = volume.Value; };
        customSounds.Click += (_, _) => SoundPlayer.RevealCustomFolder();
        quit.Click += (_, _) => app.Quit();
        foreach (var color in PlayerColors.All) swatches.Children.Add(Swatch(color));
        foreach (var kind in Pings.Wheel.Append(PingKind.Regular))
        {
            var button = new Button { HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 6, 6), Padding = new Thickness(10, 6, 10, 6) };
            button.Click += (_, _) => Preview(kind);
            buttons[kind] = button;
            pingButtons.Children.Add(button);
        }
        placeholder.HorizontalAlignment = HorizontalAlignment.Center; placeholder.VerticalAlignment = VerticalAlignment.Center;
        previewStage.Children.Add(placeholder);
        previewFrame = new Border { Background = new SolidColorBrush(Color.FromRgb(23, 23, 23)), CornerRadius = new CornerRadius(6), Child = previewStage };
        previewHeading.FontWeight = FontWeights.SemiBold;
        previewHeading.Margin = new Thickness(4, 4, 0, 8);

        var bottom = new DockPanel { LastChildFill = false };
        DockPanel.SetDock(quit, Dock.Right);
        customSounds.Padding = quit.Padding = new Thickness(14, 5, 14, 5);
        bottom.Children.Add(customSounds);
        bottom.Children.Add(quit);
        footer.Margin = new Thickness(4, 8, 4, 0);

        var root = new StackPanel { Margin = new Thickness(20, 16, 20, 20) };
        root.Children.Add(Card(new StackPanel { Children = { enable, Indented(status) } }));
        root.Children.Add(Card(Row(triggerLabel, trigger)));
        usage.Margin = new Thickness(4, -6, 4, 14);
        root.Children.Add(usage);
        root.Children.Add(Card(Row(colorLabel, swatches), Row(sizeLabel, size), Row(volumeLabel, volume), Row(soundsLabel, sounds), Row(languageLabel, language)));
        root.Children.Add(previewHeading);
        root.Children.Add(Card(new StackPanel { Children = { previewFrame, pingButtons } }));
        root.Children.Add(Card(bottom));
        root.Children.Add(footer);
        Content = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };

        app.Changed += Refresh;
        Refresh();
        ResizePreview();
    }

    /// <summary>Closing only hides the window; DotaPing keeps running in the notification area.</summary>
    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        StopPreview();
        Hide();
    }

    void Refresh()
    {
        updating = true;
        var l = app.Language;
        enableLabel.Text = l.Pick("Enable DotaPing", "启用 DotaPing");
        enable.IsChecked = app.IsEnabled;
        status.Text = app.Message;
        triggerLabel.Text = l.Pick("Trigger", "触发");
        Fill(trigger, Core.Triggers.All.Select(t => t.Title(l)), Core.Triggers.All.ToList().IndexOf(app.Trigger));
        usage.Text = app.Trigger.Usage(l) + " " + l.Pick("Windows does not pass input to DotaPing while an administrator window is in front.",
                                                          "以管理员身份运行的窗口在前台时，Windows 不会把输入交给 DotaPing。");
        colorLabel.Text = l.Pick("Player Color", "玩家颜色");
        foreach (var (child, color) in swatches.Children.OfType<Border>().Zip(PlayerColors.All))
        {
            child.BorderBrush = color == app.Player ? (Brush)FindResourceOrDefault("TextFillColorPrimaryBrush", Brushes.Gray) : Brushes.Transparent;
            child.ToolTip = color.Title(l);
        }
        sizeLabel.Text = l.Pick("Size", "大小");
        size.Value = app.Scale;
        volumeLabel.Text = l.Pick("Volume", "音量");
        volume.Value = app.Volume;
        soundsLabel.Text = l.Pick("Sounds", "音效");
        Fill(sounds, [l.Pick("Dota 2", "Dota 2 原声"), l.Pick("Synthesized", "合成音效")], app.UseGameSounds ? 0 : 1);
        languageLabel.Text = l.Pick("Language", "语言");
        Fill(language, [Core.Language.English.Name(), Core.Language.Chinese.Name()], (int)l);
        previewHeading.Text = l.Pick("Preview", "预览");
        placeholder.Text = l.Pick("Click a ping below to preview it", "点下方信号预览");
        placeholder.Foreground = new SolidColorBrush(Color.FromRgb(128, 128, 128));
        foreach (var (kind, button) in buttons)
        {
            var icon = new Path { Data = Art.Glyph(kind), Stretch = Stretch.Uniform, Width = 16, Height = 16, Margin = new Thickness(0, 0, 8, 0) };
            icon.SetBinding(Shape.FillProperty, new Binding(nameof(Foreground)) { Source = button });
            button.Content = new StackPanel { Orientation = Orientation.Horizontal, Children = { icon, new TextBlock { Text = kind.Title(l), VerticalAlignment = VerticalAlignment.Center } } };
            button.ToolTip = kind.Chat(l) ?? kind.Title(l);
        }
        customSounds.Content = l.Pick("Custom Sounds…", "自定义音效…");
        customSounds.ToolTip = l.Pick("Add a file with the same name to replace a sound: ", "放入同名文件即可替换：") + string.Join(l.Pick(", ", "、"), SoundSynth.Names);
        quit.Content = l.Pick("Quit", "退出");
        footer.Text = l.Pick("Not affiliated with Valve. Dota 2 sounds © Valve Corporation.", "非 Valve 官方产品。Dota 2 音效版权归 Valve 所有。");
        updating = false;
    }

    void Preview(PingKind kind)
    {
        StopPreview();
        app.Sound.Play(kind, app.Volume);
        preview = new EffectVisual(kind, app.Player, app.Language, app.Scale);
        preview.Finished += StopPreview;
        previewStage.Children.Add(preview);
        placeholder.Visibility = Visibility.Hidden;
        preview.Start();
    }

    void StopPreview()
    {
        if (preview is null) return;
        preview.Stop();
        previewStage.Children.Remove(preview);
        preview = null;
        placeholder.Visibility = Visibility.Visible;
    }

    void ResizePreview() => previewFrame.Height = Math.Max(140, 140 * app.Scale);

    object FindResourceOrDefault(string key, object fallback) => TryFindResource(key) ?? fallback;

    Border Swatch(PlayerColor color)
    {
        var swatch = new Border
        {
            Width = 22, Height = 22, CornerRadius = new CornerRadius(11), BorderThickness = new Thickness(1.5), Padding = new Thickness(2),
            Margin = new Thickness(color == PlayerColor.Pink ? 10 : 1, 0, 1, 0), Cursor = Cursors.Hand, Background = Brushes.Transparent,
            Child = new Ellipse { Fill = new SolidColorBrush(Art.ToColor(color.Rgb())), Stroke = new SolidColorBrush(Color.FromArgb(40, 128, 128, 128)), StrokeThickness = 0.5 },
        };
        swatch.MouseLeftButtonUp += (_, _) => app.Player = color;
        System.Windows.Automation.AutomationProperties.SetName(swatch, color.Title(Core.Language.English));
        return swatch;
    }

    static void Fill(ComboBox box, IEnumerable<string> items, int selected)
    {
        var list = items.ToList();
        if (!box.Items.Cast<string>().SequenceEqual(list))
        {
            box.Items.Clear();
            foreach (var item in list) box.Items.Add(item);
        }
        box.SelectedIndex = selected;
    }

    static TextBlock RowLabel() => new() { VerticalAlignment = VerticalAlignment.Center };
    static TextBlock Secondary() => new() { TextWrapping = TextWrapping.Wrap, FontSize = 12, Opacity = 0.7 };
    static ComboBox Combo() => new() { MinWidth = 220, VerticalAlignment = VerticalAlignment.Center };
    static FrameworkElement Indented(FrameworkElement element) { element.Margin = new Thickness(26, 2, 0, 0); return element; }

    static Grid Row(FrameworkElement label, FrameworkElement control)
    {
        var grid = new Grid { MinHeight = 40 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(control, 1);
        control.HorizontalAlignment = HorizontalAlignment.Right;
        grid.Children.Add(label);
        grid.Children.Add(control);
        return grid;
    }

    /// <summary>A rounded group, like the cards in Windows 11 Settings; rows are separated by hairlines.</summary>
    static Border Card(params FrameworkElement[] rows)
    {
        var panel = new StackPanel();
        for (int i = 0; i < rows.Length; i++)
        {
            if (i > 0) panel.Children.Add(new Border { Height = 1, Margin = new Thickness(0, 4, 0, 4), Background = new SolidColorBrush(Color.FromArgb(28, 128, 128, 128)) });
            panel.Children.Add(rows[i]);
        }
        var card = new Border
        {
            CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1), Padding = new Thickness(16, 10, 16, 10),
            Margin = new Thickness(0, 0, 0, 12), Child = panel,
            BorderBrush = new SolidColorBrush(Color.FromArgb(36, 128, 128, 128)),
        };
        card.SetResourceReference(Border.BackgroundProperty, "CardBackgroundFillColorDefaultBrush");
        return card;
    }
}
