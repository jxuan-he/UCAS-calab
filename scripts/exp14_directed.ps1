param([string]$VivadoBin='D:/vivado2025/2025.2/Vivado/bin')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$work=Join-Path $repo 'build/exp14/directed'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location $work
try {
    $rtl=@('mycpu_top.v','IF_PC.v','IDU.v','CP0.v','control.v','regfile.v','alu.v','div_gen.v') | ForEach-Object {Join-Path $repo $_}
    $tb=@('tests/tb_exp14_fetch.sv','tests/tb_exp14_stress.sv') | ForEach-Object {Join-Path $repo $_}
    & "$VivadoBin/xvlog.bat" -sv -work xil_defaultlib @rtl @tb *> compile.log
    if ($LASTEXITCODE -ne 0) {throw 'xvlog failed; see compile.log'}
    Set-Content -LiteralPath run.tcl -Value "run all`nquit" -Encoding ascii
    foreach ($top in @('tb_exp14_fetch','tb_exp14_stress')) {
        & "$VivadoBin/xelab.bat" -relax -mt 4 -debug typical -s $top "xil_defaultlib.$top" *> "${top}_elaborate.log"
        if ($LASTEXITCODE -ne 0) {throw "xelab failed: $top"}
        & "$VivadoBin/xsim.bat" $top -tclbatch run.tcl -log "${top}.log" *> "${top}_console.log"
        if ($LASTEXITCODE -ne 0) {throw "xsim failed: $top"}
        $result=Get-Content -LiteralPath "${top}.log" -Raw
        if ($result -notmatch 'EXP14_(FETCH|STRESS)_PASS' -or $result -match 'Fatal:') {throw "directed check failed: $top"}
        $result -split "`n" | Where-Object {$_ -match 'EXP14_.*PASS'} | Write-Output
    }
} finally {Pop-Location}
