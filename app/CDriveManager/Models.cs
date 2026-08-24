using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace CDriveManager;

internal sealed class HealthResponse
{
    public string Overall { get; set; } = "Unknown";
    public string Coverage { get; set; } = "Partial";
    public VolumeInfo Volume { get; set; } = new();
}

internal sealed class VolumeInfo
{
    public double TotalGiB { get; set; }
    public double FreeGiB { get; set; }
    public double FreePercent { get; set; }
}

internal sealed class JunkResponse
{
    public string Mode { get; set; } = "Preview";
    public HealthGate HealthGate { get; set; } = new();
    public int EligibleFileCount { get; set; }
    public double EligibleGiB { get; set; }
    public int SkippedCount { get; set; }
    public double FreeGiBBefore { get; set; }
    public double FreeGiBAfter { get; set; }
    public double ActualFreeSpaceChangeGiB { get; set; }
    public OptionalAction ComponentStore { get; set; } = new();
    public OptionalAction DeliveryOptimization { get; set; } = new();
}

internal sealed class HealthGate { public string Overall { get; set; } = "Unknown"; }
internal sealed class OptionalAction { public string Status { get; set; } = "NotRequested"; }

internal sealed class LargeScanResponse
{
    public int Count { get; set; }
    public double TotalGiB { get; set; }
    public List<FileCandidate> Items { get; set; } = [];
}

internal sealed class DuplicateScanResponse
{
    public int DuplicateGroupCount { get; set; }
    public int DuplicateFileCount { get; set; }
    public double PotentialReclaimGiB { get; set; }
    public bool HashLimitReached { get; set; }
    public List<FileCandidate> Items { get; set; } = [];
}

internal sealed class UserCleanupResponse
{
    public int AcceptedCount { get; set; }
    public double AcceptedGiB { get; set; }
    public int SkippedCount { get; set; }
}

internal sealed class FileCandidate : INotifyPropertyChanged
{
    private bool _selected;
    public bool Selected
    {
        get => _selected;
        set { if (_selected == value) return; _selected = value; OnPropertyChanged(); }
    }
    public string? Group { get; set; }
    public string Category { get; set; } = "其他";
    public double SizeGiB { get; set; }
    public long Size { get; set; }
    public string? Sha256 { get; set; }
    public string LastWriteTime { get; set; } = "";
    public string Path { get; set; } = "";

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

internal sealed class CleanupManifest
{
    public int Version { get; set; } = 1;
    public string Type { get; set; } = "LargeFiles";
    public string CreatedAt { get; set; } = DateTimeOffset.Now.ToString("O");
    public List<ManifestItem> Items { get; set; } = [];
    public List<ManifestGroup> Groups { get; set; } = [];
}

internal sealed class ManifestItem
{
    public string Path { get; set; } = "";
    public long Size { get; set; }
    public string Sha256 { get; set; } = "";
    public string? Group { get; set; }
}

internal sealed class ManifestGroup
{
    public string Group { get; set; } = "";
    public List<string> MemberPaths { get; set; } = [];
}
