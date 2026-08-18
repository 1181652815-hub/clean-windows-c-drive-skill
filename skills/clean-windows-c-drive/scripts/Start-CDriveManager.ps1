[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [string]$ScreenshotPath = '',
    [ValidateSet('Junk','Large','Duplicate')][string]$InitialModule = 'Junk'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="C盘空间管理" Width="1180" Height="760" MinWidth="1000" MinHeight="680"
        WindowStartupLocation="CenterScreen" Background="#F4F7FB" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="FontSize" Value="14"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="18,10"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="MinWidth" Value="76"/>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#2F5BFF"/><Setter Property="Foreground" Value="White"/>
    </Style>
    <Style x:Key="NavButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#26344A"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Margin" Value="12,5"/>
      <Setter Property="Padding" Value="18,14"/>
    </Style>
    <Style TargetType="DataGrid">
      <Setter Property="BorderBrush" Value="#DCE3EE"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/><Setter Property="HorizontalGridLinesBrush" Value="#E8EDF4"/>
      <Setter Property="RowHeight" Value="38"/><Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="CanUserAddRows" Value="False"/><Setter Property="AutoGenerateColumns" Value="False"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="64"/><RowDefinition Height="*"/><RowDefinition Height="36"/></Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#2F5BFF">
      <Grid Margin="24,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="C盘空间管理" Foreground="White" FontSize="22" FontWeight="SemiBold"/>
          <TextBlock Text="  安全清理 · 精确查找 · 可恢复处理" Foreground="#C9D5FF" FontSize="12" VerticalAlignment="Center" Margin="12,4,0,0"/>
        </StackPanel>
        <TextBlock x:Name="TopHealth" Grid.Column="1" Text="正在读取 C 盘状态…" Foreground="White" VerticalAlignment="Center" FontSize="13"/>
      </Grid>
    </Border>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="230"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="White" BorderBrush="#E1E7F0" BorderThickness="0,0,1,0">
        <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <StackPanel Margin="20,22,20,14">
            <TextBlock Text="三个核心模块" FontWeight="SemiBold" FontSize="15" Foreground="#1D2A3B"/>
            <TextBlock Text="先扫描，再选择，后执行" Foreground="#8491A5" FontSize="12" Margin="0,6,0,0"/>
          </StackPanel>
          <StackPanel Grid.Row="1">
            <Button x:Name="NavJunk" Style="{StaticResource NavButton}" Content="01   垃圾清理"/>
            <Button x:Name="NavLarge" Style="{StaticResource NavButton}" Content="02   查找大文件"/>
            <Button x:Name="NavDuplicate" Style="{StaticResource NavButton}" Content="03   重复文件"/>
          </StackPanel>
          <Border Grid.Row="2" Margin="18" Padding="14" Background="#F0F4FF" CornerRadius="6">
            <StackPanel><TextBlock Text="安全范围" FontWeight="SemiBold" Foreground="#2F5BFF"/>
              <TextBlock Text="系统目录、软件配置和云端占位文件不会进入自动处理范围。" TextWrapping="Wrap" Foreground="#5B687A" FontSize="12" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
        </Grid>
      </Border>
      <Grid Grid.Column="1" Margin="24">
        <Grid.RowDefinitions><RowDefinition Height="92"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <Border Background="White" CornerRadius="8" Padding="22,16" BorderBrush="#E1E7F0" BorderThickness="1">
          <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="270"/></Grid.ColumnDefinitions>
            <StackPanel><TextBlock Text="本地磁盘 (C:)" FontSize="17" FontWeight="SemiBold" Foreground="#1D2A3B"/>
              <TextBlock x:Name="DriveSummary" Text="正在读取容量…" Foreground="#69778B" Margin="0,6,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="1" VerticalAlignment="Center">
              <ProgressBar x:Name="DriveBar" Height="10" Minimum="0" Maximum="100" Value="0" Foreground="#2F5BFF" Background="#E6EBF2"/>
              <TextBlock x:Name="DrivePercent" Text="0% 已用" HorizontalAlignment="Right" Foreground="#69778B" Margin="0,6,0,0"/>
            </StackPanel>
          </Grid>
        </Border>

        <Border x:Name="PanelJunk" Grid.Row="1" Background="White" CornerRadius="8" Margin="0,16,0,0" Padding="24" BorderBrush="#E1E7F0" BorderThickness="1">
          <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel><TextBlock Text="垃圾清理" FontSize="21" FontWeight="SemiBold" Foreground="#1D2A3B"/>
                <TextBlock Text="只处理可再生缓存和旧诊断文件，可按类别选择。" Foreground="#7B889B" Margin="0,6,0,0"/></StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="ScanJunk" Style="{StaticResource PrimaryButton}" Content="扫描" Margin="0,0,10,0"/><Button x:Name="CleanJunk" Style="{StaticResource PrimaryButton}" Content="清理已选" IsEnabled="False"/></StackPanel>
            </Grid>
            <UniformGrid Grid.Row="1" Columns="3" Margin="0,24,0,14">
              <CheckBox x:Name="JunkTemp" Content="用户临时文件" IsChecked="True" Margin="0,8"/>
              <CheckBox x:Name="JunkShader" Content="着色器缓存" IsChecked="True" Margin="0,8"/>
              <CheckBox x:Name="JunkBrowser" Content="浏览器纯缓存" IsChecked="True" Margin="0,8"/>
              <CheckBox x:Name="JunkCrash" Content="崩溃转储" IsChecked="True" Margin="0,8"/>
              <CheckBox x:Name="JunkReports" Content="错误报告" IsChecked="True" Margin="0,8"/>
              <CheckBox x:Name="JunkInstaller" Content="安装器临时文件" IsChecked="True" Margin="0,8"/>
              <CheckBox x:Name="JunkComponents" Content="Windows 组件分析" IsChecked="False" Margin="0,8"/>
              <CheckBox x:Name="JunkDelivery" Content="传递优化缓存" IsChecked="False" Margin="0,8"/>
            </UniformGrid>
            <Border Grid.Row="2" Height="1" Background="#E8EDF4"/>
            <TextBox x:Name="JunkResult" Grid.Row="3" Margin="0,16,0,0" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" BorderThickness="0" Background="#F8FAFD" Padding="16" Text="选择类别后点击“扫描”。扫描不会删除任何文件。"/>
          </Grid>
        </Border>

        <Border x:Name="PanelLarge" Grid.Row="1" Background="White" CornerRadius="8" Margin="0,16,0,0" Padding="24" BorderBrush="#E1E7F0" BorderThickness="1" Visibility="Collapsed">
          <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel><TextBlock Text="查找并清理大文件" FontSize="21" FontWeight="SemiBold" Foreground="#1D2A3B"/>
                <TextBlock Text="扫描 C 盘当前用户的桌面、下载、文档、图片、视频和音乐。" Foreground="#7B889B" Margin="0,6,0,0"/></StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><TextBlock Text="最小" VerticalAlignment="Center" Margin="0,0,6,0"/><TextBox x:Name="LargeMinimum" Text="500" Width="60" Padding="5"/><TextBlock Text=" MB" VerticalAlignment="Center" Margin="4,0,12,0"/><Button x:Name="ScanLarge" Style="{StaticResource PrimaryButton}" Content="扫描" Margin="0,0,10,0"/><Button x:Name="CleanLarge" Style="{StaticResource PrimaryButton}" Content="移至回收站" IsEnabled="False"/></StackPanel>
            </Grid>
            <TextBlock x:Name="LargeSummary" Grid.Row="1" Text="支持安装包、镜像、视频、压缩包、文档及其他普通用户文件。默认不选择。" Foreground="#69778B" Margin="0,18,0,12"/>
            <DataGrid x:Name="LargeGrid" Grid.Row="2">
              <DataGrid.Columns><DataGridCheckBoxColumn Header="选择" Binding="{Binding Selected, UpdateSourceTrigger=PropertyChanged}" Width="55"/><DataGridTextColumn Header="类型" Binding="{Binding Category}" Width="120"/><DataGridTextColumn Header="大小 (GB)" Binding="{Binding SizeGiB}" Width="90"/><DataGridTextColumn Header="修改时间" Binding="{Binding LastWriteTime}" Width="140"/><DataGridTextColumn Header="路径" Binding="{Binding Path}" Width="*" MinWidth="300"/></DataGrid.Columns>
            </DataGrid>
          </Grid>
        </Border>

        <Border x:Name="PanelDuplicate" Grid.Row="1" Background="White" CornerRadius="8" Margin="0,16,0,0" Padding="24" BorderBrush="#E1E7F0" BorderThickness="1" Visibility="Collapsed">
          <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel><TextBlock Text="重复文件清理" FontSize="21" FontWeight="SemiBold" Foreground="#1D2A3B"/>
                <TextBlock Text="先比较大小，再用 SHA-256 确认内容完全相同；每组必须保留一份。" Foreground="#7B889B" Margin="0,6,0,0"/></StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><TextBlock Text="最小" VerticalAlignment="Center" Margin="0,0,6,0"/><TextBox x:Name="DuplicateMinimum" Text="10" Width="60" Padding="5"/><TextBlock Text=" MB" VerticalAlignment="Center" Margin="4,0,12,0"/><Button x:Name="ScanDuplicate" Style="{StaticResource PrimaryButton}" Content="扫描" Margin="0,0,10,0"/><Button x:Name="CleanDuplicate" Style="{StaticResource PrimaryButton}" Content="移至回收站" IsEnabled="False"/></StackPanel>
            </Grid>
            <TextBlock x:Name="DuplicateSummary" Grid.Row="1" Text="覆盖图片、视频、音频、文档、压缩包和其他普通用户文件。默认不选择。" Foreground="#69778B" Margin="0,18,0,12"/>
            <DataGrid x:Name="DuplicateGrid" Grid.Row="2">
              <DataGrid.Columns><DataGridCheckBoxColumn Header="选择" Binding="{Binding Selected, UpdateSourceTrigger=PropertyChanged}" Width="55"/><DataGridTextColumn Header="组" Binding="{Binding Group}" Width="65"/><DataGridTextColumn Header="类型" Binding="{Binding Category}" Width="100"/><DataGridTextColumn Header="大小 (GB)" Binding="{Binding SizeGiB}" Width="90"/><DataGridTextColumn Header="修改时间" Binding="{Binding LastWriteTime}" Width="135"/><DataGridTextColumn Header="路径" Binding="{Binding Path}" Width="*" MinWidth="300"/></DataGrid.Columns>
            </DataGrid>
          </Grid>
        </Border>
      </Grid>
    </Grid>
    <Border Grid.Row="2" Background="#EAF0F8" BorderBrush="#DCE3EE" BorderThickness="0,1,0,0">
      <TextBlock x:Name="StatusText" Text="就绪｜所有删除操作均需先扫描并确认" Margin="18,0" VerticalAlignment="Center" Foreground="#617087" FontSize="12"/>
    </Border>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

function Element([string]$name) { $window.FindName($name) }
$panelJunk = Element 'PanelJunk'; $panelLarge = Element 'PanelLarge'; $panelDuplicate = Element 'PanelDuplicate'
$status = Element 'StatusText'; $largeGrid = Element 'LargeGrid'; $duplicateGrid = Element 'DuplicateGrid'
$script:largeItems = @(); $script:duplicateItems = @(); $script:lastJunkPreview = $null

function Get-HealthChinese([string]$value) {
    switch ($value) {
        'Healthy' { '健康' }
        'Attention' { '需要注意' }
        'Critical' { '严重' }
        default { '未知' }
    }
}

function Show-Panel([string]$name) {
    $panelJunk.Visibility = if ($name -eq 'Junk') { 'Visible' } else { 'Collapsed' }
    $panelLarge.Visibility = if ($name -eq 'Large') { 'Visible' } else { 'Collapsed' }
    $panelDuplicate.Visibility = if ($name -eq 'Duplicate') { 'Visible' } else { 'Collapsed' }
}

function Get-JunkCategories {
    $categories = [System.Collections.Generic.List[string]]::new()
    if ((Element 'JunkTemp').IsChecked) { $categories.Add('UserTemp') }
    if ((Element 'JunkShader').IsChecked) { $categories.Add('DirectXShaderCache') }
    if ((Element 'JunkBrowser').IsChecked) { $categories.Add('ChromeCache'); $categories.Add('EdgeCache') }
    if ((Element 'JunkCrash').IsChecked) { $categories.Add('CrashDumps') }
    if ((Element 'JunkReports').IsChecked) { $categories.Add('WindowsErrorReports') }
    if ((Element 'JunkInstaller').IsChecked) { $categories.Add('InstallerTemp') }
    return @($categories)
}

function Invoke-JsonScript([string]$scriptName, [hashtable]$parameters) {
    $path = Join-Path $PSScriptRoot $scriptName
    $raw = & $path @parameters | Out-String
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "$scriptName did not return data." }
    return $raw | ConvertFrom-Json
}

function New-CleanupManifest([string]$type, [object[]]$selected, [object[]]$allItems) {
    $directory = Join-Path $env:LOCALAPPDATA 'CDriveManager\manifests'
    [void](New-Item -ItemType Directory -Path $directory -Force)
    $manifestItems = @($selected | ForEach-Object {
        $hash = if ($_.PSObject.Properties.Name -contains 'Sha256') { $_.Sha256 } else { (Get-FileHash -LiteralPath $_.Path -Algorithm SHA256).Hash }
        [pscustomobject]@{ Path = $_.Path; Size = [long]$_.Size; Sha256 = $hash; Group = $(if ($_.PSObject.Properties.Name -contains 'Group') { $_.Group } else { $null }) }
    })
    $groups = @()
    if ($type -eq 'Duplicates') {
        $groups = @($selected.Group | Select-Object -Unique | ForEach-Object {
            $groupId = $_
            [pscustomobject]@{ Group = $groupId; MemberPaths = @($allItems | Where-Object Group -eq $groupId | Select-Object -ExpandProperty Path) }
        })
    }
    $manifest = [pscustomobject]@{ Version = 1; Type = $type; CreatedAt = (Get-Date).ToString('o'); Items = $manifestItems; Groups = $groups }
    $path = Join-Path $directory ("{0}-{1}.json" -f $type, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-SelectedFileCleanup([string]$type) {
    $grid = if ($type -eq 'LargeFiles') { $largeGrid } else { $duplicateGrid }
    [void]$grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell, $true)
    [void]$grid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true)
    $allItems = if ($type -eq 'LargeFiles') { @($script:largeItems) } else { @($script:duplicateItems) }
    $selected = @($allItems | Where-Object Selected)
    if ($selected.Count -eq 0) { [Windows.MessageBox]::Show('请先勾选要处理的文件。','没有选择') | Out-Null; return }
    try {
        $status.Text = '正在校验所选文件…'
        $manifestPath = New-CleanupManifest -type $type -selected $selected -allItems $allItems
        $preview = Invoke-JsonScript 'Invoke-SafeUserFileCleanup.ps1' @{ ManifestPath = $manifestPath; Mode = 'Preview' }
        $message = "即将把 $($preview.AcceptedCount) 个文件（约 $($preview.AcceptedGiB) GB）移至 Windows 回收站。`n`n是否继续？"
        if ([Windows.MessageBox]::Show($message,'确认处理',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning) -ne [Windows.MessageBoxResult]::Yes) { $status.Text = '已取消'; return }
        $result = Invoke-JsonScript 'Invoke-SafeUserFileCleanup.ps1' @{ ManifestPath = $manifestPath; Mode = 'Execute'; ConfirmPhrase = 'RECYCLE APPROVED USER FILES' }
        [Windows.MessageBox]::Show("已移至回收站：$($result.AcceptedCount) 个；跳过：$($result.SkippedCount) 个。",'处理完成') | Out-Null
        $status.Text = "处理完成｜$($result.AcceptedCount) 个文件已进入回收站"
    } catch { [Windows.MessageBox]::Show($_.Exception.Message,'处理失败') | Out-Null; $status.Text = '处理失败' }
}

(Element 'NavJunk').Add_Click({ Show-Panel 'Junk' })
(Element 'NavLarge').Add_Click({ Show-Panel 'Large' })
(Element 'NavDuplicate').Add_Click({ Show-Panel 'Duplicate' })

(Element 'ScanJunk').Add_Click({
    $categories = Get-JunkCategories
    if ($categories.Count -eq 0 -and -not (Element 'JunkComponents').IsChecked -and -not (Element 'JunkDelivery').IsChecked) { [Windows.MessageBox]::Show('请至少选择一个小类目。','没有选择') | Out-Null; return }
    try {
        $status.Text = '正在执行只读扫描…'; (Element 'JunkResult').Text = '正在扫描，请稍候…'
        $params = @{ Mode = 'Preview'; Categories = $categories }
        if ((Element 'JunkComponents').IsChecked) { $params.IncludeComponentStore = $true }
        if ((Element 'JunkDelivery').IsChecked) { $params.IncludeDeliveryOptimization = $true }
        $script:lastJunkPreview = Invoke-JsonScript 'Invoke-DeepCDriveCleanup.ps1' $params
        (Element 'JunkResult').Text = "健康状态：$(Get-HealthChinese $script:lastJunkPreview.HealthGate.Overall)`r`n可清理文件：$($script:lastJunkPreview.EligibleFileCount) 个`r`n预计空间：$($script:lastJunkPreview.EligibleGiB) GB`r`n跳过：$($script:lastJunkPreview.SkippedCount) 个`r`n`r`n扫描只是预览，尚未删除任何内容。"
        (Element 'CleanJunk').IsEnabled = $true; $status.Text = '扫描完成｜请核对结果后再清理'
    } catch { (Element 'JunkResult').Text = $_.Exception.Message; $status.Text = '扫描失败' }
})

(Element 'CleanJunk').Add_Click({
    if (-not $script:lastJunkPreview) { return }
    if ([Windows.MessageBox]::Show("将清理固定白名单中的 $($script:lastJunkPreview.EligibleFileCount) 个文件，约 $($script:lastJunkPreview.EligibleGiB) GB。`n`n缓存可能在下次启动软件时重新生成。是否继续？",'确认垃圾清理',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning) -ne [Windows.MessageBoxResult]::Yes) { return }
    try {
        $params = @{ Mode = 'Execute'; Categories = (Get-JunkCategories); ConfirmPhrase = 'DEEP CLEAN APPROVED CATEGORIES' }
        if ((Element 'JunkComponents').IsChecked) { $params.IncludeComponentStore = $true }
        if ((Element 'JunkDelivery').IsChecked) { $params.IncludeDeliveryOptimization = $true }
        $result = Invoke-JsonScript 'Invoke-DeepCDriveCleanup.ps1' $params
        (Element 'JunkResult').Text = "已处理：$($result.EligibleFileCount) 个文件`r`n清理前可用：$($result.FreeGiBBefore) GB`r`n清理后可用：$($result.FreeGiBAfter) GB`r`n实际变化：$($result.ActualFreeSpaceChangeGiB) GB`r`n跳过：$($result.SkippedCount) 个"
        $status.Text = '垃圾清理完成'; (Element 'CleanJunk').IsEnabled = $false
    } catch { [Windows.MessageBox]::Show($_.Exception.Message,'清理失败') | Out-Null; $status.Text = '清理失败' }
})

(Element 'ScanLarge').Add_Click({
    try {
        $minimum = [int](Element 'LargeMinimum').Text; $status.Text = '正在扫描大文件…'
        $data = Invoke-JsonScript 'Find-CDriveLargeFiles.ps1' @{ MinimumSizeMB = $minimum }
        $script:largeItems = @($data.Items); $largeGrid.ItemsSource = $script:largeItems
        (Element 'LargeSummary').Text = "找到 $($data.Count) 个文件，共 $($data.TotalGiB) GB。默认不选择，请逐项核对。"
        (Element 'CleanLarge').IsEnabled = ($data.Count -gt 0); $status.Text = '大文件扫描完成'
    } catch { [Windows.MessageBox]::Show($_.Exception.Message,'扫描失败') | Out-Null; $status.Text = '扫描失败' }
})
(Element 'CleanLarge').Add_Click({ Invoke-SelectedFileCleanup 'LargeFiles' })

(Element 'ScanDuplicate').Add_Click({
    try {
        $minimum = [int](Element 'DuplicateMinimum').Text; $status.Text = '正在计算重复文件哈希，这可能需要一些时间…'
        $data = Invoke-JsonScript 'Find-CDriveDuplicateFiles.ps1' @{ MinimumSizeMB = $minimum }
        $script:duplicateItems = @($data.Items); $duplicateGrid.ItemsSource = $script:duplicateItems
        (Element 'DuplicateSummary').Text = "找到 $($data.DuplicateGroupCount) 组、$($data.DuplicateFileCount) 个重复文件；最多可释放约 $($data.PotentialReclaimGiB) GB。默认不选择。"
        (Element 'CleanDuplicate').IsEnabled = ($data.DuplicateFileCount -gt 0); $status.Text = '重复文件扫描完成'
    } catch { [Windows.MessageBox]::Show($_.Exception.Message,'扫描失败') | Out-Null; $status.Text = '扫描失败' }
})
(Element 'CleanDuplicate').Add_Click({ Invoke-SelectedFileCleanup 'Duplicates' })

try {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $used = [long]$disk.Size - [long]$disk.FreeSpace
    $percent = [math]::Round(($used / $disk.Size) * 100, 1)
    (Element 'DriveSummary').Text = "总容量 $([math]::Round($disk.Size / 1GB,1)) GB｜可用 $([math]::Round($disk.FreeSpace / 1GB,1)) GB"
    (Element 'DriveBar').Value = $percent; (Element 'DrivePercent').Text = "$percent% 已用"
    $health = Invoke-JsonScript 'Test-CDriveHealth.ps1' @{}
    (Element 'TopHealth').Text = "健康状态：$(Get-HealthChinese $health.Overall)｜可用 $($health.Volume.FreePercent)%"
} catch { (Element 'TopHealth').Text = 'C 盘状态读取失败' }

Show-Panel $InitialModule

if ($SmokeTest) {
    [pscustomobject]@{ Status = 'PASS'; Window = $window.Title; Modules = @('垃圾清理','查找大文件','重复文件') } | ConvertTo-Json
    $window.Close(); return
}

if (-not [string]::IsNullOrWhiteSpace($ScreenshotPath)) {
    $directory = Split-Path -Parent $ScreenshotPath
    if ($directory) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    $window.Show(); $window.UpdateLayout()
    $bounds = [Windows.Media.VisualTreeHelper]::GetDescendantBounds($window)
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$bounds.Width,[int]$bounds.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $drawing = [Windows.Media.DrawingVisual]::new()
    $context = $drawing.RenderOpen(); $brush = [Windows.Media.VisualBrush]::new($window); $context.DrawRectangle($brush,$null,[Windows.Rect]::new($bounds.Size)); $context.Close(); $bitmap.Render($drawing)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Open($ScreenshotPath,[IO.FileMode]::Create); try { $encoder.Save($stream) } finally { $stream.Dispose() }
    $window.Close(); [pscustomobject]@{ Status = 'PASS'; Screenshot = $ScreenshotPath } | ConvertTo-Json; return
}

[void]$window.ShowDialog()
