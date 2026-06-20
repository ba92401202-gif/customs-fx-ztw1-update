Option Explicit

Dim outPath
outPath = WScript.Arguments(0)

Dim fso, out
Set fso = CreateObject("Scripting.FileSystemObject")
Set out = fso.CreateTextFile(outPath, True, True)

On Error Resume Next
Dim SapGuiAuto, app, conn, sess
Set SapGuiAuto = GetObject("SAPGUI")
Set app = SapGuiAuto.GetScriptingEngine
Set conn = app.Children(0)
Set sess = conn.Children(0)
If Err.Number <> 0 Then
  out.WriteLine "ERROR: Cannot open SAP session: " & Err.Description
  out.Close
  WScript.Quit 1
End If
Err.Clear

If sess.Children.Count > 1 Then
  sess.findById("wnd[1]/tbar[0]/btn[12]").Press
  WScript.Sleep 300
End If

sess.findById("wnd[0]/mbar/menu[1]/menu[0]").Select
WScript.Sleep 1000

Sub DumpControl(ctrl, indent)
  On Error Resume Next
  Dim line, k, child
  line = String(indent, " ") & ctrl.Id & " | " & ctrl.Type
  If ctrl.Name <> "" Then line = line & " | name=" & ctrl.Name
  If ctrl.Text <> "" Then line = line & " | text=" & Replace(ctrl.Text, vbCrLf, " ")
  If ctrl.Tooltip <> "" Then line = line & " | tip=" & ctrl.Tooltip
  out.WriteLine line
  If ctrl.Children.Count > 0 Then
    For k = 0 To ctrl.Children.Count - 1
      Set child = ctrl.Children(CInt(k))
      DumpControl child, indent + 2
    Next
  End If
End Sub

out.WriteLine "transaction=" & sess.Info.Transaction
out.WriteLine "program=" & sess.Info.Program
out.WriteLine "title=" & sess.findById("wnd[0]").Text
out.WriteLine "status=" & sess.findById("wnd[0]/sbar").Text
DumpControl sess.findById("wnd[0]"), 0

out.Close
