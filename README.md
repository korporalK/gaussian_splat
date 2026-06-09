# High-Performance 3D Gaussian Splatting Pipeline

This repository hosts a standardized, high-performance pipeline for reconstructing physical scenes into **3D Gaussian Splats (3DGS)** from video inputs. The pipeline automates frame extraction, blur-filtering, Structure-from-Motion (SfM) camera registration, and neural rendering optimization.

---

## 📂 Directory Structure

The project is structured around a portable, per-project architecture under the `projects/` directory.

```
gaussian_splat/
  ├── colmap/                  # Local CUDA-enabled COLMAP 4.0.2 binaries
  ├── gplat-env/               # Portable Conda environment (Python 3.10 + CUDA 12.1)
  ├── gsplat_src/              # gsplat source code library
  ├── scripts/                 # Core automation & execution scripts
  │     ├── setup_env.ps1      # Environment setup script
  │     ├── update_colmap.ps1  # COLMAP binary deployment script
  │     ├── preprocess.py      # Video frame extraction & filtering pipeline
  │     └── reconstruct.ps1     # Unified reconstruction orchestrator
  └── projects/                # Scene dataset folders
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

The pipeline runs on **Windows (PowerShell)**. To set up the Conda environment, PyTorch, local CUDA toolkit, required dependencies, and COLMAP binaries, execute the following script from the root folder:

```powershell
.\scripts\setup_env.ps1
```

*This script installs a self-contained CUDA toolkit locally in the Conda environment and downloads pre-built `gsplat` wheels, eliminating the need to install a host Microsoft Visual Studio compiler.*

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
