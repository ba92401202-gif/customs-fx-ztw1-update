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

Sub DumpModal()
  On Error Resume Next
  If sess.Children.Count > 1 Then
    out.WriteLine "modalTitle=" & sess.findById("wnd[1]").Text
    out.WriteLine "modalStatus=" & sess.findById("wnd[1]/sbar").Text
  End If
  Err.Clear
End Sub

Sub FillRate(row, fcurr, rate)
  SetText tableId & "/ctxtV_TCURR-KURST[0," & row & "]", rateType
  SetText tableId & "/ctxtV_TCURR-GDATU[1," & row & "]", validFrom
  SetText tableId & "/txtRFCU9-KURSM[2," & row & "]", ""
  SetText tableId & "/ctxtV_TCURR-FCURR[5," & row & "]", fcurr
  SetText tableId & "/txtRFCU9-KURSP[7," & row & "]", rate
  SetText tableId & "/ctxtV_TCURR-TCURR[10," & row & "]", toCurrency
End Sub

Sub DumpRows(label, lastRow)
  Dim row
  out.WriteLine label
  For row = 0 To lastRow
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
End Sub

out.WriteLine "transaction=" & sess.Info.Transaction
out.WriteLine "titleBefore=" & sess.findById("wnd[0]").Text
out.WriteLine "rateType=" & rateType
out.WriteLine "validFrom=" & validFrom
out.WriteLine "toCurrency=" & toCurrency

Dim probeField
Set probeField = sess.findById(tableId & "/ctxtV_TCURR-KURST[0,0]")
If Err.Number <> 0 Then
  out.WriteLine "ERROR: New entries table is not available: " & Err.Description
  out.Close
  WScript.Quit 1
End If
Err.Clear

For i = 0 To pairCount - 1
  FillRate i, currList(i), rateList(i)
Next
DumpRows "afterFill", pairCount - 1

sess.findById("wnd[0]").sendVKey 0
WScript.Sleep 1000
out.WriteLine "statusAfterEnter=" & sess.findById("wnd[0]/sbar").Text
If sess.Children.Count > 1 Then
  out.WriteLine "STOP: Modal appeared after validation"
  DumpModal
  out.Close
  WScript.Quit 3
End If

sess.findById("wnd[0]/tbar[0]/btn[11]").Press
WScript.Sleep 1500
out.WriteLine "statusAfterSave=" & sess.findById("wnd[0]/sbar").Text
If sess.Children.Count > 1 Then
  out.WriteLine "STOP: Modal appeared after save"
  DumpModal
  out.Close
  WScript.Quit 3
End If

out.WriteLine "titleAfter=" & sess.findById("wnd[0]").Text
out.Close
