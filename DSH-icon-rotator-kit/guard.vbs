' guard.vbs - rotates the DeepSeek Harness tray icon when the app exits.
'
' Design (v3):
'   * the icon is swapped the moment every DeepSeek Harness process is gone;
'   * the swap is done inside this script (file copy + shortcut icons), a few
'     dozen milliseconds, so an immediate relaunch cannot beat it;
'   * the icon library is scanned on every swap, so dropping new .ico files
'     into the icons folder is enough - no reinstall, no restart;
'   * single icon chain (v6): the chosen icon is copied into the install dir -
'     <install>\resources\tray.ico for the tray and
'     <install>\resources\DSH-icon-chain\<name>.ico for the shortcuts; shortcut
'     IconLocation never points at the library/kit folder;
'   * v7: the managed folder %LOCALAPPDATA%\DSH-icon-rotator\icons is the ONLY
'     icon source (install.cmd copies the kit icons into it);
'   * a start-time fallback covers a crash / forced kill;
'   * started detached (parent is WmiPrvSE), so quitting the app cannot take
'     the guard down with it.
'
' Optional argument: process name to watch (default "DeepSeek Harness.exe").

Option Explicit

Dim gAppName, gRoot, gIcons, gTray, gChainDir, gLogPath, gRotateLog, gLastFile
Dim gFso, gShell, gSvc, gLastKnown, gLastRotate, gLastSeason, gStateFile

gAppName = "DeepSeek Harness.exe"
If WScript.Arguments.Count > 0 Then gAppName = WScript.Arguments(0)

Set gFso = CreateObject("Scripting.FileSystemObject")
Set gShell = CreateObject("WScript.Shell")
gRoot = gShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\DSH-icon-rotator"
gIcons = gRoot & "\icons"
gLogPath = gRoot & "\guard.log"
gRotateLog = gRoot & "\rotate.log"
gLastFile = gRoot & "\last-icon.txt"
gStateFile = gRoot & "\app-state.txt"
gLastKnown = False
gLastRotate = Empty
gLastSeason = ""
' the guard is long-lived: remember "name|size -> is a valid ico" so a rotation
' only validates a file once (first rotation after start), not on every exit
Dim gIcoCache
Set gIcoCache = CreateObject("Scripting.Dictionary")

Function FindTrayPath()
    Dim marker, dir, i, cand, bases
    marker = gRoot & "\install-path.txt"
    If gFso.FileExists(marker) Then
        On Error Resume Next
        dir = gFso.OpenTextFile(marker, 1).ReadAll
        On Error GoTo 0
        dir = Trim(Replace(Replace(dir, vbCr, ""), vbLf, ""))
        If dir <> "" Then
            cand = dir & "\resources\tray.ico"
            If gFso.FileExists(cand) Then
                FindTrayPath = cand
                Exit Function
            End If
        End If
    End If
    bases = Array(gShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Programs\DeepSeek Harness", _
                  gShell.ExpandEnvironmentStrings("%ProgramFiles%") & "\DeepSeek Harness", _
                  gShell.ExpandEnvironmentStrings("%ProgramFiles(x86)%") & "\DeepSeek Harness")
    For i = 0 To UBound(bases)
        cand = bases(i) & "\resources\tray.ico"
        If gFso.FileExists(cand) Then
            FindTrayPath = cand
            Exit Function
        End If
    Next
    FindTrayPath = ""
End Function

Sub LogEvent(ByVal Message)
    On Error Resume Next
    Dim f
    Set f = gFso.OpenTextFile(gLogPath, 8, True)
    f.WriteLine Now & "  " & Message
    f.Close
End Sub

Sub LogRotate(ByVal Message)
    On Error Resume Next
    Dim f
    Set f = gFso.OpenTextFile(gRotateLog, 8, True)
    f.WriteLine Replace(Now, "/", "-") & "  " & Message
    f.Close
End Sub

Function AppRunning()
    On Error Resume Next
    Dim col
    Set col = gSvc.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='" & gAppName & "'")
    If Err.Number <> 0 Then
        Err.Clear
        AppRunning = gLastKnown
        Exit Function
    End If
    AppRunning = (col.Count > 0)
End Function

Function FileSize(ByVal p)
    On Error Resume Next
    If gFso.FileExists(p) Then
        FileSize = gFso.GetFile(p).Size
    Else
        FileSize = -1
    End If
End Function

' a real ICO starts with 00 00 01 00
Function IsIco(ByVal p)
    Dim s, b
    IsIco = False
    On Error Resume Next
    Set s = CreateObject("ADODB.Stream")
    s.Type = 1
    s.Open
    s.LoadFromFile p
    If s.Size >= 4 Then
        s.Position = 0
        b = s.Read(4)
        If b(0) = 0 And b(1) = 0 And b(2) = 1 And b(3) = 0 Then IsIco = True
    End If
    s.Close
    On Error GoTo 0
End Function

' all usable icons: managed folder first, then the app's own season folder
Function IsIcoCached(ByVal p, ByVal size)
    Dim key, ok
    key = LCase(p) & "|" & CStr(size)
    If gIcoCache.Exists(key) Then
        IsIcoCached = gIcoCache.Item(key)
        Exit Function
    End If
    ok = IsIco(p)
    On Error Resume Next
    gIcoCache.Add key, ok
    On Error GoTo 0
    IsIcoCached = ok
End Function

Function CollectIcons()
    Dim dict, seenSizes, dirs, d, f, file, nm, sz
    Set dict = CreateObject("Scripting.Dictionary")
    Set seenSizes = CreateObject("Scripting.Dictionary")
    dirs = Array(gIcons)
    For d = 0 To UBound(dirs)
        If dirs(d) <> "" Then
            If gFso.FolderExists(dirs(d)) Then
                For Each file In gFso.GetFolder(dirs(d)).Files
                    If LCase(gFso.GetExtensionName(file.Name)) = "ico" Then
                        nm = LCase(gFso.GetBaseName(file.Name))
                        If InStr(nm, "original") = 0 And InStr(nm, "backup") = 0 Then
                            If Not dict.Exists(nm) Then
                                If IsIcoCached(file.Path, file.Size) Then
                                    ' identical files often live in both folders: dedupe by size
                                    sz = CStr(file.Size)
                                    If Not seenSizes.Exists(sz) Then
                                        seenSizes.Add sz, True
                                        dict.Add nm, file.Path
                                    End If
                                Else
                                    LogEvent "ignored (not a valid .ico): " & file.Name
                                End If
                            End If
                        End If
                    End If
                Next
            End If
        End If
    Next
    CollectIcons = dict.Items
End Function

Function ReadLastSeason()
    Dim f, s
    ReadLastSeason = ""
    On Error Resume Next
    If gFso.FileExists(gLastFile) Then
        Set f = gFso.OpenTextFile(gLastFile, 1)
        s = CleanText(f.ReadAll)
        f.Close
        ReadLastSeason = LCase(s)
    End If
    On Error GoTo 0
End Function

' VBScript Trim() only strips spaces - this also strips CR/LF
Function CleanText(ByVal s)
    s = Replace(s, vbCr, "")
    s = Replace(s, vbLf, "")
    CleanText = Trim(s)
End Function

Sub WriteLastSeason(ByVal name)
    On Error Resume Next
    Dim f
    Set f = gFso.OpenTextFile(gLastFile, 2, True)
    f.WriteLine LCase(name)
    f.Close
End Sub

' remembered across guard restarts: "running" means the app was up when we last
' looked, i.e. a power loss / forced kill could have skipped the exit rotation
Function ReadAppState()
    Dim f, s
    ReadAppState = ""
    On Error Resume Next
    If gFso.FileExists(gStateFile) Then
        Set f = gFso.OpenTextFile(gStateFile, 1)
        s = CleanText(f.ReadAll)
        f.Close
        ReadAppState = LCase(s)
    End If
    On Error GoTo 0
End Function

Sub WriteAppState(ByVal state)
    On Error Resume Next
    Dim f
    Set f = gFso.OpenTextFile(gStateFile, 2, True)
    f.WriteLine state
    f.Close
End Sub

' pick an icon that differs from the one currently installed
Function PickIcon(ByRef chosenPath)
    Dim icons, i, cur, last, name, p, n, pool(), sz
    PickIcon = ""
    chosenPath = ""
    icons = CollectIcons()
    If UBound(icons) < 0 Then Exit Function

    cur = FileSize(gTray)
    last = ReadLastSeason()
    n = 0
    For i = 0 To UBound(icons)
        p = icons(i)
        name = LCase(gFso.GetBaseName(p))
        If name <> last And FileSize(p) <> cur Then
            ReDim Preserve pool(n)
            pool(n) = p
            n = n + 1
        End If
    Next
    ' fallback: only the name filter, in case sizes happen to collide
    If n = 0 Then
        For i = 0 To UBound(icons)
            p = icons(i)
            If LCase(gFso.GetBaseName(p)) <> last Then
                ReDim Preserve pool(n)
                pool(n) = p
                n = n + 1
            End If
        Next
    End If
    ' last resort: anything valid
    If n = 0 Then
        For i = 0 To UBound(icons)
            p = icons(i)
            If True Then
                ReDim Preserve pool(n)
                pool(n) = p
                n = n + 1
            End If
        Next
    End If
    If n = 0 Then Exit Function

    ' v6: pick ONE random index. With two separate Rnd() calls the name written
    ' to the log could differ from the icon actually installed.
    Dim pick
    Randomize
    pick = Int(Rnd() * n)
    PickIcon = gFso.GetBaseName(pool(pick))
    chosenPath = pool(pick)
End Function

Function InstallIcon(ByVal src, ByVal dst)
    Dim i
    InstallIcon = False
    For i = 1 To 3
        On Error Resume Next
        gFso.CopyFile src, dst, True
        If Err.Number = 0 Then
            On Error GoTo 0
            InstallIcon = True
            Exit Function
        End If
        Err.Clear
        WScript.Sleep 120
    Next
    On Error GoTo 0
End Function

' v6: always receives a file under <install>\resources (normally
' DSH-icon-chain\<name>.ico, gTray as a fallback) - never a library/kit path
Sub SyncShortcuts(ByVal iconPath)
    Dim lnks, i, ws, lnk
    lnks = Array( _
        gShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Desktop\DeepSeek Harness.lnk", _
        gShell.ExpandEnvironmentStrings("%APPDATA%") & "\Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk", _
        gShell.ExpandEnvironmentStrings("%APPDATA%") & "\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\DeepSeek Harness.lnk")
    On Error Resume Next
    Set ws = CreateObject("WScript.Shell")
    For i = 0 To UBound(lnks)
        If gFso.FileExists(lnks(i)) Then
            Set lnk = ws.CreateShortcut(lnks(i))
            lnk.IconLocation = iconPath & ",0"
            lnk.Save
            Err.Clear
        End If
    Next
    On Error GoTo 0
End Sub

' v6: repair shortcuts that were reset outside the install dir (an app update
' reinstalls/relinks them to the exe). Runs at guard start and when the app
' starts - only touches links that do not already point into <install>\resources.
Sub EnsureShortcuts()
    Dim season, chainIcon, lnks, i, ws, lnk, loc, prefix
    If gTray = "" Or gChainDir = "" Then Exit Sub
    season = ReadLastSeason()
    If season = "" Then Exit Sub
    chainIcon = gChainDir & "\" & LCase(season) & ".ico"
    If Not gFso.FileExists(chainIcon) Then
        If gFso.FileExists(gTray) Then InstallIcon gTray, chainIcon
    End If
    If Not gFso.FileExists(chainIcon) Then Exit Sub
    prefix = LCase(gFso.GetParentFolderName(gTray) & "\")
    lnks = Array( _
        gShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Desktop\DeepSeek Harness.lnk", _
        gShell.ExpandEnvironmentStrings("%APPDATA%") & "\Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk", _
        gShell.ExpandEnvironmentStrings("%APPDATA%") & "\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\DeepSeek Harness.lnk")
    On Error Resume Next
    Set ws = CreateObject("WScript.Shell")
    For i = 0 To UBound(lnks)
        If gFso.FileExists(lnks(i)) Then
            Set lnk = ws.CreateShortcut(lnks(i))
            loc = LCase(lnk.IconLocation)
            If Left(loc, Len(prefix)) <> prefix Then
                lnk.IconLocation = chainIcon & ",0"
                lnk.Save
                LogEvent "shortcut re-linked to icon chain: " & lnks(i)
            End If
            Err.Clear
        End If
    Next
    On Error GoTo 0
End Sub

Sub RotateFast(ByVal Tag)
    Dim t0, season, src, ms, chainIcon
    t0 = Timer
    gTray = FindTrayPath()
    If gTray = "" Then
        LogEvent "rotate skipped (" & Tag & "): tray.ico not found"
        Exit Sub
    End If
    season = PickIcon(src)
    If season = "" Or src = "" Then
        LogEvent "rotate skipped (" & Tag & "): no usable icons in " & gIcons
        Exit Sub
    End If
    If Not InstallIcon(src, gTray) Then
        LogEvent "rotate FAILED (" & Tag & "): cannot write " & gTray
        Exit Sub
    End If
    ' v6: shortcuts get a per-icon copy inside the install dir. A fixed path with
    ' changing content is served from the shell icon cache (stale image), while a
    ' per-icon filename can never go stale.
    If Not gFso.FolderExists(gChainDir) Then
        On Error Resume Next
        gFso.CreateFolder gChainDir
        On Error GoTo 0
    End If
    chainIcon = gChainDir & "\" & LCase(season) & ".ico"
    If Not InstallIcon(src, chainIcon) Then
        LogEvent "WARN cannot write shortcut icon " & chainIcon
        chainIcon = gTray
    End If
    SyncShortcuts chainIcon
    WriteLastSeason season
    gLastRotate = Now
    gLastSeason = season
    ms = Int((Timer - t0) * 1000)
    LogRotate "rotated -> " & season & " (" & Tag & ", " & ms & " ms, shortcuts synced)"
    LogEvent "rotated -> " & season & " (" & Tag & ") in " & ms & " ms"
End Sub

' --------------------------------------------------------------------- main --
Dim svc
Set svc = GetObject("winmgmts:\\.\root\cimv2")
Set gSvc = svc

Dim peers
Set peers = svc.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='wscript.exe' AND CommandLine LIKE '%guard.vbs%'")
If peers.Count > 1 Then WScript.Quit 0

gTray = FindTrayPath()
If gTray <> "" Then
    gChainDir = gFso.GetParentFolderName(gTray) & "\DSH-icon-chain"
End If

Dim iconCount
iconCount = UBound(CollectIcons()) + 1
LogEvent "guard started (watching: " & gAppName & ", icon library: " & iconCount & " ico)"

Dim wasRunning, nowRunning, prevState
prevState = ReadAppState()
gLastKnown = AppRunning()
wasRunning = gLastKnown

If wasRunning Then
    EnsureShortcuts
    WriteAppState "running"
ElseIf prevState = "running" Then
    ' the state file said the app was up, but nothing is running now: the exit
    ' rotation could not happen (power loss / forced kill) -> recover once
    LogEvent "previous session ended without an exit rotation -> recovery rotate"
    RotateFast "start-fallback"
    WriteAppState "exited"
Else
    WriteAppState "exited"
End If

Do
    WScript.Sleep 600
    nowRunning = AppRunning()
    gLastKnown = nowRunning

    If wasRunning And Not nowRunning Then
        LogEvent "app exited (all processes gone) -> rotating"
        RotateFast "exit"
        WriteAppState "exited"
        nowRunning = AppRunning()
        gLastKnown = nowRunning
    ElseIf (Not wasRunning) And nowRunning Then
        ' exit-time only: starting the app never rotates, it just reads the icon
        ' that the previous exit already installed; repair shortcut links that an
        ' app update may have reset
        EnsureShortcuts
        LogEvent "app started (icon already installed at last exit, no rotation)"
        WriteAppState "running"
    End If

    wasRunning = nowRunning
Loop
