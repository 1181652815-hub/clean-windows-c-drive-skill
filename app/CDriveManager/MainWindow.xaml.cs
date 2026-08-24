using System.Collections.ObjectModel;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;

namespace CDriveManager;

public partial class MainWindow : Window
{
    private readonly PowerShellBridge _bridge = new();
    private JunkSelection? _lastJunkSelection;
    private JunkResponse? _lastJunkPreview;

    internal ObservableCollection<FileCandidate> LargeItems { get; } = [];
    internal ObservableCollection<FileCandidate> DuplicateItems { get; } = [];

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;
        ShowPanel("Junk");
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        await RefreshHealthAsync();
    }

    private async Task RefreshHealthAsync()
    {
        try
        {
            StatusText.Text = "正在执行只读健康检测…";
            var health = await _bridge.RunAsync<HealthResponse>(new { Action = "Health" });
            var usedPercent = Math.Clamp(100 - health.Volume.FreePercent, 0, 100);
            DriveSummary.Text = $"总容量 {health.Volume.TotalGiB:0.0} GB｜可用 {health.Volume.FreeGiB:0.0} GB";
            DriveUsageBar.Value = usedPercent;
            DriveUsageText.Text = $"{usedPercent:0.0}% 已用";
            DriveUsageBar.Foreground = usedPercent >= 90
                ? new SolidColorBrush(Color.FromRgb(224, 58, 68))
                : usedPercent >= 80
                    ? new SolidColorBrush(Color.FromRgb(240, 146, 32))
                    : new SolidColorBrush(Color.FromRgb(47, 91, 255));
            HealthText.Text = $"健康状态：{HealthChinese(health.Overall)}｜检测覆盖：{CoverageChinese(health.Coverage)}";
            StatusText.Text = "健康检测完成｜所有结果仅代表当前状态";
        }
        catch (Exception ex)
        {
            HealthText.Text = "健康状态：读取失败";
            StatusText.Text = "健康检测未完成";
            MessageBox.Show(ex.Message, "健康检测失败", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static string HealthChinese(string value) => value switch
    {
        "Healthy" => "健康",
        "Attention" => "需要注意",
        "Critical" => "严重",
        _ => "未知"
    };

    private static string CoverageChinese(string value) => value == "Full" ? "完整" : "部分";

    private void ShowPanel(string panel)
    {
        JunkPanel.Visibility = panel == "Junk" ? Visibility.Visible : Visibility.Collapsed;
        LargePanel.Visibility = panel == "Large" ? Visibility.Visible : Visibility.Collapsed;
        DuplicatePanel.Visibility = panel == "Duplicate" ? Visibility.Visible : Visibility.Collapsed;
        NavJunk.Background = panel == "Junk" ? new SolidColorBrush(Color.FromRgb(235, 240, 255)) : Brushes.Transparent;
        NavLarge.Background = panel == "Large" ? new SolidColorBrush(Color.FromRgb(235, 240, 255)) : Brushes.Transparent;
        NavDuplicate.Background = panel == "Duplicate" ? new SolidColorBrush(Color.FromRgb(235, 240, 255)) : Brushes.Transparent;
    }

    private void NavJunk_Click(object sender, RoutedEventArgs e) => ShowPanel("Junk");
    private void NavLarge_Click(object sender, RoutedEventArgs e) => ShowPanel("Large");
    private void NavDuplicate_Click(object sender, RoutedEventArgs e) => ShowPanel("Duplicate");

    private JunkSelection ReadJunkSelection()
    {
        var categories = new List<string>();
        if (JunkTemp.IsChecked == true) categories.Add("UserTemp");
        if (JunkShader.IsChecked == true) categories.Add("DirectXShaderCache");
        if (JunkBrowser.IsChecked == true) { categories.Add("ChromeCache"); categories.Add("EdgeCache"); }
        if (JunkCrash.IsChecked == true) categories.Add("CrashDumps");
        if (JunkReports.IsChecked == true) categories.Add("WindowsErrorReports");
        if (JunkInstaller.IsChecked == true) categories.Add("InstallerTemp");
        return new JunkSelection(categories, JunkComponents.IsChecked == true, JunkDelivery.IsChecked == true);
    }

    private async void ScanJunk_Click(object sender, RoutedEventArgs e)
    {
        var selection = ReadJunkSelection();
        if (selection.Categories.Count == 0 && !selection.IncludeComponentStore && !selection.IncludeDeliveryOptimization)
        {
            MessageBox.Show("请至少选择一个需要检查的小类目。", "没有选择", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        await RunBusyAsync("正在扫描可安全清理的内容…", async () =>
        {
            var result = await _bridge.RunAsync<JunkResponse>(new
            {
                Action = "JunkPreview",
                selection.Categories,
                selection.IncludeComponentStore,
                selection.IncludeDeliveryOptimization
            });
            _lastJunkSelection = selection;
            _lastJunkPreview = result;
            CleanJunkButton.IsEnabled = true;
            var optional = OptionalSummary(result);
            JunkResult.Text =
                $"健康状态：{HealthChinese(result.HealthGate.Overall)}\r\n" +
                $"符合白名单：{result.EligibleFileCount} 个文件\r\n" +
                $"预计可释放：{result.EligibleGiB:0.###} GB\r\n" +
                $"跳过：{result.SkippedCount} 个\r\n{optional}\r\n" +
                "这是扫描预览，尚未删除任何内容。";
            StatusText.Text = "扫描完成｜请核对结果后再清理";
        });
    }

    private static string OptionalSummary(JunkResponse result)
    {
        var lines = new List<string>();
        if (result.ComponentStore.Status != "NotRequested") lines.Add($"Windows 组件：{OptionalChinese(result.ComponentStore.Status)}");
        if (result.DeliveryOptimization.Status != "NotRequested") lines.Add($"传递优化：{OptionalChinese(result.DeliveryOptimization.Status)}");
        return lines.Count == 0 ? "" : string.Join("\r\n", lines) + "\r\n";
    }

    private static string OptionalChinese(string value) => value switch
    {
        "SkippedNeedsAdministrator" => "需要以管理员身份运行",
        "Analyzed" => "分析完成",
        "AvailableForExecute" => "可以执行",
        "Completed" => "完成",
        "UnsupportedOnThisWindowsBuild" => "当前系统不支持",
        "AnalysisFailed" or "Failed" => "失败",
        _ => value
    };

    private async void CleanJunk_Click(object sender, RoutedEventArgs e)
    {
        if (_lastJunkSelection is null || _lastJunkPreview is null) return;
        if (!ReadJunkSelection().IsSameAs(_lastJunkSelection))
        {
            MessageBox.Show("清理选项已改变，请重新扫描。", "需要重新扫描", MessageBoxButton.OK, MessageBoxImage.Information);
            CleanJunkButton.IsEnabled = false;
            return;
        }

        var question = $"将处理刚才扫描到的 {_lastJunkPreview.EligibleFileCount} 个白名单文件，预计约 {_lastJunkPreview.EligibleGiB:0.###} GB。\n\n缓存可能在下次启动软件时重新生成。是否继续？";
        if (MessageBox.Show(question, "确认垃圾清理", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;

        await RunBusyAsync("正在清理已确认的白名单内容…", async () =>
        {
            var selection = _lastJunkSelection;
            var result = await _bridge.RunAsync<JunkResponse>(new
            {
                Action = "JunkExecute",
                selection.Categories,
                selection.IncludeComponentStore,
                selection.IncludeDeliveryOptimization
            });
            JunkResult.Text =
                $"处理完成：{result.EligibleFileCount} 个文件\r\n" +
                $"清理前可用：{result.FreeGiBBefore:0.###} GB\r\n" +
                $"清理后可用：{result.FreeGiBAfter:0.###} GB\r\n" +
                $"实际变化：{result.ActualFreeSpaceChangeGiB:0.###} GB\r\n" +
                $"跳过：{result.SkippedCount} 个";
            CleanJunkButton.IsEnabled = false;
            _lastJunkPreview = null;
            StatusText.Text = "垃圾清理完成";
            await RefreshHealthAsync();
        });
    }

    private async void ScanLarge_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(LargeMinimum.Text, out var minimum) || minimum is < 10 or > 102400)
        {
            MessageBox.Show("最小文件大小必须是 10 到 102400 MB。", "输入有误", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        await RunBusyAsync("正在扫描当前用户的大文件…", async () =>
        {
            var result = await _bridge.RunAsync<LargeScanResponse>(new { Action = "LargeScan", MinimumSizeMB = minimum });
            LargeItems.Clear();
            foreach (var item in result.Items) { item.Selected = false; LargeItems.Add(item); }
            LargeSummary.Text = $"找到 {result.Count} 个文件，共 {result.TotalGiB:0.###} GB。默认未选择，请逐项核对。";
            CleanLargeButton.IsEnabled = result.Count > 0;
            StatusText.Text = "大文件扫描完成";
        });
    }

    private async void ScanDuplicate_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(DuplicateMinimum.Text, out var minimum) || minimum is < 1 or > 102400)
        {
            MessageBox.Show("最小文件大小必须是 1 到 102400 MB。", "输入有误", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        await RunBusyAsync("正在计算文件哈希，这可能需要一些时间…", async () =>
        {
            var result = await _bridge.RunAsync<DuplicateScanResponse>(new { Action = "DuplicateScan", MinimumSizeMB = minimum });
            DuplicateItems.Clear();
            foreach (var item in result.Items) { item.Selected = false; DuplicateItems.Add(item); }
            var limit = result.HashLimitReached ? " 已达到本次哈希上限，可提高最小文件大小后重扫。" : "";
            DuplicateSummary.Text = $"找到 {result.DuplicateGroupCount} 组、{result.DuplicateFileCount} 个重复文件；最多可释放约 {result.PotentialReclaimGiB:0.###} GB。默认未选择。{limit}";
            CleanDuplicateButton.IsEnabled = result.DuplicateFileCount > 0;
            StatusText.Text = "重复文件扫描完成";
        });
    }

    private async void CleanLarge_Click(object sender, RoutedEventArgs e) => await CleanupSelectedAsync("LargeFiles", LargeItems);
    private async void CleanDuplicate_Click(object sender, RoutedEventArgs e) => await CleanupSelectedAsync("Duplicates", DuplicateItems);

    private async Task CleanupSelectedAsync(string type, IReadOnlyCollection<FileCandidate> allItems)
    {
        var selected = allItems.Where(item => item.Selected).ToList();
        if (selected.Count == 0)
        {
            MessageBox.Show("请先勾选要处理的文件。", "没有选择", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        if (type == "Duplicates")
        {
            var invalidGroup = allItems.GroupBy(item => item.Group).FirstOrDefault(group => group.All(item => item.Selected));
            if (invalidGroup is not null)
            {
                MessageBox.Show($"重复组 {invalidGroup.Key} 必须至少保留一个文件。", "不能全部删除", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
        }

        await RunBusyAsync("正在重新校验所选文件…", async () =>
        {
            var manifestPath = await CreateManifestAsync(type, selected, allItems);
            var preview = await _bridge.RunAsync<UserCleanupResponse>(new { Action = "UserCleanupPreview", ManifestPath = manifestPath });
            if (preview.AcceptedCount == 0)
                throw new InvalidOperationException("所选文件在重新校验后均不符合安全处理条件。");

            var question = $"将把 {preview.AcceptedCount} 个文件（约 {preview.AcceptedGiB:0.###} GB）移至 Windows 回收站。\n\n文件可在清空回收站前恢复。是否继续？";
            if (MessageBox.Show(question, "确认移至回收站", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            {
                StatusText.Text = "已取消处理";
                return;
            }

            var result = await _bridge.RunAsync<UserCleanupResponse>(new { Action = "UserCleanupExecute", ManifestPath = manifestPath });
            MessageBox.Show($"已移至回收站：{result.AcceptedCount} 个\n跳过：{result.SkippedCount} 个", "处理完成", MessageBoxButton.OK, MessageBoxImage.Information);
            foreach (var item in selected.Where(item => !File.Exists(item.Path)).ToList())
            {
                if (type == "LargeFiles") LargeItems.Remove(item); else DuplicateItems.Remove(item);
            }
            StatusText.Text = $"处理完成｜{result.AcceptedCount} 个文件已进入回收站";
            await RefreshHealthAsync();
        });
    }

    private static async Task<string> CreateManifestAsync(string type, IReadOnlyCollection<FileCandidate> selected, IReadOnlyCollection<FileCandidate> allItems)
    {
        var manifest = new CleanupManifest { Type = type };
        foreach (var item in selected)
        {
            if (!File.Exists(item.Path)) throw new FileNotFoundException("文件在扫描后已不存在。", item.Path);
            await using var stream = new FileStream(item.Path, FileMode.Open, FileAccess.Read, FileShare.Read, 1024 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
            var hash = item.Sha256 ?? Convert.ToHexString(await SHA256.HashDataAsync(stream));
            manifest.Items.Add(new ManifestItem { Path = item.Path, Size = item.Size, Sha256 = hash, Group = item.Group });
        }

        if (type == "Duplicates")
        {
            foreach (var group in selected.Select(item => item.Group).Where(value => value is not null).Distinct())
            {
                manifest.Groups.Add(new ManifestGroup
                {
                    Group = group!,
                    MemberPaths = allItems.Where(item => item.Group == group).Select(item => item.Path).ToList()
                });
            }
        }

        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CDriveManager", "manifests");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, $"{type}-{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(path, JsonSerializer.Serialize(manifest, JsonOptions.Default));
        return path;
    }

    private async Task RunBusyAsync(string message, Func<Task> operation)
    {
        try
        {
            IsEnabled = false;
            StatusText.Text = message;
            await operation();
        }
        catch (Exception ex)
        {
            StatusText.Text = "操作未完成";
            MessageBox.Show(ex.Message, "操作未完成", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsEnabled = true;
        }
    }

    private sealed class JunkSelection(IReadOnlyList<string> categories, bool includeComponentStore, bool includeDeliveryOptimization)
    {
        public IReadOnlyList<string> Categories { get; } = categories;
        public bool IncludeComponentStore { get; } = includeComponentStore;
        public bool IncludeDeliveryOptimization { get; } = includeDeliveryOptimization;

        public bool IsSameAs(JunkSelection? other) => other is not null &&
            IncludeComponentStore == other.IncludeComponentStore &&
            IncludeDeliveryOptimization == other.IncludeDeliveryOptimization &&
            Categories.SequenceEqual(other.Categories, StringComparer.Ordinal);
    }
}
