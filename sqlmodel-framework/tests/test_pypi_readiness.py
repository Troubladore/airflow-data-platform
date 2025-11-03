"""Tests to ensure the package is ready for PyPI publication."""

import tomllib
from pathlib import Path
import re


class TestPyPIReadiness:
    """Test suite to verify the package is ready for PyPI publication."""

    def test_pyproject_toml_exists(self):
        """Test that pyproject.toml exists in the correct location."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        assert pyproject_path.exists(), "pyproject.toml must exist"

    def test_python_version_is_pinned(self):
        """Test that Python version is properly pinned as required."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        requires_python = data.get("project", {}).get("requires-python", "")

        # Should be pinned to exact version as per requirements
        assert re.match(r"^==\d+\.\d+\.\d+$", requires_python), (
            f"Python version '{requires_python}' should be pinned (e.g., ==3.12.11)"
        )

    def test_python_classifiers_include_312(self):
        """Test that classifiers include Python 3.12."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        classifiers = data.get("project", {}).get("classifiers", [])

        assert "Programming Language :: Python :: 3.12" in classifiers, (
            "Classifier for Python 3.12 must be present"
        )

    def test_author_email_is_github_noreply(self):
        """Test that author email is the GitHub noreply email."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        authors = data.get("project", {}).get("authors", [])
        expected_email = "8116429+Troubladore@users.noreply.github.com"

        assert len(authors) > 0, "At least one author must be specified"

        author_email = authors[0].get("email", "")
        assert author_email == expected_email, (
            f"Author email should be '{expected_email}', got '{author_email}'"
        )

    def test_package_name_is_valid(self):
        """Test that package name follows PyPI naming conventions."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        name = data.get("project", {}).get("name", "")
        assert name == "sqlmodel-framework", "Package name should be 'sqlmodel-framework'"

        # Check it follows PyPI naming rules
        assert re.match(r"^[a-zA-Z0-9]([a-zA-Z0-9._-])*$", name), (
            f"Package name '{name}' doesn't follow PyPI naming conventions"
        )

    def test_version_is_valid_semver(self):
        """Test that version follows semantic versioning."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        version = data.get("project", {}).get("version", "")
        assert re.match(r"^\d+\.\d+\.\d+", version), (
            f"Version '{version}' doesn't follow semantic versioning (X.Y.Z)"
        )

    def test_build_system_is_configured(self):
        """Test that build system is properly configured."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        build_system = data.get("build-system", {})
        assert build_system.get("build-backend") == "hatchling.build", (
            "Build backend should be 'hatchling.build'"
        )
        assert "hatchling" in build_system.get("requires", []), (
            "Build requires should include 'hatchling'"
        )

    def test_package_discovery_configured(self):
        """Test that package discovery is properly configured for src layout."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        src_path = Path(__file__).parent.parent / "src" / "sqlmodel_framework"

        # Check that source directory exists
        assert src_path.exists(), f"Source package directory must exist at {src_path}"

        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        # Check if hatch is configured to find packages in src/
        hatch_config = data.get("tool", {}).get("hatch", {}).get("build", {})
        wheel_config = hatch_config.get("targets", {}).get("wheel", {})

        # Should specify packages correctly for src layout
        packages = wheel_config.get("packages", [])
        assert "src/sqlmodel_framework" in packages or "sqlmodel_framework" in packages, (
            f"Package discovery not configured correctly. Found packages: {packages}. "
            "Should include 'src/sqlmodel_framework' or 'sqlmodel_framework'"
        )

    def test_readme_exists(self):
        """Test that README file exists."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        readme_path = Path(__file__).parent.parent / "README.md"

        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        readme = data.get("project", {}).get("readme", "")
        assert readme == "README.md", "README should be specified as 'README.md'"
        assert readme_path.exists(), f"README file '{readme}' must exist"

    def test_license_is_specified(self):
        """Test that license is properly specified."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        license_info = data.get("project", {}).get("license", "")
        assert license_info, "License must be specified"
        assert license_info == "MIT", "License should be 'MIT'"

    def test_dependencies_are_specified(self):
        """Test that core dependencies are properly specified."""
        pyproject_path = Path(__file__).parent.parent / "pyproject.toml"
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)

        dependencies = data.get("project", {}).get("dependencies", [])

        # Check for core dependencies
        assert any("sqlmodel" in dep for dep in dependencies), (
            "sqlmodel must be in dependencies"
        )
        assert any("sqlalchemy" in dep for dep in dependencies), (
            "sqlalchemy must be in dependencies"
        )
        assert any("pydantic" in dep for dep in dependencies), (
            "pydantic must be in dependencies"
        )