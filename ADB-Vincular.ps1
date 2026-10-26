Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Find-Adb {
    # 1) variable ADB_PATH  2) PATH  3) winget  4) Android SDK
    if ($env:ADB_PATH -and (Test-Path $env:ADB_PATH)) { return $env:ADB_PATH }
    $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @()
    $candidates += Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools*\platform-tools\adb.exe" -ErrorAction SilentlyContinue
    foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk")) {
        if ($sdk) { $candidates += Get-Item (Join-Path $sdk "platform-tools\adb.exe") -ErrorAction SilentlyContinue }
    }
    if ($candidates.Count -gt 0) { return $candidates[0].FullName }
    return $null
}

$ADB = Find-Adb
if (-not $ADB) {
    [System.Windows.Forms.MessageBox]::Show(
        "No se encontro adb.exe.`n`nInstalalo con:`n  winget install Google.PlatformTools`n`no define la variable de entorno ADB_PATH.",
        "ADB no encontrado") | Out-Null
    exit 1
}

. (Join-Path $PSScriptRoot "ADB-QR-Encoder.ps1")
. (Join-Path $PSScriptRoot "ADB-Mdns.ps1")

$form = New-Object System.Windows.Forms.Form
$form.Text            = "ADB - Depuracion Inalambrica"
$form.Size            = New-Object System.Drawing.Size(430, 475)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.TopMost         = $true
$form.BackColor       = [System.Drawing.Color]::FromArgb(25, 25, 25)

$lbTitle = New-Object System.Windows.Forms.Label
$lbTitle.Text      = "Conectar celular por Wi-Fi"
$lbTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$lbTitle.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
$lbTitle.Location  = New-Object System.Drawing.Point(20, 12)
$lbTitle.Size      = New-Object System.Drawing.Size(390, 30)
$form.Controls.Add($lbTitle)

$lbSub = New-Object System.Windows.Forms.Label
$lbSub.Text      = "Ya vinculado? SOLO CONECTAR (puerto vacio = lo busca solo). Primera vez? QR."
$lbSub.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lbSub.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 140)
$lbSub.Location  = New-Object System.Drawing.Point(20, 44)
$lbSub.Size      = New-Object System.Drawing.Size(390, 18)
$form.Controls.Add($lbSub)

function Add-Field($label, $y, $default) {
    $lb = New-Object System.Windows.Forms.Label
    $lb.Text      = $label
    $lb.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $lb.ForeColor = [System.Drawing.Color]::Silver
    $lb.Location  = New-Object System.Drawing.Point(20, $y)
    $lb.Size      = New-Object System.Drawing.Size(165, 22)
    $form.Controls.Add($lb)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text        = $default
    $tb.Font        = New-Object System.Drawing.Font("Consolas", 11)
    $tb.Location    = New-Object System.Drawing.Point(190, ($y - 2))
    $tb.Size        = New-Object System.Drawing.Size(210, 26)
    $tb.BackColor   = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $tb.ForeColor   = [System.Drawing.Color]::White
    $tb.BorderStyle = "FixedSingle"
    $form.Controls.Add($tb)
    return $tb
}

# Ultima IP:puerto que conecto (el puerto solo cambia si se reinicia la depuracion inalambrica)
$lastFile = Join-Path $PSScriptRoot "ADB-ultima-conexion.txt"
$lastIp = ""; $lastPort = ""
if (Test-Path $lastFile) {
    $parts = (Get-Content $lastFile -Raw).Trim() -split ":"
    if ($parts.Count -eq 2) { $lastIp = $parts[0]; $lastPort = $parts[1] }
}

$txtIP       = Add-Field "IP del celular:"        78  $lastIp
$txtConnPort = Add-Field "Puerto conexion TCP:"   110 $lastPort
$txtPairPort = Add-Field "Puerto vinculacion:"    148 ""
$txtCode     = Add-Field "Codigo de 6 digitos:"   180 ""

# Etiquetas de seccion
$lbSec1 = New-Object System.Windows.Forms.Label
$lbSec1.Text = "^ pantalla principal (Direccion IP y puerto)"
$lbSec1.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$lbSec1.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$lbSec1.Location = New-Object System.Drawing.Point(190, 134)
$lbSec1.Size = New-Object System.Drawing.Size(220, 14)
$form.Controls.Add($lbSec1)

$lbSec2 = New-Object System.Windows.Forms.Label
$lbSec2.Text = "^ pantalla Vincular con codigo (solo 1a vez)"
$lbSec2.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$lbSec2.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$lbSec2.Location = New-Object System.Drawing.Point(190, 204)
$lbSec2.Size = New-Object System.Drawing.Size(220, 14)
$form.Controls.Add($lbSec2)

$con = New-Object System.Windows.Forms.RichTextBox
$con.Location    = New-Object System.Drawing.Point(20, 225)
$con.Size        = New-Object System.Drawing.Size(385, 85)
$con.ReadOnly    = $true
$con.BackColor   = [System.Drawing.Color]::FromArgb(10, 10, 10)
$con.ForeColor   = [System.Drawing.Color]::LimeGreen
$con.Font        = New-Object System.Drawing.Font("Consolas", 9)
$con.BorderStyle = "FixedSingle"
$form.Controls.Add($con)

function Log($msg, $col) {
    if (-not $col) { $col = "LimeGreen" }
    $con.SelectionStart  = $con.TextLength
    $con.SelectionLength = 0
    $con.SelectionColor  = [System.Drawing.Color]::$col
    $con.AppendText("$msg`n")
    $con.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Do-Connect($ip, $cport) {
    if (-not $cport) {
        Log "[>] Sin puerto: preguntando al celular ($ip) por mDNS..." "Cyan"
        $svc = $null
        for ($i = 0; $i -lt 3 -and -not $svc; $i++) {
            $svc = Find-AdbService "connect" "" $ip $ip
            [System.Windows.Forms.Application]::DoEvents()
        }
        if (-not $svc) {
            Log "[!] El celular no responde. Pantalla encendida, Depuracion" "Orange"
            Log "    inalambrica activada y misma red Wi-Fi?" "Orange"
            return $false
        }
        $cport = "$($svc.Port)"
        $script:txtConnPort.Text = $cport
        Log "    puerto encontrado: $cport" "Gray"
    }
    Log "[>] Conectando $ip`:$cport ..." "Cyan"
    $r = & $ADB connect "$ip`:$cport" 2>&1
    foreach ($l in $r) { Log "    $l" }
    if ("$r" -match "connected") {
        "$ip`:$cport" | Set-Content $lastFile
        Log "[OK] Conectado! Ya puedes depurar." "LimeGreen"
        return $true
    }
    # El puerto guardado puede estar viejo: se le pregunta al celular el vigente.
    Log "[>] Fallo. Buscando el puerto actual por mDNS..." "Cyan"
    $svc = Find-AdbService "connect" "" $ip $ip
    if ($svc -and "$($svc.Port)" -ne "$cport") {
        $script:txtConnPort.Text = "$($svc.Port)"
        $r = & $ADB connect "$ip`:$($svc.Port)" 2>&1
        foreach ($l in $r) { Log "    $l" }
        if ("$r" -match "connected") {
            "$ip`:$($svc.Port)" | Set-Content $lastFile
            Log "[OK] Conectado! (puerto actualizado a $($svc.Port))" "LimeGreen"
            return $true
        }
    }
    Log "[!] Fallo. Revisa IP/puerto o que Depuracion inalambrica este activa." "Orange"
    return $false
}

# ---- Boton SOLO CONECTAR ----
$btnConn = New-Object System.Windows.Forms.Button
$btnConn.Text      = "SOLO CONECTAR"
$btnConn.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnConn.Location  = New-Object System.Drawing.Point(20, 318)
$btnConn.Size      = New-Object System.Drawing.Size(185, 36)
$btnConn.BackColor = [System.Drawing.Color]::FromArgb(40, 110, 60)
$btnConn.ForeColor = [System.Drawing.Color]::White
$btnConn.FlatStyle = "Flat"
$btnConn.FlatAppearance.BorderSize = 0
$btnConn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnConn.Add_Click({
    $btnConn.Enabled = $false; $btnPair.Enabled = $false
    $con.Clear()
    Do-Connect $txtIP.Text.Trim() $txtConnPort.Text.Trim() | Out-Null
    $btnConn.Enabled = $true; $btnPair.Enabled = $true
})
$form.Controls.Add($btnConn)

# ---- Boton VINCULAR + CONECTAR ----
$btnPair = New-Object System.Windows.Forms.Button
$btnPair.Text      = "VINCULAR + CONECTAR"
$btnPair.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnPair.Location  = New-Object System.Drawing.Point(218, 318)
$btnPair.Size      = New-Object System.Drawing.Size(187, 36)
$btnPair.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$btnPair.ForeColor = [System.Drawing.Color]::White
$btnPair.FlatStyle = "Flat"
$btnPair.FlatAppearance.BorderSize = 0
$btnPair.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnPair.Add_Click({
    $ip    = $txtIP.Text.Trim()
    $pport = $txtPairPort.Text.Trim()
    $code  = $txtCode.Text.Trim()
    $cport = $txtConnPort.Text.Trim()

    if (-not $ip -or -not $pport -or -not $code) {
        Log "[!] Para vincular: IP + puerto vinculacion + codigo." "Orange"
        return
    }
    $btnConn.Enabled = $false; $btnPair.Enabled = $false
    $con.Clear()

    Log "[1] Vinculando $ip`:$pport  codigo=$code" "Cyan"
    $r = & $ADB pair "$ip`:$pport" $code 2>&1
    foreach ($l in $r) { Log "    $l" }

    if ("$r" -match "Successfully paired|success") {
        Log "[OK] Vinculado!" "LimeGreen"
        Do-Connect $ip $cport | Out-Null
    } else {
        Log "[!] Vinculacion fallo. El codigo expira en segundos:" "Orange"
        Log "    genera uno NUEVO y dale al boton de inmediato." "Orange"
    }
    $btnConn.Enabled = $true; $btnPair.Enabled = $true
})
$form.Controls.Add($btnPair)

# ---- Vincular escaneando QR ----
function New-RandomString([string]$chars, [int]$len) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object 'byte[]' $len
    $rng.GetBytes($buf)
    return -join ($buf | ForEach-Object { $chars[$_ % $chars.Length] })
}

function Invoke-AdbTimeout([string[]]$arguments, [int]$seconds) {
    # adb pair puede quedarse colgado; se corta a los N segundos.
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $ADB -ArgumentList $arguments -NoNewWindow -PassThru `
            -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $p.WaitForExit($seconds * 1000)) {
            try { $p.Kill() } catch {}
            return "Tiempo agotado (${seconds}s) esperando respuesta del celular."
        }
        return ((Get-Content $out -Raw) + (Get-Content $err -Raw)).Trim()
    } finally {
        Remove-Item $out, $err -ErrorAction SilentlyContinue
    }
}

function Get-MdnsEntries {
    # Lineas: nombre <tab> _adb-tls-pairing._tcp <tab> ip:puerto
    $entries = @()
    foreach ($l in (& $ADB mdns services 2>&1)) {
        if ("$l" -match '^(\S+)\s+(_adb-tls-(?:pairing|connect)\._tcp)\.?\s+(\d+\.\d+\.\d+\.\d+):(\d+)') {
            $entries += [pscustomobject]@{ Name = $Matches[1]; Kind = $Matches[2]; Ip = $Matches[3]; Port = $Matches[4] }
        }
    }
    return $entries
}

function Show-QrDialog {
    $script:qrName = "ADBQR" + (New-RandomString "0123456789" 6)
    $script:qrPass = New-RandomString "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789" 10
    $script:qrState = "scan"       # scan -> connect -> done
    $script:qrIp = $null
    $script:qrBusy = $false
    $script:qrTicks = 0
    $script:qrConnectTicks = 0

    $payload = "WIFI:T:ADB;S:$($script:qrName);P:$($script:qrPass);;"
    $bmp = New-QrBitmap $payload 7

    $script:qrForm = New-Object System.Windows.Forms.Form
    $script:qrForm.Text            = "Vincular con codigo QR"
    $script:qrForm.Size            = New-Object System.Drawing.Size(340, 470)
    $script:qrForm.StartPosition   = "CenterParent"
    $script:qrForm.FormBorderStyle = "FixedDialog"
    $script:qrForm.MaximizeBox     = $false
    $script:qrForm.MinimizeBox     = $false
    $script:qrForm.TopMost         = $true
    $script:qrForm.BackColor       = [System.Drawing.Color]::FromArgb(25, 25, 25)

    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Image    = $bmp
    $pic.SizeMode = "AutoSize"
    $pic.Location = New-Object System.Drawing.Point(((340 - 16 - $bmp.Width) / 2), 12)
    $script:qrForm.Controls.Add($pic)

    $steps = New-Object System.Windows.Forms.Label
    $steps.Text = "En el celular:`nAjustes > Opciones de desarrollador > Depuracion inalambrica > 'Vincular dispositivo con codigo QR' y apunta a este codigo."
    $steps.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $steps.ForeColor = [System.Drawing.Color]::Silver
    $steps.Location = New-Object System.Drawing.Point(16, 285)
    $steps.Size = New-Object System.Drawing.Size(300, 62)
    $script:qrForm.Controls.Add($steps)

    $script:qrStatus = New-Object System.Windows.Forms.Label
    $script:qrStatus.Text = "Esperando que el celular escanee el codigo..."
    $script:qrStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $script:qrStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
    $script:qrStatus.Location = New-Object System.Drawing.Point(16, 352)
    $script:qrStatus.Size = New-Object System.Drawing.Size(300, 40)
    $script:qrForm.Controls.Add($script:qrStatus)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text      = "Cancelar"
    $btnCancel.Location  = New-Object System.Drawing.Point(16, 398)
    $btnCancel.Size      = New-Object System.Drawing.Size(300, 28)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnCancel.ForeColor = [System.Drawing.Color]::Silver
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.Add_Click({ $script:qrForm.Close() })
    $script:qrForm.Controls.Add($btnCancel)

    $script:qrTimer = New-Object System.Windows.Forms.Timer
    $script:qrTimer.Interval = 1500
    $script:qrTimer.Add_Tick({
        if ($script:qrBusy -or $script:qrState -eq "done") { return }
        $script:qrBusy = $true
        try {
            $script:qrTicks++
            if ($script:qrState -eq "scan") {
                $svc = Find-AdbService "pairing" $script:qrName "" $txtIP.Text.Trim()
                if (-not $svc) { $svc = Get-MdnsEntries | Where-Object { $_.Name -eq $script:qrName -and $_.Kind -eq "_adb-tls-pairing._tcp" } | Select-Object -First 1 }
                if ($svc) {
                    $script:qrStatus.Text = "Celular detectado ($($svc.Ip)). Vinculando..."
                    $r = Invoke-AdbTimeout @("pair", "$($svc.Ip):$($svc.Port)", $script:qrPass) 15
                    if ("$r" -match "Successfully paired|success") {
                        $script:qrIp = $svc.Ip
                        $script:qrState = "connect"
                        $script:qrStatus.Text = "Vinculado. Conectando..."
                    } else {
                        $script:qrStatus.Text = "Fallo al vincular: $("$r".Trim()). Reintentando..."
                    }
                } elseif ($script:qrTicks -eq 15) {
                    $script:qrStatus.Text = "Sin senal del celular. PC y celular deben estar en la misma red Wi-Fi."
                }
            }
            if ($script:qrState -eq "connect") {
                $script:qrConnectTicks++
                $ip = $script:qrIp
                $svc = Find-AdbService "connect" "" $ip $ip
                if (-not $svc) { $svc = Get-MdnsEntries | Where-Object { $_.Kind -eq "_adb-tls-connect._tcp" -and $_.Ip -eq $ip } | Select-Object -First 1 }
                $port = $null
                if ($svc) {
                    $port = $svc.Port
                    $r = & $ADB connect "$ip`:$port" 2>&1
                    $ok = "$r" -match "connected"
                } else {
                    # adb a veces conecta solo tras vincular
                    $ok = $false
                    foreach ($l in (& $ADB devices 2>&1)) {
                        if ("$l" -match "^$([regex]::Escape($ip)):(\d+)\s+device") { $ok = $true; $port = $Matches[1] }
                    }
                }
                if ($ok) {
                    $script:qrState = "done"
                    $txtIP.Text = $ip
                    if ($port) { $txtConnPort.Text = "$port"; "$ip`:$port" | Set-Content $lastFile }
                    $con.Clear()
                    Log "[OK] Vinculado y conectado por QR: $ip`:$port" "LimeGreen"
                    $script:qrForm.Close()
                } elseif ($script:qrConnectTicks -ge 12) {
                    $script:qrState = "done"
                    $con.Clear()
                    Log "[OK] Vinculado por QR, pero no se pudo conectar solo." "Orange"
                    Log "    Pon el puerto de la pantalla principal y usa SOLO CONECTAR." "Orange"
                    $script:qrForm.Close()
                }
            }
        } finally {
            $script:qrBusy = $false
        }
    })

    & $ADB start-server 2>&1 | Out-Null
    $script:qrTimer.Start()
    $script:qrForm.ShowDialog($form) | Out-Null
    $script:qrTimer.Stop()
    $script:qrTimer.Dispose()
    $bmp.Dispose()
}

$btnQr = New-Object System.Windows.Forms.Button
$btnQr.Text      = "VINCULAR CON CODIGO QR"
$btnQr.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnQr.Location  = New-Object System.Drawing.Point(20, 360)
$btnQr.Size      = New-Object System.Drawing.Size(385, 36)
$btnQr.BackColor = [System.Drawing.Color]::FromArgb(110, 70, 170)
$btnQr.ForeColor = [System.Drawing.Color]::White
$btnQr.FlatStyle = "Flat"
$btnQr.FlatAppearance.BorderSize = 0
$btnQr.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnQr.Add_Click({ Show-QrDialog })
$form.Controls.Add($btnQr)

# ---- Boton reset / olvidar estado ----
$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text      = "Reiniciar servidor ADB"
$btnReset.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$btnReset.Location  = New-Object System.Drawing.Point(20, 404)
$btnReset.Size      = New-Object System.Drawing.Size(385, 26)
$btnReset.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnReset.ForeColor = [System.Drawing.Color]::Silver
$btnReset.FlatStyle = "Flat"
$btnReset.FlatAppearance.BorderSize = 0
$btnReset.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnReset.Add_Click({
    $con.Clear()
    Log "[*] Matando procesos adb..." "Gray"
    Get-Process adb -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    & $ADB start-server 2>&1 | Out-Null
    Log "[OK] Servidor ADB reiniciado limpio." "LimeGreen"
})
$form.Controls.Add($btnReset)

$form.AcceptButton = $btnConn
$form.Add_Shown({ $txtConnPort.Focus() })
$form.ShowDialog() | Out-Null
