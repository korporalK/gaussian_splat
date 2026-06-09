# Unified Orchestration Script to Reconstruct any scene using the High-Performance Pipeline
param (
    [string]$ProjectName = "computer_table",
    [int]$DataFactor = 2,
    [int]$MaxSteps = 20000,
    [string]$Strategy = "mcmc"
)

$ErrorActionPreference = "Stop"

$RootDir = (Resolve-Path "$PSScriptRoot\..").Path
$PythonExe = "$RootDir\gsplat-env\python.exe"
$ColmapExe = "$RootDir\colmap\bin\colmap.exe"
$ProjectDir = "$RootDir\projects\$ProjectName"
$DatabasePath = "$ProjectDir\database.db"
$ImagesDir = "$ProjectDir\images"
$SparseDir = "$ProjectDir\sparse"

function Get-Timestamp {
    return (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

Write-Output "[$(Get-Timestamp)] ============================================"
Write-Output "[$(Get-Timestamp)]    Starting reconstruction for: $ProjectName"
Write-Output "[$(Get-Timestamp)] ============================================"

# --- Step 1: Preprocessing video ---
Write-Output "`n[$(Get-Timestamp)] ============================================"
Write-Output "[$(Get-Timestamp)]    Step 1: Running video preprocessing      "
Write-Output "[$(Get-Timestamp)] ============================================"

$InputFolder = "$ProjectDir\input"
if (-not (Test-Path $InputFolder)) {
    Write-Error "Project input directory not found: $InputFolder"
    exit 1
}

# Find any video file (mp4, webm, mov, avi) in the input directory
$VideoFile = (Get-ChildItem -Path $InputFolder -File | Where-Object { $_.Extension -match '\.(mp4|webm|mov|avi)$' } | Select-Object -First 1).FullName

if (-not $VideoFile) {
    Write-Output "[$(Get-Timestamp)] No video file found in $InputFolder. Skipping video frame extraction."
} else {
    Write-Output "[$(Get-Timestamp)] Found input video: $VideoFile"
    & $PythonExe -u "$PSScriptRoot\preprocess.py" --video_path "$VideoFile" --output_dir "$ProjectDir"
}

# --- Step 2: Feature Extraction ---
Write-Output "`n[$(Get-Timestamp)] ============================================"
Write-Output "[$(Get-Timestamp)]    Step 2: COLMAP SIFT Feature Extraction   "
Write-Output "[$(Get-Timestamp)] ============================================"
if (Test-Path $DatabasePath) {
    Remove-Item -Path $DatabasePath -Force
}

if (-not (Test-Path $ImagesDir)) {
    Write-Error "Images directory does not exist: $ImagesDir"
    exit 1
}

# Extract SIFT features on the images (limit resolution for fast execution but mapping back to original coordinates)
& $ColmapExe feature_extractor `
    --database_path $DatabasePath `
    --image_path $ImagesDir `
    --FeatureExtraction.use_gpu 1 `
    --FeatureExtraction.max_image_size 1920 `
    --FeatureExtraction.num_threads 16 `
    --SiftExtraction.max_num_features 8192

# --- Step 3: Feature Matching ---
Write-Output "`n[$(Get-Timestamp)] ============================================"
Write-Output "[$(Get-Timestamp)]    Step 3: COLMAP Feature Matching          "
Write-Output "[$(Get-Timestamp)] ============================================"
# Sequential matching with loop detection since video frames are sequential.
& $ColmapExe sequential_matcher `
    --database_path $DatabasePath `
    --FeatureMatching.use_gpu 1 `
    --SequentialMatching.overlap 15 `
    --SequentialMatching.loop_detection 1

# --- Step 4: SfM Mapping (GLOMAP with Fallback) ---
Write-Output "`n[$(Get-Timestamp)] ============================================"
Write-Output "[$(Get-Timestamp)]    Step 4: COLMAP SfM Mapping               "
Write-Output "[$(Get-Timestamp)] ============================================"
if (Test-Path $SparseDir) {
    Remove-Item -Path $SparseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $SparseDir | Out-Null

# Run GLOMAP Global Mapper first
& $ColmapExe global_mapper `
    --database_path $DatabasePath `
    --image_path $ImagesDir `
    --output_path $SparseDir

# Verify SfM reconstruction
$ModelDir = "$SparseDir\0"
if (-not (Test-Path $ModelDir)) {
    Write-Output "[$(Get-Timestamp)] GLOMAP global mapper did not generate a sparse model folder sparse/0."
    Write-Output "[$(Get-Timestamp)] Falling back to COLMAP Incremental Mapper for maximum robustness..."
    & $ColmapExe mapper `
        --database_path $DatabasePath `
        --image_path $ImagesDir `
        --output_path $SparseDir
}

# Verify again after fallback
if (-not (Test-Path $ModelDir)) {
    $SubDirs = Get-ChildItem -Path $SparseDir -Directory
    if ($SubDirs.Count -gt 0) {
        $ModelDir = $SubDirs[0].FullName
        Write-Output "[$(Get-Timestamp)] Found SfM reconstruction model folder at: $ModelDir"
    } else {
        Write-Error "SfM Reconstruction FAILED: No sparse reconstruction models found! Check if camera matching succeeded."
        exit 1
    }
}

# Verify the necessary binary files are present and contain valid content (size > 100 bytes)
$RequiredFiles = @("cameras.bin", "images.bin", "points3D.bin")
foreach ($file in $RequiredFiles) {
    $filePath = Join-Path $ModelDir $file
    if (-not (Test-Path $filePath)) {
        Write-Error "SfM Verification FAILED: Missing required file $file at $filePath"
        exit 1
    }
    $fileSize = (Get-Item $filePath).Length
    if ($fileSize -lt 100) {
        Write-Error "SfM Verification FAILED: File $file at $filePath is empty or trivial ($fileSize bytes). Camera registration failed!"
        exit 1
    }
}
Write-Output "[$(Get-Timestamp)] SfM Verification: SUCCESS"

# Rename model dir to "0" if it was named differently
$StandardModelDir = Join-Path $SparseDir "0"
if ($ModelDir -ne $StandardModelDir) {
    Write-Output "[$(Get-Timestamp)] Moving reconstruction model to standard sparse/0 folder..."
    Rename-Item -Path $ModelDir -NewName "0"
}

# --- Step 5: Run gsplat Trainer ---
Write-Output "`n[$(Get-Timestamp)] ============================================"
Write-Output "[$(Get-Timestamp)]    Step 5: Running gsplat $Strategy Trainer      "
Write-Output "[$(Get-Timestamp)] ============================================"

$TrainerScript = "$RootDir\gsplat_src\examples\simple_trainer.py"
$ResultDir = "$ProjectDir\splats"

# Determine eval, save, and ply steps based on MaxSteps
$HalfSteps = [int]($MaxSteps / 2)

& $PythonExe -u $TrainerScript $Strategy `
    --data_dir $ProjectDir `
    --result_dir $ResultDir `
    --data_factor $DataFactor `
    --max_steps $MaxSteps `
    --eval_steps $HalfSteps $MaxSteps `
    --save_steps $HalfSteps $MaxSteps `
    --ply_steps $HalfSteps $MaxSteps `
    --pose_opt `
    --antialiased `
    --app_opt `
    --save_ply

Write-Output "`n[$(Get-Timestamp)] ============================================"
Write-Output "[$(Get-Timestamp)]    Reconstruction Completed Successfully!   "
Write-Output "[$(Get-Timestamp)] ============================================"
