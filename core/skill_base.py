"""
Skill base classes for the Meta AGI skill framework.

Each skill is a self-contained module that:
- Declares its metadata (id, name, version, capabilities)
- Implements an execute() entry point
- Can compose with other skills via the registry
- Persists state to PostgreSQL
"""

from __future__ import annotations

import abc
import datetime
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class SkillStatus(str, Enum):
    REGISTERED = "registered"
    LOADED = "loaded"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class SkillMetadata:
    skill_id: str          # e.g. "sk18b"
    name: str              # human-readable name
    version: str           # semver
    description: str
    capabilities: list[str] = field(default_factory=list)
    depends_on: list[str] = field(default_factory=list)
    created_at: datetime.datetime = field(
        default_factory=datetime.datetime.utcnow
    )

    def as_dict(self) -> dict[str, Any]:
        return {
            "skill_id": self.skill_id,
            "name": self.name,
            "version": self.version,
            "description": self.description,
            "capabilities": self.capabilities,
            "depends_on": self.depends_on,
            "created_at": self.created_at.isoformat(),
        }


class Skill(abc.ABC):
    """Abstract base for all AGI skills."""

    def __init__(self) -> None:
        self._status = SkillStatus.REGISTERED

    # -- required overrides --------------------------------------------------

    @abc.abstractmethod
    def metadata(self) -> SkillMetadata:
        """Return the skill's metadata descriptor."""

    @abc.abstractmethod
    def execute(self, context: dict[str, Any]) -> dict[str, Any]:
        """
        Run the skill.

        Parameters
        ----------
        context : dict
            Arbitrary execution context passed by the loader/orchestrator.

        Returns
        -------
        dict
            Result payload.
        """

    # -- lifecycle ------------------------------------------------------------

    @property
    def status(self) -> SkillStatus:
        return self._status

    def load(self) -> None:
        """Hook called when the skill is loaded into the registry."""
        self._status = SkillStatus.LOADED

    def run(self, context: dict[str, Any]) -> dict[str, Any]:
        """Execute with status tracking."""
        self._status = SkillStatus.RUNNING
        try:
            result = self.execute(context)
            self._status = SkillStatus.COMPLETED
            return result
        except Exception:
            self._status = SkillStatus.FAILED
            raise
