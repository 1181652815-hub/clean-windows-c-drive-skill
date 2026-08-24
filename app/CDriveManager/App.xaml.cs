using System.IO;
using System.Text.Json;
using System.Windows;

namespace CDriveManager;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        DispatcherUnhandledException += (_, args) =>
        {
            MessageBox.Show(args.Exception.Message, "程序异常", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };

        if (e.Args.Length >= 2 && e.Args[0].Equals("--smoke-test", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var bridge = new PowerShellBridge();
                bridge.EnsureRuntime();
                var window = new MainWindow();
                window.AssertResultTableBindings();
                window.Close();
                var result = new
                {
                    Status = "PASS",
                    Product = "C盘空间管理",
                    Modules = new[] { "垃圾清理", "查找大文件", "重复文件" },
                    ResultTableBindings = "PASS",
                    Runtime = bridge.RuntimeDirectory
                };
                File.WriteAllText(e.Args[1], JsonSerializer.Serialize(result, JsonOptions.Default));
                Shutdown(0);
            }
            catch (Exception ex)
            {
                File.WriteAllText(e.Args[1], JsonSerializer.Serialize(new { Status = "FAIL", Error = ex.Message }, JsonOptions.Default));
                Shutdown(1);
            }
            return;
        }

        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }
}
