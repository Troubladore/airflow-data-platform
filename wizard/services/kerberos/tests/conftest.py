"""Pytest configuration for Kerberos service tests."""

import pytest


def pytest_collection_modifyitems(session, config, items):
    """
    Prevent pytest from collecting test_kerberos from actions.py.

    The test_kerberos function in actions.py is an action function, not a test.
    Pytest mistakenly collects it because it starts with 'test_'.
    """
    # Filter out the false positive test_kerberos from actions.py
    items[:] = [
        item for item in items
        if not (item.name == 'test_kerberos' and 'actions.py' in str(item.fspath))
    ]
