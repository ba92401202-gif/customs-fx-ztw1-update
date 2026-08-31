Option Explicit

Dim outPath, validFrom, rateType, toCurrency, ratePairsArg
outPath = WScript.Arguments(0)
validFrom = WScript.Arguments(1)
rateType = WScript.Arguments(2)
toCurrency = WScript.Arguments(3)
ratePairsArg = WScript.Arguments(4)

Dim fso, out
Set fso = CreateObject("Scripting.FileSystemObject")
Set out = fso.CreateTextFile(outPath, True, True)

' ratePairsArg format: CURR=RATE[,CURR=RATE...], e.g. USD=31.51,EUR=34.2
Dim pairItems, pairCount, currList(), rateList(), i, kv
pairItems = Split(ratePairsArg, ",")
ReDim currList(UBound(pairItems))
ReDim rateList(UBound(pairItems))
pairCount = 0
For i = 0 To UBound(pairItems)
  If Trim(pairItems(i)) <> "" Then
    kv = Split(pairItems(i), "=")
    If UBound(kv) <> 1 Or Trim(kv(0)) = "" Or Trim(kv(1)) = "" Then
      out.WriteLine "ERROR: Invalid currency rate pair: " & pairItems(i)
      out.Close
      WScript.Quit 1
    End If
    currList(pairCount) = UCase(Trim(kv(0)))
    rateList(pairCount) = Trim(kv(1))
    pairCount = pairCount + 1
  End If
Next
If pairCount = 0 Then
  out.WriteLine "ERROR: No currency rate pairs provided."
  out.Close
  WScript.Quit 1
End If

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

Sub SetText(path, value)
  On Error Resume Next
  sess.findById(path).Text = value
  If Err.Number <> 0 Then
    out.WriteLine "ERROR: Cannot set " & path & " = " & value & ": " & Err.Description
    out.Close
    WScript.Quit 1
  End If
  Err.Clear
End Sub

Sub PositionKey(fcurr)
  CancelModalIfAny
  sess.findById("wnd[0]/mbar/menu[2]/menu[4]").Select
  WScript.Sleep 500
  If Err.Number <> 0 Then
    out.WriteLine "ERROR: Cannot open position dialog for " & fcurr & ": " & Err.Description
    out.Close
    WScript.Quit 1
  End If
  Err.Clear
  sess.findById("wnd[1]/usr/sub:SAPLSPO4:0300/ctxtSVALD-VALUE[0,21]").Text = rateType
  sess.findById("wnd[1]/usr/sub:SAPLSPO4:0300/ctxtSVALD-VALUE[1,21]").Text = fcurr
  sess.findById("wnd[1]/usr/sub:SAPLSPO4:0300/ctxtSVALD-VALUE[2,21]").Text = toCurrency
  sess.findById("wnd[1]/usr/sub:SAPLSPO4:0300/ctxtSVALD-VALUE[3,21]").Text = validFrom
  sess.findById("wnd[1]/tbar[0]/btn[0]").Press
  WScript.Sleep 800
End Sub

Sub UpdateRate(fcurr, rate)
  PositionKey fcurr
  Dim kurst, gdatu, gotFcurr, tcurr
  kurst = Cell(tableId & "/ctxtV_TCURR-KURST[0,0]")
  gdatu = Cell(tableId & "/ctxtV_TCURR-GDATU[1,0]")
  gotFcurr = Cell(tableId & "/ctxtV_TCURR-FCURR[5,0]")
  tcurr = Cell(tableId & "/ctxtV_TCURR-TCURR[10,0]")
  out.WriteLine "before " & fcurr & ": " & kurst & "/" & gdatu & "/" & gotFcurr & "/" & tcurr & " KURSM=" & Cell(tableId & "/txtRFCU9-KURSM[2,0]") & " KURSP=" & Cell(tableId & "/txtRFCU9-KURSP[7,0]") & " FFACT=" & Cell(tableId & "/txtRFCU9-*FFACT[4,0]") & " TFACT=" & Cell(tableId & "/txtRFCU9-*TFACT[9,0]")
  If Not (kurst = rateType And gdatu = validFrom And gotFcurr = fcurr And tcurr = toCurrency) Then
    out.WriteLine "ERROR: Positioned row does not match target key for " & fcurr
    out.Close
    WScript.Quit 2
  End If
  SetText tableId & "/txtRFCU9-KURSP[7,0]", rate
  sess.findById("wnd[0]").sendVKey 0
  WScript.Sleep 500
  If sess.Children.Count > 1 Then
    out.WriteLine "STOP: Modal appeared after updating " & fcurr
    out.WriteLine "modalTitle=" & sess.findById("wnd[1]").Text
    out.Close
    WScript.Quit 3
  End If
  out.WriteLine "after " & fcurr & ": " & Cell(tableId & "/ctxtV_TCURR-KURST[0,0]") & "/" & Cell(tableId & "/ctxtV_TCURR-GDATU[1,0]") & "/" & Cell(tableId & "/ctxtV_TCURR-FCURR[5,0]") & "/" & Cell(tableId & "/ctxtV_TCURR-TCURR[10,0]") & " KURSM=" & Cell(tableId & "/txtRFCU9-KURSM[2,0]") & " KURSP=" & Cell(tableId & "/txtRFCU9-KURSP[7,0]") & " FFACT=" & Cell(tableId & "/txtRFCU9-*FFACT[4,0]") & " TFACT=" & Cell(tableId & "/txtRFCU9-*TFACT[9,0]")
End Sub

out.WriteLine "transaction=" & sess.Info.Transaction
out.WriteLine "titleBefore=" & sess.findById("wnd[0]").Text
out.WriteLine "rateType=" & rateType
out.WriteLine "validFrom=" & validFrom
out.WriteLine "toCurrency=" & toCurrency

For i = 0 To pairCount - 1
  UpdateRate currList(i), rateList(i)
Next

sess.findById("wnd[0]/tbar[0]/btn[11]").Press
WScript.Sleep 1500
out.WriteLine "statusAfterSave=" & sess.findById("wnd[0]/sbar").Text
If sess.Children.Count > 1 Then
  out.WriteLine "STOP: Modal appeared after save"
  out.WriteLine "modalTitle=" & sess.findById("wnd[1]").Text
  out.Close
  WScript.Quit 3
End If
out.WriteLine "titleAfter=" & sess.findById("wnd[0]").Text
out.Close
