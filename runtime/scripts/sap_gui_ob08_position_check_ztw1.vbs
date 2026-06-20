Option Explicit

Dim outPath, validFrom, rateType, currenciesArg
outPath = WScript.Arguments(0)
validFrom = WScript.Arguments(1)
rateType = WScript.Arguments(2)
currenciesArg = WScript.Arguments(3)

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

Dim tableId
tableId = "wnd[0]/usr/tblSAPL0SAPTCTRL_V_TCURR"

Sub CancelModalIfAny()
  On Error Resume Next
  If sess.Children.Count > 1 Then
    sess.findById("wnd[1]/tbar[0]/btn[12]").Press
    WScript.Sleep 300
  End If
  Err.Clear
End Sub

Function Cell(path)
  On Error Resume Next
  Cell = sess.findById(path).Text
  If Err.Number <> 0 Then
    Cell = "<ERR>"
    Err.Clear
  End If
End Function

Sub OpenPosition()
  On Error Resume Next
  sess.findById("wnd[0]/mbar/menu[2]/menu[4]").Select
  WScript.Sleep 500
  If Err.Number <> 0 Then
    out.WriteLine "ERROR: Cannot open position dialog: " & Err.Description
    out.Close
    WScript.Quit 1
  End If
  Err.Clear
End Sub

Sub DumpVisible(label)
  Dim row
  out.WriteLine "CHECK " & label
  For row = 0 To 8
    out.WriteLine " row=" & row & " " & _
      Cell(tableId & "/ctxtV_TCURR-KURST[0," & row & "]") & "/" & _
      Cell(tableId & "/ctxtV_TCURR-GDATU[1," & row & "]") & "/" & _
      Cell(tableId & "/ctxtV_TCURR-FCURR[5," & row & "]") & "/" & _
      Cell(tableId & "/ctxtV_TCURR-TCURR[10," & row & "]") & _
      " KURSM=" & Cell(tableId & "/txtRFCU9-KURSM[2," & row & "]") & _
      " KURSP=" & Cell(tableId & "/txtRFCU9-KURSP[7," & row & "]") & _
      " FFACT=" & Cell(tableId & "/txtRFCU9-*FFACT[4," & row & "]") & _
      " TFACT=" & Cell(tableId & "/txtRFCU9-*TFACT[9," & row & "]")
  Next
  out.WriteLine "status=" & sess.findById("wnd[0]/sbar").Text
End Sub

Sub PositionAndDump(fcurr)
  CancelModalIfAny
  OpenPosition
  sess.findById("wnd[1]/usr/sub:SAPLSPO4:0300/ctxtSVALD-VALUE[0,21]").Text = rateType
  sess.findById("wnd[1]/usr/sub:SAPLSPO4:0300/ctxtSVALD-VALUE[1,21]").Text = fcurr
  sess.findById("wnd[1]/usr/sub:SAPLSPO4:0300/ctxtSVALD-VALUE[2,21]").Text = "TWD"
  sess.findById("wnd[1]/usr/sub:SAPLSPO4:0300/ctxtSVALD-VALUE[3,21]").Text = validFrom
  sess.findById("wnd[1]/tbar[0]/btn[0]").Press
  WScript.Sleep 800
  DumpVisible fcurr
End Sub

out.WriteLine "transaction=" & sess.Info.Transaction
out.WriteLine "title=" & sess.findById("wnd[0]").Text
out.WriteLine "rateType=" & rateType
out.WriteLine "validFrom=" & validFrom

Dim currencies, i
currencies = Split(currenciesArg, ",")
For i = 0 To UBound(currencies)
  If Trim(currencies(i)) <> "" Then
    PositionAndDump Trim(currencies(i))
  End If
Next

CancelModalIfAny
out.Close
