"""Tests for host platform classification."""

from dotfiles.context import Context


def test_darwin_is_not_classified_as_windows():
    assert Context.determine_platform("darwin") == "unknown"


def test_supported_platforms_are_classified():
    assert Context.determine_platform("win32") == "windows"
    assert Context.determine_platform("linux") == "linux"
