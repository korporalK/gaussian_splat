# Consolidated Environment Setup Script for 3DGS on Windows

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$RootDir = (Resolve-Path "$PSScriptRoot\..").Path
$EnvPrefix = "$RootDir\gsplat-env"
$LocalPip = "$EnvPrefix\Scripts\pip.exe"
$LocalPython = "$EnvPrefix\python.exe"
$DestColmapDir = "$RootDir\colmap"

Write-Output "=============================================="
Write-Output "  Consolidated 3DGS & COLMAP Setup Script     "
Write-Output "=============================================="

# --- Step 1: Install Miniconda via winget if not present ---
Write-Output "`n=== Step 1: Checking/Installing Miniconda ==="
$CondaPaths = @(
    "$env:USERPROFILE\miniconda3\Scripts\conda.exe",
    "$env:USERPROFILE\AppData\Local\Miniconda3\Scripts\conda.exe"
)

$CondaPath = $null
foreach ($path in $CondaPaths) {
    if (Test-Path $path) {
        $CondaPath = $path
        break
    }
}

if (-not $CondaPath) {
    # Check WinGet package directories as fallback
    $WinGetDir = "$env:USERPROFILE\AppData\Local\Microsoft\WinGet\Packages"
    if (Test-Path $WinGetDir) {
        $CondaSearch = Get-ChildItem -Path $WinGetDir -Filter "conda.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($CondaSearch) {
            $CondaPath = $CondaSearch.FullName
        }
    }
}

if (-not $CondaPath) {
    Write-Output "Miniconda not detected. Installing via Winget..."
    winget install Anaconda.Miniconda3 --scope user --silent --accept-package-agreements --accept-source-agreements
    
    # Locate after install
    foreach ($path in $CondaPaths) {
        if (Test-Path $path) {
            $CondaPath = $path
            break
        }
    }
    if (-not $CondaPath) {
        Write-Error "Could not locate conda.exe after Winget installation. Please check your setup."
        exit 1
    }
}

Write-Output "Using conda.exe at: $CondaPath"

# Accept Conda Terms of Service for standard channels (silent configuration)
& $CondaPath tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main -ErrorAction SilentlyContinue
& $CondaPath tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r -ErrorAction SilentlyContinue
& $CondaPath tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2 -ErrorAction SilentlyContinue

# --- Step 2: Creating local gsplat-env conda environment ---
Write-Output "`n=== Step 2: Creating local conda environment ==="
if (Test-Path $EnvPrefix) {
    Write-Output "Local environment at $EnvPrefix already exists. Reusing it."
} else {
    Write-Output "Creating environment with python=3.10 and cmake=3.14.0..."
    & $CondaPath create -p $EnvPrefix python=3.10 cmake=3.14.0 -y
}

# --- Step 3: Installing FFmpeg & CUDA Toolkit ---
Write-Output "`n=== Step 3: Installing FFmpeg and CUDA Toolkit 12.1 inside environment ==="
& $CondaPath install -p $EnvPrefix ffmpeg -c conda-forge -y
& $CondaPath install -p $EnvPrefix cuda-toolkit=12.1.1 -c nvidia -y

# --- Step 4: Installing Pip Dependencies ---
Write-Output "`n=== Step 4: Installing Pip Dependencies (PyTorch, gsplat, viser, etc.) ==="

# Set CUDA_HOME environment variable to the local conda environment Library directory for build process
$env:CUDA_HOME = "$EnvPrefix\Library"

Write-Output "Installing basic tools (Ninja, Jaxtyping, Rich 14.3.4)..."
& $LocalPip install ninja jaxtyping rich==14.3.4

Write-Output "Installing PyTorch 2.4.1 (CUDA 12.1)..."
& $LocalPip install torch==2.4.1+cu121 torchvision==0.19.1+cu121 --extra-index-url https://download.pytorch.org/whl/cu121

Write-Output "Installing training & viewer dependencies (with NumPy 1.x compatibility)..."
& $LocalPip install "opencv-python<4.9" tyro viser scikit-learn torchmetrics imageio[ffmpeg] tqdm "plyfile<1.0" scikit-image pyyaml matplotlib splines tensorboard tensorly

Write-Output "Installing nerfview from git..."
& $LocalPip install git+https://github.com/nerfstudio-project/nerfview@4538024fe0d15fd1a0e4d760f3695fc44ca72787

Write-Output "Installing gsplat 1.5.2 (pre-compiled Windows binary wheel)..."
& $LocalPip install gsplat==1.5.2 --extra-index-url https://docs.gsplat.studio/whl/pt24cu121

Write-Output "Installing PyColmap from correct git commit and force-downgrading NumPy to 1.26.4 (camera tracking compatibility)..."
& $LocalPip install git+https://github.com/rmbrualla/pycolmap@cc7ea4b7301720ac29287dbe450952511b32125e numpy==1.26.4

# --- Step 4.5: Patching PyColmap scene_manager.py for Windows ---
Write-Output "`n=== Step 4.5: Patching PyColmap for Windows 64-bit struct compatibility ==="
& $LocalPython -c "
import os
path = os.path.join(r'$EnvPrefix', 'Lib', 'site-packages', 'pycolmap', 'scene_manager.py')
if os.path.exists(path):
    with open(path, 'r') as f:
        content = f.read()
    replacements = [
        ('struct.unpack(\'L\', f.read(8))', 'struct.unpack(\'Q\', f.read(8))'),
        ('struct.unpack(\'IiLL\', f.read(24))', 'struct.unpack(\'IiQQ\', f.read(24))'),
        ('struct.unpack(\'L\', f.read(8))[0]', 'struct.unpack(\'Q\', f.read(8))[0]'),
        ('struct.pack(\'L\',', 'struct.pack(\'Q\','),
        ('struct.Struct(\'IiLL\')', 'struct.Struct(\'IiQQ\')')
    ]
    for old, new in replacements:
        content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('pycolmap scene_manager.py successfully patched!')
else:
    print('Warning: pycolmap scene_manager.py not found to patch!')
"

# --- Step 5: Download & Install COLMAP 4.0.2 with GLOMAP ---
Write-Output "`n=== Step 5: Downloading & Installing COLMAP 4.0.2 (CUDA) ==="
$ZipUrl = "https://github.com/colmap/colmap/releases/download/4.0.2/colmap-x64-windows-cuda.zip"
$ZipPath = "$RootDir\colmap-4.0.2.zip"
$TempExtract = "$RootDir\colmap-temp"

# Checking if current version is already 4.0.2
$CurrentColmapExe = "$DestColmapDir\bin\colmap.exe"
$NeedsColmapUpdate = $true
if (Test-Path $CurrentColmapExe) {
    $VersionString = & $CurrentColmapExe help 2>&1 | Out-String
    if ($VersionString -match "COLMAP 4\.") {
        Write-Output "COLMAP 4.x already installed. Skipping download."
        $NeedsColmapUpdate = $false
    }
}

if ($NeedsColmapUpdate) {
    Write-Output "Downloading COLMAP 4.0.2 zip archive..."
    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath
    
    if (Test-Path $TempExtract) {
        Remove-Item -Path $TempExtract -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TempExtract | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $TempExtract
    
    Write-Output "Replacing old COLMAP folder..."
    Get-Process -Name "colmap" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (Test-Path $DestColmapDir) {
        Remove-Item -Path $DestColmapDir -Recurse -Force
    }
    
    $SubDirs = Get-ChildItem -Path $TempExtract -Directory
    if ($SubDirs.Count -eq 1) {
        Move-Item -Path $SubDirs[0].FullName -Destination $DestColmapDir
    } else {
        Move-Item -Path $TempExtract -Destination $DestColmapDir
    }
    
    # Cleanup zip and temp extraction folder
    Remove-Item -Path $TempExtract -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue
    Write-Output "COLMAP 4.0.2 successfully installed!"
}

# --- Step 5.5: Clone & Patch gsplat source (examples) ---
Write-Output "`n=== Step 5.5: Cloning & Patching gsplat source (examples) ==="
$GsplatSrcDir = "$RootDir\gsplat_src"
if (-not (Test-Path $GsplatSrcDir)) {
    Write-Output "Cloning gsplat repository (tag v1.5.2)..."
    & git clone --depth 1 --branch v1.5.2 https://github.com/nerfstudio-project/gsplat.git $GsplatSrcDir
} else {
    Write-Output "gsplat_src directory already exists."
}

# Copy the Windows-patched simple_trainer.py
$PatchSource = "$RootDir\scripts\patches\simple_trainer.py"
$PatchDest = "$GsplatSrcDir\examples\simple_trainer.py"
if (Test-Path $PatchSource) {
    Write-Output "Applying Windows compatibility patch to simple_trainer.py..."
    Copy-Item -Path $PatchSource -Destination $PatchDest -Force
    Write-Output "Patch applied successfully!"
} else {
    Write-Warning "Patch file not found at $PatchSource!"
}

# --- Step 6: Verify Environment & Executables ---
Write-Output "`n=== Step 6: Verifying Setup ==="
Write-Output "Verifying Python dependencies..."

$env:CUDA_HOME = "$EnvPrefix\Library"

& $LocalPython -c "
import sys
import torch
import gsplat
import pycolmap
import numpy
import yaml
import viser
import nerfview
import matplotlib
import skimage
import splines
import tensorboard
import tensorly

cuda_ok = torch.cuda.is_available()
print('--- Verification Results ---')
print('PyTorch CUDA Available:', cuda_ok)
if cuda_ok:
    print('CUDA Device:', torch.cuda.get_device_name(0))

# Verify that precompiled CUDA extension is successfully imported and operational
try:
    from gsplat import csrc
    print('gsplat CUDA backend successfully loaded (csrc.pyd available!)')
    gsplat_ok = True
except Exception as e:
    print('ERROR: gsplat CUDA backend failed to load! JIT compiler or DLL loading failed. Details:', e)
    gsplat_ok = False

print('gsplat Version:', gsplat.__version__)
print('pycolmap Version:', pycolmap.__version__)
print('numpy Version:', numpy.__version__)
print('All other imports (yaml, viser, nerfview, matplotlib, skimage, splines, tensorboard, tensorly) succeeded!')
print('----------------------------')

if not gsplat_ok:
    sys.exit(1)
"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python verification failed: gsplat CUDA backend could not be loaded!"
    exit 1
}

Write-Output "Verifying COLMAP executable..."
$NewColmapExe = "$DestColmapDir\bin\colmap.exe"
if (Test-Path $NewColmapExe) {
    $ColmapHelp = & $NewColmapExe help 2>&1 | Out-String
    if ($ColmapHelp -match "global_mapper") {
        Write-Output "COLMAP verification: SUCCESS (integrated GLOMAP/global_mapper detected!)"
    } else {
        Write-Warning "COLMAP verification: WARNING (colmap.exe found, but global_mapper command is missing!)"
    }
} else {
    Write-Error "COLMAP verification: FAILED (colmap.exe not found!)"
    exit 1
}

Write-Output "`nEnvironment setup completed successfully!"
