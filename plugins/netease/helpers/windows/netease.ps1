param([Parameter(Mandatory = $true)][string]$Data)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$StatePath = Join-Path $Data 'state.txt'
$CmdDir = Join-Path $Data 'cmd'
$BinDir = Join-Path $Data 'bin'
$LogPath = Join-Path $Data 'helper.log'
$LeasePath = Join-Path $Data 'lease'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Clock = [Diagnostics.Stopwatch]::StartNew()

$script:lastLogged = @{}
function Write-Log([string]$Message) {
	$now = $Clock.ElapsedMilliseconds
	if ($script:lastLogged.ContainsKey($Message) -and $now - $script:lastLogged[$Message] -lt 60000) { return }
	$script:lastLogged[$Message] = $now
	try {
		if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 64KB) { [IO.File]::WriteAllText($LogPath, '', $Utf8) }
		[IO.File]::AppendAllText($LogPath, ('{0} windows {1}{2}' -f (Get-Date -Format o), $Message, "`n"), $Utf8)
	} catch {}
}

function Get-UnixSeconds { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$mutex = New-Object System.Threading.Mutex($false, 'Local\tern-netease-helper')
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) { exit 0 }

foreach ($dir in @($Data, $CmdDir, $BinDir)) { [void][IO.Directory]::CreateDirectory($dir) }

# The helper C# is compiled once into bin and reused by its content hash.
$script:native = $false
function Initialize-Native {
	if ($script:native) { return $true }
	$source = [IO.File]::ReadAllText((Join-Path $Here 'netease.cs'))
	$sha = [Security.Cryptography.SHA1]::Create()
	$hash = -join ($sha.ComputeHash($Utf8.GetBytes($source))[0..5] | ForEach-Object { $_.ToString('x2') })
	$dll = Join-Path $BinDir "TernNetease-$hash.dll"
	if (-not (Test-Path $dll)) {
		$tmp = Join-Path $BinDir ("build-{0}-{1}.dll" -f $hash, $PID)
		Add-Type -TypeDefinition $source -OutputAssembly $tmp -OutputType Library
		try { [IO.File]::Move($tmp, $dll) } catch { if (-not (Test-Path $dll)) { throw } }
	}
	Add-Type -Path $dll
	$script:native = $true
	$true
}

$script:problem = ''
try { [void](Initialize-Native) } catch {
	$script:problem = "The NetEase helper could not start: $_"
	Write-Log "native: $_"
}

$script:running = $false
$script:runningAt = -100000
$script:handle = [IntPtr]::Zero
$script:track = $null
$script:status = $null
$script:posSeq = 0
$script:lastLoudAt = -100000
$script:volume = $null
$script:volumeAt = -100000
$script:ack = ''
$script:cmdError = ''
$script:seq = 0
$script:lastBody = ''
$script:lastWriteAt = -100000
$script:forceRead = $false

# Nothing playing keeps the product name in the shell window title.
$script:IDLE_TITLES = @('', '网易云音乐', 'NetEase Cloud Music')

function Format-Value($Value) {
	if ($null -eq $Value) { return '' }
	if ($Value -is [bool]) { if ($Value) { return '1' } else { return '0' } }
	([string]$Value) -replace "[`r`n]+", ' '
}

function Get-Flag([bool]$Value) { if ($Value) { '1' } else { '0' } }

# The CloudMusic shell window title is "<song> - <artist>".
function Split-Title([string]$raw) {
	if ($script:IDLE_TITLES -contains $raw) { return @('', '') }
	$at = $raw.IndexOf(' - ')
	if ($at -lt 1) { return @($raw, '') }
	@($raw.Substring(0, $at), $raw.Substring($at + 3))
}

function Get-MainHandle {
	if (-not [TernNetease.Win]::Alive($script:handle)) {
		$script:handle = [TernNetease.Win]::FindMain()
	}
	$script:handle
}

function Read-State {
	$now = $Clock.ElapsedMilliseconds
	if ($now - $script:runningAt -ge 2000 -or $script:forceRead) {
		$script:running = [TernNetease.Win]::Running()
		$script:runningAt = $now
	}

	$title = ''
	$artist = ''
	if ($script:running) {
		try {
			$parts = Split-Title ([TernNetease.Win]::Title((Get-MainHandle)))
			$title = $parts[0]
			$artist = $parts[1]
		} catch { Write-Log "title: $_" }
	}
	$track = if ($title -eq '') { '' } else { $title + '|' + $artist }

	# The mixer peak tells play from pause: the client keeps its session alive while paused
	# but its streams fall silent. A quiet passage keeps the last loud moment for a moment.
	try {
		if ([TernNetease.AppVolume]::Peak() -gt 0.0005) { $script:lastLoudAt = $now }
	} catch { Write-Log "peak: $_" }
	$status = if ($title -eq '') { 'stopped' } elseif ($now - $script:lastLoudAt -lt 2500) { 'playing' } else { 'paused' }

	if ($track -ne $script:track) { $script:posSeq++ }
	$script:track = $track
	$script:status = $status

	if ($now - $script:volumeAt -ge 1000 -or $script:forceRead) {
		try { $script:volume = [TernNetease.AppVolume]::Get() } catch { $script:volume = $null; Write-Log "volume: $_" }
		$script:volumeAt = $now
	}

	$s = [ordered]@{
		status = $status; title = $title; artist = $artist; track_id = $track
		volume = ''; muted = ''
		can_play = '0'; can_next = '0'; can_prev = '0'; can_volume = '0'; can_mute = '0'
	}
	if ($script:running -and $title -ne '') {
		$s.can_play = '1'
		$s.can_next = '1'
		$s.can_prev = '1'
	}
	if ($null -ne $script:volume) {
		$s.volume = [int][Math]::Round($script:volume[0] * 100)
		$s.muted = Get-Flag ($script:volume[1] -ge 0.5)
		$s.can_volume = '1'
		$s.can_mute = '1'
	}
	$script:forceRead = $false
	$s
}

function Write-State($Fields) {
	$playing = $Fields.status -eq 'playing'
	$body = New-Object System.Text.StringBuilder
	[void]$body.Append("v=1`nbackend=windows`npid=$PID`n")
	[void]$body.Append('running=' + (Get-Flag $script:running) + "`n")
	foreach ($key in $Fields.Keys) { [void]$body.Append($key + '=' + (Format-Value $Fields[$key]) + "`n") }
	[void]$body.Append("pos_seq=$($script:posSeq)`nack=$(Format-Value $script:ack)`nerror=$(Format-Value $script:cmdError)`n")
	[void]$body.Append("problem=$(Format-Value $script:problem)`n")
	$text = $body.ToString()

	$now = $Clock.ElapsedMilliseconds
	$changed = $text -ne $script:lastBody
	$beatEvery = if ($playing) { 1000 } else { 2000 }
	if (-not $changed -and $now - $script:lastWriteAt -lt $beatEvery) { return }
	if ($changed) { $script:seq++ }

	$full = $text + "seq=$($script:seq)`nbeat=$(Get-UnixSeconds)`n"
	$tmp = "$StatePath.tmp"
	[IO.File]::WriteAllText($tmp, $full, $Utf8)
	try {
		if (Test-Path $StatePath) { [IO.File]::Replace($tmp, $StatePath, [NullString]::Value) } else { [IO.File]::Move($tmp, $StatePath) }
	} catch {
		return
	}
	$script:lastBody = $text
	$script:lastWriteAt = $now
}

# CloudMusic ships no local control API: playback goes through its own global hotkeys
# (Ctrl+Alt+P play/pause, Ctrl+Alt+Left previous, Ctrl+Alt+Right next), and the app's
# mixer session carries the volume.
function Invoke-NeteaseCommand([string]$Name, [string]$Arg) {
	if ($Name -eq 'open') {
		$handle = [TernNetease.Win]::FindMain()
		if ($handle -ne [IntPtr]::Zero) {
			[TernNetease.Win]::Show($handle)
			$script:handle = $handle
			return
		}
		Start-Process 'orpheus://'
		return
	}
	if (-not [TernNetease.Win]::Running()) { throw 'NetEase Cloud Music is not running' }
	switch ($Name) {
		'toggle' { [TernNetease.Win]::Hotkey([byte]0x11, [byte]0x12, [byte]0x50) }
		'next' { [TernNetease.Win]::Hotkey([byte]0x11, [byte]0x12, [byte]0x27) }
		'previous' { [TernNetease.Win]::Hotkey([byte]0x11, [byte]0x12, [byte]0x25) }
		'volume' {
			$level = [Math]::Min(100, [Math]::Max(0, [int]$Arg)) / 100.0
			if ([TernNetease.AppVolume]::Set($level, -1) -eq 0) { throw 'NetEase Cloud Music has no audio yet; start playback first' }
		}
		'mute' {
			$mute = if ($Arg -eq '1') { 1 } else { 0 }
			if ([TernNetease.AppVolume]::Set(-1, $mute) -eq 0) { throw 'NetEase Cloud Music has no audio yet; start playback first' }
		}
		default { throw "Unknown command $Name" }
	}
}

function Invoke-Queue {
	$ran = $false
	$files = [IO.Directory]::GetFiles($CmdDir, '*.cmd') | Sort-Object
	foreach ($file in $files) {
		$id = [IO.Path]::GetFileNameWithoutExtension($file)
		$work = "$file.work"
		try { [IO.File]::Move($file, $work) } catch { continue }
		$lines = @([IO.File]::ReadAllLines($work, $Utf8))
		$name = if ($lines.Count -ge 1) { $lines[0].Trim() } else { '' }
		$arg = if ($lines.Count -ge 2) { $lines[1].Trim() } else { '' }
		$written = 0
		[void][long]::TryParse(($id -split '-')[0], [ref]$written)
		if ($name -eq '' -and (Get-UnixSeconds) - $written -lt 3) {
			try { [IO.File]::Move($work, $file) } catch { [IO.File]::Delete($work) }
			continue
		}
		[IO.File]::Delete($work)
		if ($name -eq '' -or (Get-UnixSeconds) - $written -gt 15) { continue }
		$script:ack = $id
		$script:cmdError = ''
		try {
			Invoke-NeteaseCommand $name $arg
		} catch {
			$script:cmdError = $_.Exception.Message
			if ($script:cmdError -notmatch 'is not running|no audio yet') { Write-Log "command $name failed: $_" }
		}
		$ran = $true
	}
	if ($ran) { $script:forceRead = $true }
	$ran
}

function Get-LeaseAge {
	try {
		$lease = 0
		if ([long]::TryParse([IO.File]::ReadAllText($LeasePath).Trim(), [ref]$lease)) { return (Get-UnixSeconds) - $lease }
	} catch {}
	[long]::MaxValue
}

$watcher = New-Object IO.FileSystemWatcher($CmdDir, '*.cmd')
$leaseCheckedAt = -100000
try {
	while ($true) {
		$now = $Clock.ElapsedMilliseconds
		if ($now - $leaseCheckedAt -ge 2000) {
			$leaseCheckedAt = $now
			if ($now -gt 45000 -and (Get-LeaseAge) -gt 45) { break }
		}
		try {
			[void](Invoke-Queue)
			Write-State (Read-State)
		} catch {
			Write-Log "tick: $_"
		}
		$change = $watcher.WaitForChanged([IO.WatcherChangeTypes]::Created -bor [IO.WatcherChangeTypes]::Renamed, 300)
		if (-not $change.TimedOut) { Start-Sleep -Milliseconds 15 }
	}
} finally {
	$watcher.Dispose()
	$mutex.ReleaseMutex()
}
