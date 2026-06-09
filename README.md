# High-Performance 3D Gaussian Splatting Pipeline

This repository hosts a standardized, high-performance pipeline for reconstructing physical scenes into **3D Gaussian Splats (3DGS)** from video inputs. The pipeline automates frame extraction, blur-filtering, Structure-from-Motion (SfM) camera registration, and neural rendering optimization.

---

## 📂 Directory Structure

The repository contains only the core pipeline scripts and configuration. The local environment, third-party libraries, and dataset folders are generated dynamically during setup to keep the repository size lightweight.

```
gaussian_splat/
  ├── colmap/                  # [Generated] Local CUDA-enabled COLMAP 4.0.2 binaries
  ├── gplat-env/               # [Generated] Portable Conda environment (Python 3.10 + CUDA 12.1)
  ├── gsplat_src/              # [Generated] Shallow-cloned gsplat v1.5.2 (patched for Windows compatibility)
  ├── scripts/                 # [Tracked] Core automation & execution scripts
  │     ├── patches/           # [Tracked] Local patch files
  │     │     └── simple_trainer.py
  │     ├── setup_env.ps1      # Environment setup script
  │     ├── update_colmap.ps1  # COLMAP binary deployment script
  │     ├── preprocess.py      # Video frame extraction & filtering pipeline
  │     └── reconstruct.ps1    # Unified reconstruction orchestrator
  └── projects/                # [Ignored] Scene dataset folders (contains empty .gitkeep)
        ├── <project_name>/
        │     ├── input/       # Raw video file (mp4, webm, mov, etc.)
        │     ├── images/      # Preprocessed 4K frames (lossless PNG)
        │     ├── images_2/    # Downsampled 1080p target images (lossless PNG)
        │     ├── database.db  # COLMAP feature database
        │     ├── sparse/0/    # SfM sparse camera binaries (cameras.bin, points3D.bin)
        │     └── splats/      # Output splats (PLY files, videos, checkpoints)
```

---

## 🛠️ Setup & Installation

### Prerequisites
- **Operating System**: Windows 10 or 11 (PowerShell is required).
- **Hardware**: An NVIDIA GPU with CUDA support (strongly recommended to have at least 8GB of VRAM).
- **Git**: Git must be installed and available on your system `PATH` to fetch dependencies.

### Installation Steps

1. Clone this repository to your local machine.
2. Open PowerShell and allow script execution for this session (if your system policy restricts running scripts):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```
3. Run the setup script from the root folder:
   ```powershell
   .\scripts\setup_env.ps1
   ```

### What the Setup Script Automates:
*   **Miniconda Installation**: Installs Miniconda locally under your user profile if it's not already detected.
*   **Local Conda Environment (`gsplat-env`)**: Sets up a local Python 3.10 environment, installs PyTorch 2.4.1 (CUDA 12.1), and downloads standard pipeline packages.
*   **Precompiled `gsplat` Wheels**: Installs the precompiled binary wheels of `gsplat 1.5.2` directly, eliminating the need to have a host Microsoft Visual Studio C++ Compiler.
*   **Automated Windows Patching**: Shallow-clones the official `nerfstudio-project/gsplat` repository at version `v1.5.2` and applies a custom Windows compatibility patch to the training script (replacing `fused_ssim` with `torchmetrics` to prevent import/compilation failures on Windows).
*   **COLMAP binaries**: Downloads and configures local CUDA-enabled COLMAP 4.0.2 with GLOMAP integration into your root directory.

---

## 🚀 How to Use

### 1. Initialize a New Scene
1. Create a new directory inside `projects/` named after your scene (e.g., `projects/living_room/`).
2. Inside that directory, create an `input/` folder.
3. Place your raw input video (e.g., `living_room.mp4`) inside `projects/<project_name>/input/`.

### 2. Run the Unified Reconstruction
Run the unified `reconstruct.ps1` script. It automatically detects the video, extracts frames, performs COLMAP registration, and trains the Gaussian Splat model:

```powershell
# Reconstruct the scene with 1080p target training (DataFactor 2) and MCMC optimization:
.\scripts\reconstruct.ps1 -ProjectName "living_room" -DataFactor 2 -MaxSteps 20000

# Reconstruct the scene at full 4K resolution (DataFactor 1) for 10,000 steps:
.\scripts\reconstruct.ps1 -ProjectName "living_room" -DataFactor 1 -MaxSteps 10000
```

### Parameters:
*   `-ProjectName`: The folder name under `projects/` (defaults to `"computer_table"`).
*   `-DataFactor`: The downscaling ratio for training target images. `2` trains at 1080p (4x faster); `1` trains at original 4K resolution.
*   `-MaxSteps`: Total training iterations (defaults to `20000`).
*   `-Strategy`: Splat optimization strategy, e.g. `"mcmc"` (SOTA) or `"default"`.

---

## ⚙️ Core Scripts Reference

### 1. `setup_env.ps1`
Automates Miniconda installation, creates the local environment (`gsplat-env`), pulls PyTorch 2.4.1 (CUDA 12.1), pins compatible packages (`numpy 1.26.4`), builds the `pycolmap` dev branch, applies a Windows 64-bit binary layout alignment patch, and installs COLMAP 4.0.2 with GLOMAP.

### 2. `update_colmap.ps1`
Utility script to quickly download and extract the latest CUDA-enabled COLMAP release into the root directory.

### 3. `preprocess.py`
Processes the video in RAM to select sharp, distinct keyframes:
- **FFT High-Pass Filtering:** Discards blurry frames in real-time.
- **SSIM Comparison:** Ensures keyframes represent actual scene changes, preventing redundant/static frames.
- **Lossless Export:** Exports frames as `.png` to avoid compression artifacts that degrade neural rendering fidelity.

### 4. `reconstruct.ps1`
The primary orchestrator that coordinates the pipeline:
1.  Calls `preprocess.py` to populate images.
2.  Runs COLMAP feature extraction at dynamic resolutions (maximizes SIFT speed while registering camera matrices to full 4K coordinates).
3.  Executes sequential matcher with loop detection ($O(N)$ matching complexity suitable for video sequences).
4.  Runs GLOMAP (Global Mapping) for camera poses, falling back to incremental mapping if needed.
5.  Triggers the `gsplat` trainer with anti-aliasing, pose optimization, and appearance optimization enabled.

---

## 📊 Viewing the Splats
During training, the script spawns a real-time web viewer. You can navigate and inspect your training splat live at:
*   **http://localhost:8080**

The final output point clouds and rendered trajectories are saved to `projects/<project_name>/splats/`.
