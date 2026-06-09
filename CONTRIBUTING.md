# Contributing to High-Performance 3D Gaussian Splatting Pipeline

Thank you for your interest in contributing! We welcome all contributions, including bug reports, feature suggestions, documentation updates, and pull requests.

## How to Contribute

### 1. Reporting Bugs & Feature Requests
- Check the [Issues Page](https://github.com/korporalK/gaussian_splat/issues) to make sure your issue or suggestion hasn't already been reported.
- If it's a bug, please include:
  - Your GPU details, CUDA version, and Windows version.
  - Steps to reproduce the bug.
  - The exact error output or logs.
- If it's a feature request, describe the desired behavior and the use case.

### 2. Submitting Pull Requests (PRs)
1. Fork the repository and create your branch from `main`:
   ```bash
   git checkout -b feature/my-cool-feature
   ```
2. Make your changes.
3. Test your changes locally by running:
   - Environment setup script: `.\scripts\setup_env.ps1`
   - Reconstruction pipeline: `.\scripts\reconstruct.ps1 -ProjectName "<test_project>"`
4. Commit your changes with clear, descriptive commit messages.
5. Push your branch to your fork:
   ```bash
   git push origin feature/my-cool-feature
   ```
6. Open a Pull Request pointing to our `main` branch.

## Coding Style
- **Python**: Follow PEP 8 guidelines. Write clean, readable code with comments where appropriate.
- **PowerShell**: Follow clean script layout conventions, use descriptive variable names, and include appropriate error checking (`$ErrorActionPreference = "Stop"`).

## Licensing
By contributing to this project, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
