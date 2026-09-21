"""Ordered action plans."""

from __future__ import annotations

from dotfiles.action import Action


class Plan:
    """Collect actions while preserving order and rejecting duplicate IDs."""

    def __init__(self, actions: list[Action] | None = None) -> None:
        self._actions: dict[str, Action] = {}

        for action in actions or []:
            self.add(action)

    def add(self, action: Action) -> Plan:
        """Add an action and return this plan for fluent construction."""
        if action.id in self._actions:
            raise ValueError(f"Duplicate action ID: {action.id}")

        self._actions[action.id] = action

        return self

    @property
    def actions(self) -> tuple[Action, ...]:
        """Return the ordered actions as an immutable view."""
        return tuple(self._actions.values())

    @property
    def empty(self) -> bool:
        """Return whether the plan contains no actions."""
        return not self._actions

    def for_platform(self, platform: str) -> Plan:
        """Return shared and platform-specific actions for the current host."""
        selected_actions = [
            action for action in self.actions if action.platform == "shared" or action.platform == platform
        ]

        return Plan(selected_actions)
