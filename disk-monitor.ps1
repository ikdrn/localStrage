# =====================================================
#  disk-monitor.ps1 - ローカルドライブ容量モニター
#  使い方: 右クリック → "PowerShell で実行"
#          または run.bat をダブルクリック
# =====================================================

$REFRESH_SEC = 5  # 自動更新間隔（秒）

function Show-Bar {
    param([double]$Percent, [int]$Width = 25)
    $filled = [math]::Round($Percent / 100 * $Width)
    $filled = [math]::Max(0, [math]::Min($Width, $filled))
    return ("$([char]0x2588)" * $filled) + ("$([char]0x2591)" * ($Width - $filled))
}

function Format-GB {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:F1} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:F1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:F1} MB" -f ($Bytes / 1MB) }
    return "{0:F0} KB" -f ($Bytes / 1KB)
}

function Get-UsageColor {
    param([double]$Percent)
    if ($Percent -ge 90) { return "Red" }
    if ($Percent -ge 70) { return "Yellow" }
    return "Green"
}

while ($true) {
    Clear-Host
    $width = [math]::Max(60, $Host.UI.RawUI.WindowSize.Width - 2)

    # ヘッダー
    Write-Host ("=" * $width) -ForegroundColor Cyan
    Write-Host "  DISK MONITOR  |  $(Get-Date -Format 'yyyy-MM-dd  HH:mm:ss')  |  Ctrl+C で終了" -ForegroundColor Cyan
    Write-Host ("=" * $width) -ForegroundColor Cyan
    Write-Host ""

    # ドライブ情報取得
    $drives = Get-PSDrive -PSProvider FileSystem |
              Where-Object { $_.Used -ne $null -and ($_.Used + $_.Free) -gt 0 }

    if ($drives.Count -eq 0) {
        Write-Host "  ドライブが見つかりませんでした。" -ForegroundColor Red
    }

    foreach ($drive in $drives) {
        $total   = $drive.Used + $drive.Free
        $percent = [math]::Round($drive.Used / $total * 100, 1)
        $color   = Get-UsageColor $percent
        $bar     = Show-Bar $percent

        # ドライブ名行
        Write-Host "  $($drive.Root)" -ForegroundColor White -NoNewline
        if ($drive.Description) {
            Write-Host "  $($drive.Description)" -ForegroundColor DarkGray -NoNewline
        }
        Write-Host ""

        # プログレスバー行
        Write-Host "  [" -NoNewline
        Write-Host $bar -ForegroundColor $color -NoNewline
        Write-Host "]  " -NoNewline
        Write-Host ("{0,5}%" -f $percent) -ForegroundColor $color

        # 容量詳細行
        $usedFmt  = Format-GB $drive.Used
        $freeFmt  = Format-GB $drive.Free
        $totalFmt = Format-GB $total
        Write-Host ("  使用: {0,-10}  空き: {1,-10}  合計: {2}" -f $usedFmt, $freeFmt, $totalFmt) -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host ("─" * $width) -ForegroundColor DarkGray
    Write-Host "  凡例:  " -NoNewline
    Write-Host "正常 <70%  " -ForegroundColor Green -NoNewline
    Write-Host "注意 70-89%  " -ForegroundColor Yellow -NoNewline
    Write-Host "危険 90%+  " -ForegroundColor Red -NoNewline
    Write-Host "  |  ${REFRESH_SEC}秒後に自動更新..." -ForegroundColor DarkGray

    Start-Sleep -Seconds $REFRESH_SEC
}
