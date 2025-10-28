#!/usr/bin/env python3
"""Test that verbose mode doesn't change wizard behavior."""

import unittest
import tempfile
import os
from wizard.engine.runner import RealActionRunner


class TestVerboseBehavior(unittest.TestCase):
    """Test that verbose mode preserves command output."""

    def test_normal_mode_captures_output(self):
        """Normal mode should capture command output."""
        runner = RealActionRunner(verbose=False)
        result = runner.run_shell(['echo', 'test output'])

        self.assertEqual(result['returncode'], 0)
        self.assertEqual(result['stdout'].strip(), 'test output')
        self.assertEqual(result['stderr'], '')

    def test_verbose_mode_captures_output(self):
        """Verbose mode should ALSO capture command output."""
        runner = RealActionRunner(verbose=True)

        # Redirect stdout temporarily to suppress verbose output in test
        import sys
        from io import StringIO
        old_stdout = sys.stdout
        sys.stdout = StringIO()

        try:
            result = runner.run_shell(['echo', 'test output'])
        finally:
            sys.stdout = old_stdout

        # The key test: verbose mode must still capture output
        self.assertEqual(result['returncode'], 0)
        self.assertEqual(result['stdout'].strip(), 'test output')
        self.assertEqual(result['stderr'], '')

    def test_verbose_mode_reads_files(self):
        """Verbose mode should be able to read file contents via cat."""
        # Create a temp file with known content
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            f.write('config_value=12345\n')
            temp_path = f.name

        try:
            runner_normal = RealActionRunner(verbose=False)
            runner_verbose = RealActionRunner(verbose=True)

            # Redirect stdout for verbose mode
            import sys
            from io import StringIO
            old_stdout = sys.stdout
            sys.stdout = StringIO()

            try:
                result_normal = runner_normal.run_shell(['cat', temp_path])
                result_verbose = runner_verbose.run_shell(['cat', temp_path])
            finally:
                sys.stdout = old_stdout

            # Both should return the same content
            self.assertEqual(result_normal['stdout'], result_verbose['stdout'])
            self.assertEqual(result_normal['stdout'].strip(), 'config_value=12345')
            self.assertEqual(result_verbose['stdout'].strip(), 'config_value=12345')

        finally:
            os.unlink(temp_path)

    def test_verbose_mode_yaml_parsing(self):
        """Verbose mode should allow YAML parsing from command output."""
        # Create a temp YAML file
        yaml_content = """services:
  postgres:
    enabled: true
    port: 5432
"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(yaml_content)
            temp_path = f.name

        try:
            runner_verbose = RealActionRunner(verbose=True)

            # Redirect stdout
            import sys
            from io import StringIO
            old_stdout = sys.stdout
            sys.stdout = StringIO()

            try:
                result = runner_verbose.run_shell(['cat', temp_path])
            finally:
                sys.stdout = old_stdout

            # Should be able to parse the YAML from output
            import yaml
            parsed = yaml.safe_load(result['stdout'])

            self.assertIsNotNone(parsed)
            self.assertTrue(parsed['services']['postgres']['enabled'])
            self.assertEqual(parsed['services']['postgres']['port'], 5432)

        finally:
            os.unlink(temp_path)


if __name__ == '__main__':
    unittest.main()