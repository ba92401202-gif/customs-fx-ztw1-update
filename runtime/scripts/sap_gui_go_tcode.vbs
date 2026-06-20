Option Explicit

Dim tcode, outPath
tcode = WScript.Arguments(0)
outPath = WScript.Arguments(1)

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

sess.findById("wnd[0]/tbar[0]/okcd").Text = "/n" & tcode
sess.findById("wnd[0]").sendVKey 0
WScript.Sleep 2000

out.WriteLine "transaction=" & sess.Info.Transaction
out.WriteLine "program=" & sess.Info.Program
out.WriteLine "title=" & sess.findById("wnd[0]").Text
out.WriteLine "status=" & sess.findById("wnd[0]/sbar").Text
If sess.Children.Count > 1 Then
  out.WriteLine "modal=" & sess.findById("wnd[1]").Text
End If
out.Close
