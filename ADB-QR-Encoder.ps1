# Codificador QR minimo (version 3, correccion M, modo byte, mascara 0).
# Capacidad: hasta 42 bytes ASCII. Suficiente para "WIFI:T:ADB;S:<nombre>;P:<clave>;;".

function New-QrMatrix([string]$Text) {
    $size = 29
    $dataCap = 44
    $ecLen = 26

    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    if ($bytes.Length -gt 42) { throw "Texto demasiado largo para QR v3-M ($($bytes.Length) > 42)" }

    # ---- bits de datos ----
    $bits = New-Object System.Collections.Generic.List[int]
    function AddBits([int]$val, [int]$n) { for ($i = $n - 1; $i -ge 0; $i--) { $bits.Add(($val -shr $i) -band 1) } }
    AddBits 4 4
    AddBits $bytes.Length 8
    foreach ($b in $bytes) { AddBits $b 8 }
    $term = [Math]::Min(4, $dataCap * 8 - $bits.Count)
    AddBits 0 $term
    while ($bits.Count % 8 -ne 0) { $bits.Add(0) }
    $data = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $bits.Count; $i += 8) {
        $v = 0; for ($j = 0; $j -lt 8; $j++) { $v = ($v -shl 1) -bor $bits[$i + $j] }
        $data.Add($v)
    }
    $pad = 0xEC
    while ($data.Count -lt $dataCap) { $data.Add($pad); if ($pad -eq 0xEC) { $pad = 0x11 } else { $pad = 0xEC } }

    # ---- Reed-Solomon en GF(256) ----
    $exp = New-Object 'int[]' 512
    $log = New-Object 'int[]' 256
    $x = 1
    for ($i = 0; $i -lt 255; $i++) {
        $exp[$i] = $x; $log[$x] = $i
        $x = $x -shl 1
        if ($x -band 0x100) { $x = $x -bxor 0x11D }
    }
    for ($i = 255; $i -lt 512; $i++) { $exp[$i] = $exp[$i - 255] }
    function GfMul([int]$a, [int]$b) { if ($a -eq 0 -or $b -eq 0) { return 0 }; return $exp[$log[$a] + $log[$b]] }

    $gen = New-Object 'int[]' $ecLen
    $gen[$ecLen - 1] = 1
    $root = 1
    for ($i = 0; $i -lt $ecLen; $i++) {
        for ($j = 0; $j -lt $ecLen; $j++) {
            $gen[$j] = GfMul $gen[$j] $root
            if ($j + 1 -lt $ecLen) { $gen[$j] = $gen[$j] -bxor $gen[$j + 1] }
        }
        $root = GfMul $root 2
    }
    $ec = New-Object 'int[]' $ecLen
    foreach ($b in $data) {
        $factor = $b -bxor $ec[0]
        for ($i = 0; $i -lt $ecLen - 1; $i++) { $ec[$i] = $ec[$i + 1] }
        $ec[$ecLen - 1] = 0
        for ($i = 0; $i -lt $ecLen; $i++) { $ec[$i] = $ec[$i] -bxor (GfMul $gen[$i] $factor) }
    }
    $all = New-Object System.Collections.Generic.List[int]
    $all.AddRange($data); $all.AddRange([int[]]$ec)

    # ---- matriz ----
    $m  = New-Object 'bool[,]' $size, $size   # [y,x]
    $fn = New-Object 'bool[,]' $size, $size
    function SetF([int]$xx, [int]$yy, [bool]$dark) { $m[$yy, $xx] = $dark; $fn[$yy, $xx] = $true }

    for ($i = 0; $i -lt $size; $i++) { SetF 6 $i ($i % 2 -eq 0); SetF $i 6 ($i % 2 -eq 0) }
    foreach ($c in @(@(3, 3), @(($size - 4), 3), @(3, ($size - 4)))) {
        for ($dy = -4; $dy -le 4; $dy++) { for ($dx = -4; $dx -le 4; $dx++) {
            $xx = $c[0] + $dx; $yy = $c[1] + $dy
            if ($xx -ge 0 -and $xx -lt $size -and $yy -ge 0 -and $yy -lt $size) {
                $d = [Math]::Max([Math]::Abs($dx), [Math]::Abs($dy))
                SetF $xx $yy ($d -ne 2 -and $d -ne 4)
            }
        } }
    }
    for ($dy = -2; $dy -le 2; $dy++) { for ($dx = -2; $dx -le 2; $dx++) {
        SetF (22 + $dx) (22 + $dy) ([Math]::Max([Math]::Abs($dx), [Math]::Abs($dy)) -ne 1)
    } }

    function DrawFormat([int]$fmt) {
        for ($i = 0; $i -le 5; $i++) { SetF 8 $i ((($fmt -shr $i) -band 1) -eq 1) }
        SetF 8 7 ((($fmt -shr 6) -band 1) -eq 1)
        SetF 8 8 ((($fmt -shr 7) -band 1) -eq 1)
        SetF 7 8 ((($fmt -shr 8) -band 1) -eq 1)
        for ($i = 9; $i -lt 15; $i++) { SetF (14 - $i) 8 ((($fmt -shr $i) -band 1) -eq 1) }
        for ($i = 0; $i -lt 8; $i++) { SetF ($size - 1 - $i) 8 ((($fmt -shr $i) -band 1) -eq 1) }
        for ($i = 8; $i -lt 15; $i++) { SetF 8 ($size - 15 + $i) ((($fmt -shr $i) -band 1) -eq 1) }
        SetF 8 ($size - 8) $true
    }
    DrawFormat 0

    # ---- colocar datos (zigzag) ----
    $idx = 0; $total = $all.Count * 8
    for ($right = $size - 1; $right -ge 1; $right -= 2) {
        if ($right -eq 6) { $right = 5 }
        for ($vert = 0; $vert -lt $size; $vert++) {
            for ($j = 0; $j -lt 2; $j++) {
                $xx = $right - $j
                $up = ((($right + 1) -band 2) -eq 0)
                if ($up) { $yy = $size - 1 - $vert } else { $yy = $vert }
                if (-not $fn[$yy, $xx] -and $idx -lt $total) {
                    $m[$yy, $xx] = ((($all[$idx -shr 3] -shr (7 - ($idx -band 7))) -band 1) -eq 1)
                    $idx++
                }
            }
        }
    }

    # ---- mascara 0: (x+y) par ----
    for ($yy = 0; $yy -lt $size; $yy++) { for ($xx = 0; $xx -lt $size; $xx++) {
        if (-not $fn[$yy, $xx] -and ((($xx + $yy) % 2) -eq 0)) { $m[$yy, $xx] = -not $m[$yy, $xx] }
    } }

    # ---- informacion de formato: ECC M (00) + mascara 0 ----
    $fdata = 0
    $rem = $fdata
    for ($i = 0; $i -lt 10; $i++) { $rem = ($rem -shl 1) -bxor (($rem -shr 9) * 0x537) }
    $fmt = ((($fdata -shl 10) -bor $rem) -bxor 0x5412)
    DrawFormat $fmt

    return , $m
}

function New-QrBitmap([string]$Text, [int]$Scale = 6) {
    Add-Type -AssemblyName System.Drawing
    $m = New-QrMatrix $Text
    $size = 29; $quiet = 4
    $px = ($size + 2 * $quiet) * $Scale
    $bmp = New-Object System.Drawing.Bitmap $px, $px
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    for ($y = 0; $y -lt $size; $y++) { for ($x = 0; $x -lt $size; $x++) {
        if ($m[$y, $x]) { $g.FillRectangle([System.Drawing.Brushes]::Black, ($x + $quiet) * $Scale, ($y + $quiet) * $Scale, $Scale, $Scale) }
    } }
    $g.Dispose()
    return $bmp
}
