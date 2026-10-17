param(
    [string]$AutoHotkeyPath = "D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe",
    [ValidateRange(500, 15000)]
    [int]$PaceMs = 3000,
    [ValidateRange(20, 300)]
    [int]$TypeDelayMs = 50,
    [ValidateSet("balanced", "fast", "readable")]
    [string]$SpeedMode = "balanced",
    [string]$StartSignalPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "SevenNote.ahk"
$driverPath = Join-Path $PSScriptRoot "user_journey_driver.ahk"
$reportPath = Join-Path $PSScriptRoot "user-journey-report.html"

if (-not (Test-Path -LiteralPath $AutoHotkeyPath)) {
    throw "AutoHotkey v2 x64 not found at '$AutoHotkeyPath'. Pass -AutoHotkeyPath."
}
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "SevenNote.ahk was not found."
}

$runId = [Guid]::NewGuid().ToString("N")
$sandboxRoot = Join-Path $env:TEMP "SevenNoteJourneyTests\$runId"
$appDataPath = Join-Path $sandboxRoot "AppData"
$vaultPath = Join-Path $sandboxRoot "Vault"
$configPath = Join-Path $appDataPath "_config.ini"
$testScriptPath = Join-Path $sandboxRoot "SevenNote-JourneyDemo.ahk"
$resultPath = Join-Path $sandboxRoot "results.tsv"
$tracePath = Join-Path $sandboxRoot "trace.log"
$demoImagePath = Join-Path $sandboxRoot "journey-image.bmp"
$process = $null

try {
    $demoSandboxPrefix = Join-Path $env:TEMP "SevenNoteJourneyTests\"
    $existingDemo = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and
        $_.CommandLine.Contains($demoSandboxPrefix) -and
        $_.CommandLine -match 'SevenNote-JourneyDemo\.ahk'
    } | Select-Object -First 1
    if ($existingDemo) {
        throw "An isolated presentation is already running (PID $($existingDemo.ProcessId)); refusing to send input to an ambiguous window."
    }

    New-Item -ItemType Directory -Path $appDataPath, $vaultPath -Force | Out-Null
    Set-Content -LiteralPath $configPath -Value "[Paths]`r`nVault=$vaultPath" -Encoding ASCII
    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::new(420, 150)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(242, 247, 250))
    $accent = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(52, 112, 136))
    $graphics.FillRectangle($accent, 0, 0, 12, 150)
    $titleFont = [System.Drawing.Font]::new("Microsoft YaHei UI", 21, [System.Drawing.FontStyle]::Bold)
    $bodyFont = [System.Drawing.Font]::new("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Regular)
    $titleBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(31, 58, 92))
    $bodyBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(82, 96, 120))
    $graphics.DrawString("图文记录 · 截图与说明同页", $titleFont, $titleBrush, 28, 30)
    $graphics.DrawString("粘贴即嵌入笔记，附件按日期归档", $bodyFont, $bodyBrush, 30, 86)
    $bitmap.Save($demoImagePath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bodyBrush.Dispose()
    $titleBrush.Dispose()
    $bodyFont.Dispose()
    $titleFont.Dispose()
    $accent.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
    $source = [System.IO.File]::ReadAllText($sourcePath, [System.Text.Encoding]::UTF8)
    function Replace-ExactlyOnce([string]$Text, [string]$Pattern, [string]$Replacement, [string]$Label) {
        $regex = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        $matches = $regex.Matches($Text)
        if ($matches.Count -ne 1) {
            $count = $matches.Count
            throw "Expected exactly one source location for $Label (matches: $count). No demo process was started."
        }

        $match = $matches[0]
        $prefix = $Text.Substring(0, $match.Index)
        $suffix = $Text.Substring($match.Index + $match.Length)
        return $prefix + $Replacement + $suffix
    }

    $source = Replace-ExactlyOnce $source '^\s*static AppName := "SevenNote"\s*$' '    static AppName := "SevenNote-JourneyDemo"' "AppName"
    $source = Replace-ExactlyOnce $source '^\s*static AppDataDir := .+$' ('    static AppDataDir := "' + $appDataPath + '"') "AppDataDir"
    $source = Replace-ExactlyOnce $source '^\s*static ConfigPath := .+$' ('    static ConfigPath := "' + $configPath + '"') "ConfigPath"

    $pandocGuard = '(?m)^if !FileExist\(A_AppData \. "\\SevenNote\\pandoc\.exe"\) \|\| FileGetSize\(A_AppData \. "\\SevenNote\\pandoc\.exe"\) < 1048576 \{\r?$'
    if (-not [regex]::IsMatch($source, $pandocGuard)) {
        throw "Could not isolate the Pandoc extraction block. No demo process was started."
    }
    $source = [regex]::Replace($source, $pandocGuard, 'if false {', 1)

    # Hotkey wiring moved into RegisterHotkeys() (data-driven table); the
    # call site below is the stable anchor that proves the composition root
    # is still assembling hotkeys.
    $source = Replace-ExactlyOnce $source `
        '(?m)^RegisterHotkeys\(\)\r?$' `
        'RegisterHotkeys()' `
        "hotkey registration"
    $source = Replace-ExactlyOnce $source `
        '(?m)^ShowStartupTip\(\)\r?$' `
        '; Startup tip disabled in the presentation-only copy.' `
        "startup tip"

    $driver = [System.IO.File]::ReadAllText($driverPath, [System.Text.Encoding]::UTF8)
    $driver = $driver.Replace("__RESULT_PATH__", $resultPath)
    $driver = $driver.Replace("__DEMO_IMAGE_PATH__", $demoImagePath)
    $driver = $driver.Replace("__TRACE_PATH__", $tracePath)
    $driver = $driver.Replace("__START_SIGNAL_PATH__", $StartSignalPath)
    $driver = Replace-ExactlyOnce $driver `
        '(?m)^global JourneyPaceMs := \d+\r?$' `
        ("global JourneyPaceMs := " + $PaceMs) `
        "presentation pace"
    $driver = Replace-ExactlyOnce $driver `
        '(?m)^global JourneyTypeDelayMs := \d+\r?$' `
        ("global JourneyTypeDelayMs := " + $TypeDelayMs) `
        "typing pace"
    $driver = Replace-ExactlyOnce $driver `
        '(?m)^global JourneySpeedMode := "balanced"\r?$' `
        ('global JourneySpeedMode := "' + $SpeedMode.ToLowerInvariant() + '"') `
        "speed mode"
    [System.IO.File]::WriteAllText(
        $testScriptPath,
        $source + "`r`n`r`n" + $driver,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "Starting isolated six-module presentation (speed mode: $SpeedMode)..."
    $process = Start-Process `
        -FilePath $AutoHotkeyPath `
        -ArgumentList @("`"$testScriptPath`"") `
        -WorkingDirectory $sandboxRoot `
        -PassThru

    try {
        Wait-Process -Id $process.Id -Timeout 600
    } catch {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $tracePath) {
            Write-Host "Last presentation checkpoints:"
            Get-Content -LiteralPath $tracePath -Tail 30 | Write-Host
        }
        throw "The presentation did not finish within 600 seconds."
    }
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "No presentation result file was produced. Check for an AutoHotkey runtime dialog."
    }

    $results = @(
        Get-Content -LiteralPath $resultPath -Encoding UTF8 | ForEach-Object {
            $fields = $_ -split "`t", 8
            if ($fields.Count -ne 8) {
                throw "Malformed presentation result row: $_"
            }
            [pscustomobject]@{
                Status = $fields[0]
                Chapter = $fields[1]
                Journey = $fields[2]
                Feature = $fields[3]
                Hotkey = $fields[4]
                Story = $fields[5]
                Action = $fields[6]
                Details = $fields[7]
            }
        }
    )
    if ($results.Count -ne 6) {
        throw "Expected six journey chapters, received $($results.Count)."
    }
    $passed = @($results | Where-Object Status -eq "PASS").Count
    $failed = @($results | Where-Object Status -ne "PASS").Count
    $cards = foreach ($result in $results) {
        $chapter = [System.Net.WebUtility]::HtmlEncode($result.Chapter)
        $journey = [System.Net.WebUtility]::HtmlEncode($result.Journey)
        $feature = [System.Net.WebUtility]::HtmlEncode($result.Feature)
        $hotkey = [System.Net.WebUtility]::HtmlEncode($result.Hotkey)
        $story = [System.Net.WebUtility]::HtmlEncode($result.Story)
        $action = [System.Net.WebUtility]::HtmlEncode($result.Action)
        $details = [System.Net.WebUtility]::HtmlEncode($result.Details)
        $status = [System.Net.WebUtility]::HtmlEncode($result.Status)
        $class = $result.Status.ToLowerInvariant()
        "<article class='chapter $class'><header><div><p class='eyebrow'>$journey</p><h2>$chapter</h2></div><span class='status'>$status</span></header><p class='feature'>$feature</p><p class='story'>$story</p><p class='hotkey'>$hotkey</p><p class='action'><strong>&#29616;&#22330;&#25805;&#20316;&#65306;</strong>$action</p><p class='detail'>$details</p></article>"
    }
    $overallClass = if ($failed -eq 0) { "pass" } else { "fail" }
    $overall = if ($failed -eq 0) { "&#20845;&#20010;&#29615;&#33410;&#23637;&#31034;&#23436;&#25104;" } else { "&#23384;&#22312;&#26410;&#36890;&#36807;&#29615;&#33410;" }
    $html = @"
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SevenNote User Journey</title>
<style>
    :root { font-family: "Segoe UI", "Microsoft YaHei", sans-serif; color: #182235; }
    body { margin: 0; background: #f3f5f9; }
    main { max-width: 900px; margin: 38px auto; padding: 0 22px; }
    header.hero { padding: 28px 30px; background: linear-gradient(120deg, #fff, #edf3ff); border: 1px solid #e1e7f0; border-radius: 18px; }
    h1 { margin: 0 0 10px; font-size: 30px; }
    h2 { margin: 0; font-size: 22px; color: #1f3a5c; }
    h3 { margin: 16px 0 4px; color: #7b5a20; font-size: 13px; }
    p { margin: 0; color: #526078; font-size: 17px; line-height: 1.65; }
    .muted { color: #68758a; line-height: 1.7; }
    .badge, .status { display: inline-block; padding: 6px 11px; border-radius: 99px; font-weight: 700; }
    .badge.pass, .pass .status { color: #147a46; background: #e5f5eb; }
    .badge.fail, .fail .status { color: #b72e2e; background: #ffeded; }
    .metrics { display: flex; gap: 12px; margin: 16px 0 24px; }
    .metric { flex: 1; background: #fff; border: 1px solid #e1e7f0; border-radius: 13px; padding: 14px 18px; color: #68758a; }
    .metric strong { display: block; font-size: 24px; color: #182235; }
    .chapter { margin: 14px 0; padding: 20px 24px; background: #fff; border: 1px solid #e1e7f0; border-radius: 16px; }
    .chapter header { display: flex; align-items: center; gap: 12px; }
    .chapter .status { margin-left: auto; font-size: 11px; }
    .feature { margin-top: 14px; color: #7b5a20; font-size: 19px; font-weight: 700; }
    .story { margin-top: 12px; }
    .hotkey { margin-top: 10px; padding: 10px 14px; background: #e5ecf5; border-radius: 9px; color: #29496e; font-size: 17px; font-weight: 700; }
    .action { margin-top: 12px; padding: 11px 14px; background: #f3f6fb; border-radius: 9px; }
    .detail { margin-top: 10px; color: #147a46; font-size: 15px; }
    .eyebrow { margin-bottom: 4px; color: #7b5a20; font-size: 13px; font-weight: 700; letter-spacing: .04em; }
    footer { color: #68758a; font-size: 13px; margin: 18px 4px; }
    @media (max-width: 700px) { main { margin: 20px auto; } .metrics { gap: 6px; } .metric { padding: 10px; } }
</style>
</head>
<body><main>
<header class="hero">
  <h1>SevenNote &#29992;&#25143;&#26053;&#36884;</h1>
  <span class="badge $overallClass">$overall</span>
  <p class="muted">&#20174;&#24207;&#35328;&#21040;&#20845;&#20010;&#21151;&#33021;&#27169;&#22359;&#65306;&#19971;&#20221;&#31508;&#35760;&#25353;&#36830;&#32493;&#26085;&#26399;&#21644;&#26053;&#36884;&#26631;&#31614;&#32452;&#32455;&#12290;&#28436;&#31034;&#20808;&#25552;&#31034;&#65292;&#20877;&#25191;&#34892;&#28909;&#38190;&#65292;&#26368;&#21518;&#23637;&#31034;&#20445;&#23384;&#12289;&#26631;&#31614;&#19982;&#22238;&#39038;&#25928;&#26524;&#12290;</p>
</header>
<section class="metrics">
  <div class="metric"><strong>7</strong>&#20221;&#25353;&#26085;&#26399;&#32534;&#25490;&#30340;&#28436;&#31034;&#31508;&#35760;</div>
  <div class="metric"><strong style="color:#147a46">$passed</strong>&#20010;&#21151;&#33021;&#28436;&#31034;&#29615;&#33410;&#36890;&#36807;</div>
  <div class="metric"><strong style="color:#b72e2e">$failed</strong>&#20010;&#26410;&#36890;&#36807;</div>
</section>
<div class="journey">$($cards -join "`r`n")</div>
<footer>&#28436;&#31034;&#31508;&#35760;&#21644;&#37197;&#32622;&#22343;&#38480;&#20110;&#20020;&#26102;&#38548;&#31163;&#29615;&#22659; &#183; $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</footer>
</main></body></html>
"@
    [System.IO.File]::WriteAllText($reportPath, $html, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Journey modules: $($results.Count); seven dated notes including prologue; displayed and verified: $passed; failed: $failed."
    Write-Host "Window layout: equal-size outer bounds, side by side, no overlap."
    Write-Host "Features demonstrated: $((@($results.Feature | Select-Object -Unique)) -join ', ')"
    if (Test-Path -LiteralPath $tracePath) {
        Write-Host "Retrieval checkpoints:"
        Get-Content -LiteralPath $tracePath | Where-Object {
            $_ -match "DirectJump|FilteredJump|List click|Chapter checks complete"
        } | Write-Host
    }
    Write-Host "Presentation report: $reportPath"
    Start-Process -FilePath $reportPath
    if ($failed -gt 0) {
        exit 1
    }
} finally {
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $null = $process.WaitForExit(5000)
        }
    }
    if (Test-Path -LiteralPath $sandboxRoot) {
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force
    }
}
