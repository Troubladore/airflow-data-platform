"""Tests for the package build process."""

import subprocess
import sys
from pathlib import Path
import shutil
import tempfile


class TestBuildProcess:
    """Test suite for building the package distribution."""

    def test_build_tools_installed(self):
        """Test that build and twine are installed."""
        # Check if build is installed
        result = subprocess.run(
            [sys.executable, "-m", "build", "--version"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, "build tool must be installed (pip install build)"

        # Check if twine is installed
        result = subprocess.run(
            [sys.executable, "-m", "twine", "--version"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, "twine tool must be installed (pip install twine)"

    def test_build_creates_dist_directory(self):
        """Test that build creates a dist directory with wheel and sdist."""
        project_root = Path(__file__).parent.parent
        dist_dir = project_root / "dist"

        # Clean up any existing dist directory
        if dist_dir.exists():
            shutil.rmtree(dist_dir)

        # Run build
        result = subprocess.run(
            [sys.executable, "-m", "build"],
            cwd=project_root,
            capture_output=True,
            text=True
        )

        assert result.returncode == 0, f"Build failed: {result.stderr}"
        assert dist_dir.exists(), "dist directory should be created"

        # Check for wheel file
        wheel_files = list(dist_dir.glob("*.whl"))
        assert len(wheel_files) == 1, f"Expected 1 wheel file, found {len(wheel_files)}"
        assert "sqlmodel_framework-1.0.0" in wheel_files[0].name

        # Check for source distribution
        tar_files = list(dist_dir.glob("*.tar.gz"))
        assert len(tar_files) == 1, f"Expected 1 tar.gz file, found {len(tar_files)}"
        assert "sqlmodel-framework-1.0.0" in tar_files[0].name or "sqlmodel_framework-1.0.0" in tar_files[0].name

    def test_wheel_contains_correct_files(self):
        """Test that the built wheel contains the expected files."""
        project_root = Path(__file__).parent.parent
        dist_dir = project_root / "dist"

        # Ensure we have a built wheel
        if not dist_dir.exists() or not list(dist_dir.glob("*.whl")):
            subprocess.run(
                [sys.executable, "-m", "build"],
                cwd=project_root,
                capture_output=True
            )

        wheel_file = list(dist_dir.glob("*.whl"))[0]

        # Extract wheel to temp directory and check contents
        with tempfile.TemporaryDirectory() as tmpdir:
            import zipfile
            with zipfile.ZipFile(wheel_file, 'r') as zip_ref:
                zip_ref.extractall(tmpdir)

            # Check that sqlmodel_framework package is included
            package_path = Path(tmpdir) / "sqlmodel_framework"
            assert package_path.exists(), "sqlmodel_framework package should be in wheel"

            # Check for __init__.py
            init_file = package_path / "__init__.py"
            assert init_file.exists(), "__init__.py should be in package"

            # Check that tests are NOT included
            test_path = Path(tmpdir) / "tests"
            assert not test_path.exists(), "tests should not be included in wheel"

    def test_package_can_be_installed(self):
        """Test that the built package can be installed."""
        project_root = Path(__file__).parent.parent
        dist_dir = project_root / "dist"

        # Ensure we have a built wheel
        if not dist_dir.exists() or not list(dist_dir.glob("*.whl")):
            subprocess.run(
                [sys.executable, "-m", "build"],
                cwd=project_root,
                capture_output=True
            )

        wheel_file = list(dist_dir.glob("*.whl"))[0]

        # Create a virtual environment and install the package
        with tempfile.TemporaryDirectory() as tmpdir:
            venv_dir = Path(tmpdir) / "test_venv"

            # Create virtual environment
            subprocess.run(
                [sys.executable, "-m", "venv", str(venv_dir)],
                check=True
            )

            # Get path to python in venv
            if sys.platform == "win32":
                venv_python = venv_dir / "Scripts" / "python.exe"
            else:
                venv_python = venv_dir / "bin" / "python"

            # Install the wheel
            result = subprocess.run(
                [str(venv_python), "-m", "pip", "install", str(wheel_file)],
                capture_output=True,
                text=True
            )

            assert result.returncode == 0, f"Installation failed: {result.stderr}"

            # Test import
            result = subprocess.run(
                [str(venv_python), "-c", "import sqlmodel_framework; print('Import successful')"],
                capture_output=True,
                text=True
            )

            assert result.returncode == 0, f"Import failed: {result.stderr}"
            assert "Import successful" in result.stdout