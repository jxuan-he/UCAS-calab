# Reuse Vivado's exported XSIM file list without opening the GUI/project again.
# Run once after exp14_vivado.tcl create + sim have exported the simulation.
param(
 [string]$VivadoBin='D:/vivado2025/2025.2/Vivado/bin',
 [string]$BuildRoot='build/exp14_final',
 [string[]]$Seeds=@('5500ff','5501ff','5527ff','550001','551234')
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$work=[IO.Path]::GetFullPath((Join-Path $repo $BuildRoot))
$sim=Join-Path $work 'project/exp14.sim/sim_1/behav/xsim'
if (!(Test-Path -LiteralPath (Join-Path $sim 'tb_top_vlog.prj'))) {throw 'Export simulation once with exp14_vivado.tcl sim first'}
$sourceConf=Get-Content -LiteralPath (Join-Path $repo '../output/exp14/soc_verify/soc_hs_bram/rtl/CONFREG/confreg.v') -Raw
$reports=Join-Path $work 'final_reports'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
Push-Location $sim
try {
 Set-Content -LiteralPath exp14_run.tcl -Value "run all`nquit" -Encoding ascii
 foreach ($seed in $Seeds) {
  $conf=$sourceConf -replace '(?m)^`define RANDOM_SEED[^\r\n]*',("``define RANDOM_SEED 23'h"+$seed)
  Set-Content -LiteralPath (Join-Path $work 'generated/confreg.v') -Value $conf -Encoding utf8
  & "$VivadoBin/xvlog.bat" --incr --relax -L uvm -prj tb_top_vlog.prj -log xvlog.log *> (Join-Path $reports "compile_$seed.log")
  if ($LASTEXITCODE -ne 0) {throw "xvlog failed seed=$seed"}
  & "$VivadoBin/xelab.bat" --incr --debug typical --relax --mt 4 -L xil_defaultlib -L blk_mem_gen_v8_4_12 -L uvm -L unisims_ver -L unimacro_ver -L secureip -L xpm --snapshot tb_top_behav xil_defaultlib.tb_top xil_defaultlib.glbl -log elaborate.log *> (Join-Path $reports "elaborate_$seed.log")
  if ($LASTEXITCODE -ne 0) {throw "xelab failed seed=$seed"}
  & "$VivadoBin/xsim.bat" tb_top_behav -tclbatch exp14_run.tcl -log (Join-Path $reports "sim_$seed.log") *> (Join-Path $reports "console_$seed.log")
  $result=Get-Content -LiteralPath (Join-Path $reports "sim_$seed.log") -Raw
  $points=[regex]::Matches($result,"Number 8'd\d+ Functional Test Point PASS").Count
  if ($LASTEXITCODE -ne 0 -or $points -ne 58 -or $result -notmatch '----PASS!!!' -or $result -match 'Fatal:|Error!!!') {throw "func failed seed=$seed points=$points"}
  "EXP14_FINAL_FUNC_PASS seed=$seed points=$points"
 }
} finally {Pop-Location}
