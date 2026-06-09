import cv2
import numpy as np
import os
import shutil
import sys
from skimage.metrics import structural_similarity as ssim

import argparse

# Parameters
parser = argparse.ArgumentParser(description="In-Memory Streaming Preprocessing")
parser.add_argument("--video_path", type=str, default="projects/computer_table/input/computer_table.mp4", help="Path to input video file")
parser.add_argument("--output_dir", type=str, default="projects/computer_table", help="Project directory to save extracted images")
parser.add_argument("--fps", type=int, default=5, help="FPS to extract frames at")
args = parser.parse_args()

VIDEO_PATH = args.video_path
FINAL_DIR = os.path.join(args.output_dir, "images")
FINAL_DIR_1080P = os.path.join(args.output_dir, "images_2")
FPS = args.fps

FFT_THRESHOLD = 10.0
FFT_BOX_SIZE = 60
SSIM_MAX_THRESHOLD = 0.92

# Clean and create directories
for d in [FINAL_DIR, FINAL_DIR_1080P]:
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d, exist_ok=True)

print("=== Starting In-Memory Streaming Preprocessing ===", flush=True)
cap = cv2.VideoCapture(VIDEO_PATH)
if not cap.isOpened():
    print(f"Error: Could not open video file {VIDEO_PATH}", flush=True)
    sys.exit(1)

video_fps = cap.get(cv2.CAP_PROP_FPS)
frame_interval = max(1, int(round(video_fps / FPS)))
total_video_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

orig_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
orig_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
print(f"Original Video Resolution: {orig_w}x{orig_h}", flush=True)
print(f"Video Frame Count: {total_video_frames} | Video FPS: {video_fps:.2f} | Extracting at {FPS} FPS", flush=True)

frame_idx = 0
keyframe_count = 0
last_keyframe_gray_small = None

# Downscale settings for fast calculations
SSIM_DIM = 480  # Max dimension 480 for 16x faster SSIM calculation
FFT_DIM = 1080  # Max dimension 1080 for 4x faster FFT calculation
OUTPUT_1080P_DIM = 1920  # Max dimension 1920 for the cached 1080p images

def check_blur_fft(gray_img, threshold=10.0, box_size=60):
    (h, w) = gray_img.shape
    (cX, cY) = (int(w / 2.0), int(h / 2.0))
    fft = np.fft.fft2(gray_img)
    fftShift = np.fft.fftshift(fft)
    
    # Zero-out the low frequencies in the center
    fftShift[cY - box_size:cY + box_size, cX - box_size:cX + box_size] = 0
    
    # Inverse FFT to reconstruct high-pass image
    fftShift = np.fft.ifftshift(fftShift)
    recon = np.fft.ifft2(fftShift)
    
    # Calculate high-frequency magnitude
    magnitude = 20 * np.log(np.abs(recon) + 1e-8)
    mean_high_freq = np.mean(magnitude)
    return mean_high_freq >= threshold, mean_high_freq

processed_count = 0
sharp_count = 0

print("\n--- Streaming and Filtering Video Frames in RAM ---", flush=True)

while True:
    ret, frame = cap.read()
    if not ret:
        break
    
    if frame_idx % frame_interval == 0:
        processed_count += 1
        h, w = frame.shape[:2]
        
        # 1. Downscale to 1080p copy for FFT blur analysis (speeds up FFT by 4x)
        scale_fft = FFT_DIM / max(h, w)
        new_w_fft = int(w * scale_fft)
        new_h_fft = int(h * scale_fft)
        frame_fft = cv2.resize(frame, (new_w_fft, new_h_fft), interpolation=cv2.INTER_AREA)
        gray_fft = cv2.cvtColor(frame_fft, cv2.COLOR_BGR2GRAY)
        
        # 2. FFT blur filtering
        is_sharp, val = check_blur_fft(gray_fft, FFT_THRESHOLD, FFT_BOX_SIZE)
        if not is_sharp:
            # Discard blurry frame immediately, free memory
            frame_idx += 1
            continue
            
        sharp_count += 1
        
        # 3. Downscale to 480p copy for SSIM (speeds up SSIM by 16x)
        scale_ssim = SSIM_DIM / max(h, w)
        new_w_ssim = int(w * scale_ssim)
        new_h_ssim = int(h * scale_ssim)
        frame_ssim = cv2.resize(frame, (new_w_ssim, new_h_ssim), interpolation=cv2.INTER_AREA)
        gray_ssim = cv2.cvtColor(frame_ssim, cv2.COLOR_BGR2GRAY)
        
        # 4. SSIM keyframe selection
        if last_keyframe_gray_small is None:
            # First keyframe
            filename = f"frame_{keyframe_count:04d}.png"
            
            # Save original 4K image (PNG)
            out_path_4k = os.path.join(FINAL_DIR, filename)
            cv2.imwrite(out_path_4k, frame)
            
            # Save 1080p copy (PNG) to avoid runtime downscaling in training
            scale_1080p = OUTPUT_1080P_DIM / max(h, w)
            new_w_1080p = int(w * scale_1080p)
            new_h_1080p = int(h * scale_1080p)
            frame_1080p = cv2.resize(frame, (new_w_1080p, new_h_1080p), interpolation=cv2.INTER_AREA)
            
            out_path_1080p = os.path.join(FINAL_DIR_1080P, f"frame_{keyframe_count:04d}.png")
            cv2.imwrite(out_path_1080p, frame_1080p)
            
            last_keyframe_gray_small = gray_ssim
            keyframe_count += 1
            print(f"Selected starting keyframe: {filename} (Sharpness: {val:.2f})", flush=True)
        else:
            # Calculate SSIM against the last selected keyframe at 480p
            similarity = ssim(gray_ssim, last_keyframe_gray_small)
            if similarity < SSIM_MAX_THRESHOLD:
                filename = f"frame_{keyframe_count:04d}.png"
                
                # Save original 4K image (PNG)
                out_path_4k = os.path.join(FINAL_DIR, filename)
                cv2.imwrite(out_path_4k, frame)
                
                # Save 1080p copy (PNG) to avoid runtime downscaling in training
                scale_1080p = OUTPUT_1080P_DIM / max(h, w)
                new_w_1080p = int(w * scale_1080p)
                new_h_1080p = int(h * scale_1080p)
                frame_1080p = cv2.resize(frame, (new_w_1080p, new_h_1080p), interpolation=cv2.INTER_AREA)
                
                out_path_1080p = os.path.join(FINAL_DIR_1080P, f"frame_{keyframe_count:04d}.png")
                cv2.imwrite(out_path_1080p, frame_1080p)
                
                last_keyframe_gray_small = gray_ssim
                keyframe_count += 1
                print(f"Selected keyframe: {filename} (Similarity: {similarity:.4f}, Sharpness: {val:.2f})", flush=True)
                
        if processed_count % 50 == 0:
            print(f"Progress: Analyzed {processed_count} frames, Sharp: {sharp_count}, Selected keyframes: {keyframe_count}", flush=True)

    frame_idx += 1

cap.release()
print(f"\nCompleted preprocessing! Saved {keyframe_count} keyframes to {FINAL_DIR} (4K PNG) and {FINAL_DIR_1080P} (1080p PNG).", flush=True)
