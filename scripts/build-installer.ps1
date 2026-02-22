# ============================================================
# IceDownloader — Build Script (self-contained, no Chrome dep)
# Requirements: PowerShell 7+, Inno Setup 6
# ============================================================

$ErrorActionPreference = "Stop"
$ROOT     = Split-Path -Parent $PSScriptRoot
$EXT_DIR  = Join-Path $ROOT "IceDownloader"
$KEY_FILE = Join-Path $ROOT "key.pem"
$CRX_OUT  = Join-Path $ROOT "IceDownloader.crx"
$ISS_FILE = Join-Path $ROOT "installer.iss"
$INNO     = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ──────────────────────────────────────────────────────────────
# Byte array helpers (PowerShell + operator loses [byte[]] type)
# ──────────────────────────────────────────────────────────────
function Join-Bytes {
    param([byte[][]]$Arrays)
    $total = ($Arrays | Measure-Object -Property Length -Sum).Sum
    $out   = [byte[]]::new($total)
    $pos   = 0
    foreach ($a in $Arrays) {
        [System.Buffer]::BlockCopy($a, 0, $out, $pos, $a.Length)
        $pos += $a.Length
    }
    return $out
}

function ConvertTo-Varint([int64]$v) {
    $buf = [System.Collections.Generic.List[byte]]::new()
    do {
        $b = [byte]($v -band 0x7F)
        $v = [int64]($v -shr 7)
        if ($v -ne 0) { $b = $b -bor 0x80 }
        $buf.Add($b)
    } while ($v -ne 0)
    return [byte[]]$buf.ToArray()
}

function New-PbField([int64]$fieldNum, [byte[]]$data) {
    $tag = ($fieldNum -shl 3) -bor 2
    return Join-Bytes @( (ConvertTo-Varint $tag), (ConvertTo-Varint $data.Length), $data )
}

# ──────────────────────────────────────────────────────────────
# CRX3 packer
# ──────────────────────────────────────────────────────────────
function Build-CRX3([string]$ExtDir, [string]$KeyPem, [string]$Output) {

    # Zip the extension
    $tmpZip = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".zip")
    if (Test-Path $tmpZip) { Remove-Item $tmpZip }
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $ExtDir, $tmpZip,
        [System.IO.Compression.CompressionLevel]::Optimal, $false)
    [byte[]]$archive = [System.IO.File]::ReadAllBytes($tmpZip)
    Remove-Item $tmpZip

    # Load RSA key, export SubjectPublicKeyInfo DER
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem((Get-Content $KeyPem -Raw))
    [byte[]]$pubKeyDer = $rsa.ExportSubjectPublicKeyInfo()

    # crx_id = first 16 bytes of SHA-256(SPKI)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    [byte[]]$crxId = $sha.ComputeHash($pubKeyDer)[0..15]

    # SignedData protobuf { crx_id = field 1 }
    [byte[]]$signedDataProto = New-PbField 1 $crxId

    # Signing blob: "CRX3 SignedData\0" + uint32le(len(sdp)) + sdp + archive
    [byte[]]$magicStr  = [System.Text.Encoding]::ASCII.GetBytes("CRX3 SignedData")
    [byte[]]$magicNull = [byte[]](0x00)
    [byte[]]$sdLen     = [BitConverter]::GetBytes([uint32]$signedDataProto.Length)
    [byte[]]$blobToSign = Join-Bytes @($magicStr, $magicNull, $sdLen, $signedDataProto, $archive)

    # RSA-PKCS1-SHA256 signature
    [byte[]]$sig = $rsa.SignData($blobToSign,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    # AsymmetricKeyProof { public_key=1, signature=2 }
    [byte[]]$keyProof = Join-Bytes @( (New-PbField 1 $pubKeyDer), (New-PbField 2 $sig) )

    # CrxFileHeader { sha256_with_rsa=2 (tag=18), signed_header_data=10000 (tag=80002) }
    [byte[]]$tagVar    = ConvertTo-Varint 80002
    [byte[]]$sdLenVar  = ConvertTo-Varint $signedDataProto.Length
    [byte[]]$fileHeader = Join-Bytes @(
        (New-PbField 2 $keyProof),
        $tagVar, $sdLenVar, $signedDataProto
    )

    # Final CRX3 binary
    [byte[]]$crxMagic = 0x43, 0x72, 0x32, 0x34   # "Cr24"
    [byte[]]$ver      = [BitConverter]::GetBytes([uint32]3)
    [byte[]]$hdrSize  = [BitConverter]::GetBytes([uint32]$fileHeader.Length)
    [byte[]]$crx      = Join-Bytes @($crxMagic, $ver, $hdrSize, $fileHeader, $archive)
    [System.IO.File]::WriteAllBytes($Output, $crx)

    $rsa.Dispose(); $sha.Dispose()
}

# ──────────────────────────────────────────────────────────────
# Compute Extension ID from key.pem
# ──────────────────────────────────────────────────────────────
function Get-ExtensionId([string]$KeyPem) {
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem((Get-Content $KeyPem -Raw))
    $spki = $rsa.ExportSubjectPublicKeyInfo()
    $rsa.Dispose()
    $sha  = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($spki)
    $sha.Dispose()
    $map  = '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'
    $lmap = 'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p'
    $hex  = ($hash[0..15] | ForEach-Object { $_.ToString('x2') }) -join ''
    return -join ($hex.ToCharArray() | ForEach-Object {
        $lmap[$map.IndexOf("$_")]
    })
}

# ══════════════════════════════════════════════════════════════
Write-Host "`n=== IceDownloader Build ===" -ForegroundColor Cyan

# Step 1: Rust
Write-Host "`n[1/5] Building Rust daemon..." -ForegroundColor Yellow
Push-Location (Join-Path $ROOT "ice-daemon")
cargo build --release
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Rust build failed" }
Pop-Location
Write-Host "      OK" -ForegroundColor Green

# Step 2: Key
Write-Host "[2/5] Checking RSA key..." -ForegroundColor Yellow
if (-not (Test-Path $KEY_FILE)) {
    $r = [System.Security.Cryptography.RSA]::Create(2048)
    Set-Content $KEY_FILE -Value $r.ExportRSAPrivateKeyPem() -Encoding UTF8 -NoNewline
    $r.Dispose()
    Write-Host "      key.pem generated — do NOT commit to a public repo!" -ForegroundColor Red
} else {
    Write-Host "      Reusing key.pem" -ForegroundColor Green
}

# Step 3: Extension ID
Write-Host "[3/5] Computing extension ID..." -ForegroundColor Yellow
$EXT_ID = Get-ExtensionId $KEY_FILE
Write-Host "      Extension ID: $EXT_ID" -ForegroundColor Green

# Step 4: CRX3
Write-Host "[4/5] Packing CRX3..." -ForegroundColor Yellow
Build-CRX3 -ExtDir $EXT_DIR -KeyPem $KEY_FILE -Output $CRX_OUT
$kb = [math]::Round((Get-Item $CRX_OUT).Length / 1KB, 1)
Write-Host "      OK → $CRX_OUT ($kb KB)" -ForegroundColor Green

# Step 5: Inno Setup
Write-Host "[5/5] Building installer..." -ForegroundColor Yellow
$iss = Get-Content $ISS_FILE -Raw
$iss = $iss -replace '#define EXTENSION_ID "[^"]*"', "#define EXTENSION_ID `"$EXT_ID`""
Set-Content $ISS_FILE -Value $iss -Encoding UTF8
& $INNO $ISS_FILE
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed" }

$out = "$Env:USERPROFILE\Documents\Inno Setup Examples Output\IceDownloaderSetup.exe"
Write-Host "`n=== Done! ===" -ForegroundColor Cyan
Write-Host "Extension ID : $EXT_ID"
Write-Host "Installer    : $out"
Write-Host "`n[!] key.pem must not change between releases." -ForegroundColor DarkYellow
