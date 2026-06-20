Option Explicit

Dim outPath
outPath = WScript.Arguments(0)

Dim fso, out
Set fso = CreateObject("Scripting.FileSystemObject")
Set out = fso.CreateTextFile(outPath, True, True)

On Error Resume Next
Dim SapGuiAuto, app, conn, sess
Set SapGuiAuto = GetObject("SAPGUI")
If Err.Number <> 0 Then
  out.WriteLine "ERROR: Cannot get SAPGUI object: " & Err.Description
  out.Close
  WScript.Quit 1
End If
Err.Clear
Set app = SapGuiAuto.GetScriptingEngine
If Err.Number <> 0 Then
  out.WriteLine "ERROR: Cannot get scripting engine: " & Err.Description
  out.Close
  WScript.Quit 1
End If

out.WriteLine "connections=" & app.Children.Count
Dim i, j
For i = 0 To app.Children.Count - 1
  Set conn = app.Children(CInt(i))
  out.WriteLine "connection[" & i & "].sessions=" & conn.Children.Count
  For j = 0 To conn.Children.Count - 1
    Set sess = conn.Children(CInt(j))
    out.WriteLine "session[" & i & "," & j & "].Id=" & sess.Id
    out.WriteLine "session[" & i & "," & j & "].Info.SystemName=" & sess.Info.SystemName
    out.WriteLine "session[" & i & "," & j & "].Info.Client=" & sess.Info.Client
    out.WriteLine "session[" & i & "," & j & "].Info.User=" & sess.Info.User
    out.WriteLine "session[" & i & "," & j & "].Info.Transaction=" & sess.Info.Transaction
    out.WriteLine "session[" & i & "," & j & "].Info.Program=" & sess.Info.Program
    out.WriteLine "session[" & i & "," & j & "].wnd0.Text=" & sess.findById("wnd[0]").Text
    out.WriteLine "session[" & i & "," & j & "].status=" & sess.findById("wnd[0]/sbar").Text
  Next
Next

out.Close
