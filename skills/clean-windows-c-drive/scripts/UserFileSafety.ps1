Set-StrictMode -Version 2

function Get-ApprovedCDriveUserRoots {
    $profile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $candidates = @(
        (Join-Path $profile 'Downloads'),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::MyPictures),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::MyVideos),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::MyMusic)
    )

    @($candidates | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and
        (Test-Path -LiteralPath $_ -PathType Container) -and
        ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($_)) -ieq 'C:\')
    } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique)
}

function Test-IsChildPath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Candidate)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    return $candidateFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Test-IsApprovedCDriveUserFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $full = [IO.Path]::GetFullPath($Path)
    $inside = @((Get-ApprovedCDriveUserRoots) | Where-Object { Test-IsChildPath -Root $_ -Candidate $full }).Count -gt 0
    if (-not $inside) { return $false }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    $blocked = [IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Offline -bor [IO.FileAttributes]::System
    return (($item.Attributes -band $blocked) -eq 0)
}

function Get-CDriveUserFileCategory {
    param([Parameter(Mandatory)][string]$Path)
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -in @('.jpg','.jpeg','.png','.gif','.bmp','.webp','.heic','.raw')) { return '图片' }
    if ($extension -in @('.mp4','.mkv','.mov','.avi','.wmv','.flv','.webm','.m4v')) { return '视频' }
    if ($extension -in @('.mp3','.wav','.flac','.aac','.m4a','.ogg','.wma')) { return '音频' }
    if ($extension -in @('.zip','.7z','.rar','.tar','.gz','.iso','.img','.exe','.msi','.msix','.appx')) { return '压缩包与安装包' }
    if ($extension -in @('.doc','.docx','.xls','.xlsx','.ppt','.pptx','.pdf','.txt','.md')) { return '文档' }
    return '其他'
}

function Get-SafeCDriveUserFiles {
    param([int]$MaximumFiles = 200000)
    $found = 0
    foreach ($root in Get-ApprovedCDriveUserRoots) {
        $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
        if (-not $rootItem -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $pending = [System.Collections.Generic.Stack[string]]::new()
        $pending.Push($root)
        while ($pending.Count -gt 0 -and $found -lt $MaximumFiles) {
            $current = $pending.Pop()
            foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
                if ($item.PSIsContainer) {
                    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $pending.Push($item.FullName) }
                    continue
                }
                $blocked = [IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Offline -bor [IO.FileAttributes]::System
                if (($item.Attributes -band $blocked) -ne 0) { continue }
                $found++
                $item
                if ($found -ge $MaximumFiles) { break }
            }
        }
    }
}
