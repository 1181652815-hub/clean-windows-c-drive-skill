using System.Diagnostics;
using System.Reflection;
using System.Text;
using System.Text.Json;

namespace CDriveManager;

internal sealed class PowerShellBridge
{
    private const string ResourcePrefix = "CDriveManager.Scripts.";
    public string RuntimeDirectory { get; }
    private string ScriptsDirectory => Path.Combine(RuntimeDirectory, "scripts");

    public PowerShellBridge()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "3.0.0";
        RuntimeDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CDriveManager", "runtime", version);
    }

    public void EnsureRuntime()
    {
        Directory.CreateDirectory(ScriptsDirectory);
        var assembly = Assembly.GetExecutingAssembly();
        var resources = assembly.GetManifestResourceNames()
            .Where(name => name.StartsWith(ResourcePrefix, StringComparison.Ordinal) && name.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
            .ToArray();
        if (resources.Length < 6)
            throw new InvalidOperationException("程序内置的安全脚本不完整，请重新下载官方发布包。");

        foreach (var resource in resources)
        {
            var fileName = resource[ResourcePrefix.Length..];
            var target = Path.Combine(ScriptsDirectory, fileName);
            using var source = assembly.GetManifestResourceStream(resource)
                ?? throw new InvalidOperationException($"无法读取内置资源：{fileName}");
            using var memory = new MemoryStream();
            source.CopyTo(memory);
            var bytes = memory.ToArray();
            if (!File.Exists(target) || !File.ReadAllBytes(target).SequenceEqual(bytes))
                File.WriteAllBytes(target, bytes);
        }
    }

    public async Task<T> RunAsync<T>(object request, CancellationToken cancellationToken = default)
    {
        EnsureRuntime();
        var requestDirectory = Path.Combine(RuntimeDirectory, "requests");
        Directory.CreateDirectory(requestDirectory);
        var requestPath = Path.Combine(requestDirectory, $"request-{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(requestPath, JsonSerializer.Serialize(request, JsonOptions.Default), new UTF8Encoding(false), cancellationToken);

        try
        {
            var bridgePath = Path.Combine(ScriptsDirectory, "Invoke-DesktopBridge.ps1");
            var systemDirectory = Environment.GetFolderPath(Environment.SpecialFolder.System);
            var powershell = Path.Combine(systemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(powershell)) powershell = "powershell.exe";

            var start = new ProcessStartInfo
            {
                FileName = powershell,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            start.ArgumentList.Add("-NoProfile");
            start.ArgumentList.Add("-NonInteractive");
            start.ArgumentList.Add("-ExecutionPolicy");
            start.ArgumentList.Add("Bypass");
            start.ArgumentList.Add("-File");
            start.ArgumentList.Add(bridgePath);
            start.ArgumentList.Add("-PayloadPath");
            start.ArgumentList.Add(requestPath);

            using var process = Process.Start(start) ?? throw new InvalidOperationException("无法启动 Windows PowerShell。 ");
            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken);
            var stdout = await stdoutTask;
            var stderr = await stderrTask;

            if (process.ExitCode != 0)
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(stderr) ? "安全后端执行失败。" : stderr.Trim());
            if (string.IsNullOrWhiteSpace(stdout))
                throw new InvalidOperationException("安全后端没有返回结果。");

            return JsonSerializer.Deserialize<T>(stdout, JsonOptions.Default)
                ?? throw new InvalidOperationException("无法解析安全后端返回的数据。");
        }
        finally
        {
            try { File.Delete(requestPath); } catch { }
        }
    }
}
