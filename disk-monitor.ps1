# =============================================================
#  disk-monitor.ps1  -  Disk & Directory Monitor (TUI)
#  インストール不要 / ダブルクリック起動: run.bat を使用
# =============================================================
#  キー操作:
#    ↑ ↓       選択を移動
#    Enter     ドライブ/フォルダに入る / ファイルを開く
#    Backspace 上の階層へ
#    E         エクスプローラで開く
#    F         フォルダ選択ダイアログ
#    S         選択フォルダの完全サイズスキャン
#    D         ドライブ一覧に戻る
#    Q         終了
# =============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms

# ── Config ────────────────────────────────────────────────────
$REFRESH_SEC = 5    # ドライブ画面の自動更新間隔 (秒)
$BAR_W       = 24   # プログレスバーの幅

# ── Helpers ──────────────────────────────────────────────────
function fmtSize([long]$b) {
    if ($b -lt 0)   { return "    ---" }
    if ($b -ge 1TB) { return "{0:F2} TB" -f ($b/1TB) }
    if ($b -ge 1GB) { return "{0:F2} GB" -f ($b/1GB) }
    if ($b -ge 1MB) { return "{0:F1} MB" -f ($b/1MB) }
    if ($b -ge 1KB) { return "{0:F0} KB" -f ($b/1KB) }
    return "$b B"
}

function mkBar([double]$pct, [int]$w = 24) {
    $p = [math]::Max(0, [math]::Min(100, $pct))
    $f = [math]::Round($p / 100 * $w)
    return ([char]0x2588) * $f + ([char]0x2591) * ($w - $f)
}

function pctColor([double]$pct) {
    if ($pct -ge 90) { return "Red" }
    if ($pct -ge 70) { return "Yellow" }
    return "Green"
}

function winW { [Math]::Max(60, [Console]::WindowWidth - 1) }
function winH { [Math]::Max(10, [Console]::WindowHeight) }

function drawHdr([string]$txt) {
    $w = winW
    Write-Host ("═" * $w) -ForegroundColor Cyan
    Write-Host "  $txt" -ForegroundColor Cyan
    Write-Host ("═" * $w) -ForegroundColor Cyan
}

function drawFtr([string]$txt) {
    Write-Host ""
    Write-Host ("─" * (winW)) -ForegroundColor DarkGray
    Write-Host "  $txt" -ForegroundColor DarkGray
}

# ── Drive Screen ──────────────────────────────────────────────
function driveScreen([int]$sel) {
    $drives = @(Get-PSDrive -PSProvider FileSystem |
                Where-Object { $null -ne $_.Used -and ($_.Used + $_.Free) -gt 0 })
    $sel = [math]::Min([math]::Max(0, $sel), [math]::Max(0, $drives.Count - 1))

    [Console]::Clear()
    drawHdr "DISK MONITOR   $(Get-Date -Format 'yyyy-MM-dd  HH:mm:ss')"
    Write-Host ""

    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d     = $drives[$i]
        $total = $d.Used + $d.Free
        $pct   = if ($total -gt 0) { [math]::Round($d.Used / $total * 100, 1) } else { 0 }
        $col   = pctColor $pct
        $bar   = mkBar $pct $BAR_W
        $cur   = if ($i -eq $sel) { ">" } else { " " }
        $hl    = if ($i -eq $sel) { "White" } else { "Gray" }
        $lbl   = $d.Root
        if ($d.Description) { $lbl += "  $($d.Description)" }

        Write-Host ("  $cur ") -NoNewline
        Write-Host ("{0,-26}" -f $lbl) -ForegroundColor $hl -NoNewline
        Write-Host "[" -NoNewline
        Write-Host $bar -ForegroundColor $col -NoNewline
        Write-Host "]" -NoNewline
        Write-Host (" {0,5}%  {1,-10}  / {2}" -f $pct, (fmtSize $d.Used), (fmtSize $total)) -ForegroundColor DarkGray
        Write-Host ""
    }

    drawFtr "Up/Down: 選択   Enter: フォルダを見る   F: ダイアログで選択   E: エクスプローラ   Q: 終了"
    return $drives
}

# ── Directory Screen ──────────────────────────────────────────
function dirScreen([string]$path, [int]$sel) {
    [Console]::Clear()
    drawHdr "  $path"
    Write-Host "  読み込み中..." -ForegroundColor DarkGray

    # エントリ構築
    $entries = [System.Collections.Generic.List[hashtable]]::new()

    # ".." 追加
    $parent = [System.IO.Path]::GetDirectoryName($path)
    if ($parent -and $parent -ne $path) {
        $entries.Add(@{ Label="..  [上の階層へ]"; Path=$parent; IsDir=$true; IsUp=$true; Size=-1L; Count=$null })
    }

    # 子アイテム取得
    $children = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue |
                  Sort-Object @{E={ if ($_.PSIsContainer) { 0 } else { 1 } }}, Name)

    foreach ($c in $children) {
        if ($c.PSIsContainer) {
            $cnt = try {
                (Get-ChildItem -LiteralPath $c.FullName -Force -ErrorAction SilentlyContinue).Count
            } catch { "?" }
            $entries.Add(@{ Label="[DIR]  $($c.Name)"; Path=$c.FullName; IsDir=$true; IsUp=$false; Size=-1L; Count=$cnt })
        } else {
            $entries.Add(@{ Label=$c.Name; Path=$c.FullName; IsDir=$false; IsUp=$false; Size=$c.Length; Count=$null })
        }
    }

    $total = $entries.Count
    $sel = [math]::Min([math]::Max(0, $sel), [math]::Max(0, $total - 1))

    # ファイル合計 (割合計算用)
    $fileTotal = ($entries | Where-Object { -not $_["IsDir"] } |
                  ForEach-Object { $_["Size"] } |
                  Measure-Object -Sum).Sum
    if (-not $fileTotal -or $fileTotal -le 0) { $fileTotal = 1L }

    # スクロール範囲
    $visH  = winH - 9
    $start = [math]::Max(0, $sel - [math]::Floor($visH / 2))
    $end   = [math]::Min($total - 1, $start + $visH - 1)

    # 再描画
    [Console]::Clear()
    drawHdr "  $path"
    Write-Host ""

    # フォルダ統計 (直下のみ)
    $dirCount  = ($entries | Where-Object { $_["IsDir"] -and -not $_["IsUp"] }).Count
    $fileCount = ($entries | Where-Object { -not $_["IsDir"] }).Count
    $fileSzSum = fmtSize ([long]$fileTotal)
    Write-Host ("  フォルダ: {0}  ファイル: {1}  ファイル合計: {2}" -f $dirCount, $fileCount, $fileSzSum) -ForegroundColor DarkGray
    Write-Host ""

    for ($i = $start; $i -le $end; $i++) {
        $e   = $entries[$i]
        $cur = if ($i -eq $sel) { ">" } else { " " }

        if ($e["IsUp"]) {
            $hl = if ($i -eq $sel) { "White" } else { "DarkGray" }
            Write-Host "  $cur $($e["Label"])" -ForegroundColor $hl
            continue
        }

        if ($e["IsDir"]) {
            $hl  = if ($i -eq $sel) { "Cyan" } else { "Blue" }
            $cnt = if ($null -ne $e["Count"]) { " ($($e["Count"]) items)" } else { "" }
            $pad = if ($i -eq $sel) { "" } else { "" }
            Write-Host "  $cur " -NoNewline
            Write-Host ("{0,-42}" -f $e["Label"]) -ForegroundColor $hl -NoNewline
            Write-Host $cnt -ForegroundColor DarkGray
        } else {
            $hl  = if ($i -eq $sel) { "White" } else { "Gray" }
            $pct = [math]::Round($e["Size"] / $fileTotal * 100, 1)
            $bar = mkBar $pct 14
            $col = pctColor $pct
            Write-Host "  $cur " -NoNewline
            Write-Host ("{0,-38}" -f $e["Label"]) -ForegroundColor $hl -NoNewline
            Write-Host " [" -NoNewline
            Write-Host $bar -ForegroundColor $col -NoNewline
            Write-Host "] " -NoNewline
            Write-Host ("{0,10}" -f (fmtSize $e["Size"])) -ForegroundColor DarkGray
        }
    }

    # スクロールインジケーター
    if ($total -gt $visH) {
        Write-Host ("  ... ($($start+1)-$($end+1) / $total 件表示)") -ForegroundColor DarkGray
    }

    # 選択中アイテムのヒント
    $selE = if ($total -gt 0) { $entries[$sel] } else { $null }
    $hint = ""
    if ($selE) {
        $hint = if ($selE["IsDir"] -and -not $selE["IsUp"]) { "  |  S: フォルダサイズスキャン" } else { "" }
    }

    drawFtr "Up/Down: 選択   Enter: 開く   Backspace: 上へ   E: エクスプローラ   S: サイズスキャン   D: ドライブ一覧   Q: 終了$hint"
    return $entries
}

# ── Directory Size Scan ───────────────────────────────────────
function scanSize([string]$path) {
    [Console]::Clear()
    drawHdr "  サイズスキャン: $path"
    Write-Host ""
    Write-Host "  再帰スキャン中... 大きいフォルダは時間がかかります" -ForegroundColor Yellow
    Write-Host "  Ctrl+C でキャンセル" -ForegroundColor DarkGray
    Write-Host ""

    $sw    = [System.Diagnostics.Stopwatch]::StartNew()
    $total = 0L
    $files = 0
    $dirs  = 0

    try {
        Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.PSIsContainer) {
                $dirs++
            } else {
                $total += $_.Length
                $files++
            }
            if (($files + $dirs) % 500 -eq 0) {
                Write-Host ("`r  スキャン済み: {0} ファイル / {1} フォルダ  |  合計: {2}  " -f $files, $dirs, (fmtSize $total)) -NoNewline -ForegroundColor Cyan
            }
        }
    } catch {}

    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    Write-Host ""
    Write-Host ""
    $w = [math]::Min(60, winW - 4)
    Write-Host ("  " + "─" * $w) -ForegroundColor DarkGray
    Write-Host "  パス       : $path" -ForegroundColor White
    Write-Host "  合計サイズ : " -NoNewline
    Write-Host (fmtSize $total) -ForegroundColor Green
    Write-Host "  ファイル数 : $files" -ForegroundColor White
    Write-Host "  フォルダ数 : $dirs" -ForegroundColor White
    Write-Host "  スキャン時間: $elapsed 秒" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  (任意のキーで戻る)" -ForegroundColor DarkGray
    Write-Host ""

    $null = [Console]::ReadKey($true)
}

# ── Folder Browser Dialog ─────────────────────────────────────
function pickFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description       = "フォルダを選択してください"
    $dlg.ShowNewFolderButton = $false
    $dlg.RootFolder        = "MyComputer"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.SelectedPath
    }
    return $null
}

# ── Main Loop ─────────────────────────────────────────────────
$mode    = "drives"
$selIdx  = 0
$curPath = ""
$drives  = @()
$entries = @()

while ($true) {
    # 描画
    if ($mode -eq "drives") {
        $drives  = driveScreen $selIdx
        $maxIdx  = $drives.Count - 1
    } else {
        $entries = dirScreen $curPath $selIdx
        $maxIdx  = $entries.Count - 1
    }

    # キー入力待ち (ドライブ画面はタイムアウトで自動更新)
    $timeout = if ($mode -eq "drives") { $REFRESH_SEC * 10 } else { 99999 }
    $key = $null
    for ($t = 0; $t -lt $timeout; $t++) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            break
        }
        Start-Sleep -Milliseconds 100
    }

    if (-not $key) { continue }   # タイムアウト → 再描画

    switch ($key.Key) {
        # 終了
        ([ConsoleKey]::Q) { [Console]::Clear(); exit }

        # 上移動
        ([ConsoleKey]::UpArrow) {
            if ($selIdx -gt 0) { $selIdx-- }
        }

        # 下移動
        ([ConsoleKey]::DownArrow) {
            if ($selIdx -lt $maxIdx) { $selIdx++ }
        }

        # 決定
        ([ConsoleKey]::Enter) {
            if ($mode -eq "drives" -and $drives.Count -gt 0) {
                $curPath = $drives[$selIdx].Root
                $mode    = "directory"
                $selIdx  = 0
            } elseif ($mode -eq "directory" -and $entries.Count -gt 0) {
                $e = $entries[$selIdx]
                if ($e["IsDir"] -and (Test-Path -LiteralPath $e["Path"] -PathType Container)) {
                    $curPath = $e["Path"]
                    $selIdx  = 0
                } elseif (-not $e["IsDir"] -and (Test-Path -LiteralPath $e["Path"])) {
                    Start-Process $e["Path"]
                }
            }
        }

        # 上の階層へ
        ([ConsoleKey]::Backspace) {
            if ($mode -eq "directory") {
                $par = [System.IO.Path]::GetDirectoryName($curPath)
                if ($par -and $par -ne $curPath) {
                    $curPath = $par
                    $selIdx  = 0
                } else {
                    $mode   = "drives"
                    $selIdx = 0
                }
            }
        }

        # ドライブ一覧に戻る
        ([ConsoleKey]::D) { $mode = "drives"; $selIdx = 0 }

        # エクスプローラで開く
        ([ConsoleKey]::E) {
            $target = $null
            if ($mode -eq "drives" -and $drives.Count -gt 0) {
                $target = $drives[$selIdx].Root
            } elseif ($mode -eq "directory" -and $entries.Count -gt 0) {
                $e = $entries[$selIdx]
                $target = if ($e["IsDir"]) { $e["Path"] } else { [System.IO.Path]::GetDirectoryName($e["Path"]) }
            }
            if ($target -and (Test-Path -LiteralPath $target)) {
                Start-Process explorer.exe -ArgumentList "`"$target`""
            }
        }

        # フォルダサイズスキャン
        ([ConsoleKey]::S) {
            if ($mode -eq "directory" -and $entries.Count -gt 0) {
                $e        = $entries[$selIdx]
                $scanPath = if ($e["IsDir"]) { $e["Path"] } else { $curPath }
                if (Test-Path -LiteralPath $scanPath -PathType Container) {
                    scanSize $scanPath
                }
            } elseif ($mode -eq "drives" -and $drives.Count -gt 0) {
                scanSize $drives[$selIdx].Root
            }
        }

        # フォルダ選択ダイアログ
        ([ConsoleKey]::F) {
            $picked = pickFolder
            if ($picked) {
                $curPath = $picked
                $mode    = "directory"
                $selIdx  = 0
            }
        }
    }
}
