"""
Skill loader — discovers, validates, and loads skills from the skills/ tree.

Usage
-----
    loader = SkillLoader()
    loader.discover()          # scan skills/ directory
    loader.load("sk18b")       # load a specific skill
    result = loader.run("sk18b", context={...})
"""

from __future__ import annotations

import importlib
import logging
import pkgutil
from typing import Any

from core.skill_base import Skill, SkillStatus

log = logging.getLogger(__name__)


class SkillLoader:
    """Registry + loader for AGI skills."""

    def __init__(self) -> None:
        self._skills: dict[str, Skill] = {}

    # -- discovery ------------------------------------------------------------

    def discover(self) -> list[str]:
        """
        Walk the ``skills`` package and register every ``Skill`` subclass
        whose module exposes a top-level class inheriting from ``Skill``.

        Returns the list of discovered skill IDs.
        """
        import skills as skills_pkg

        found: list[str] = []
        for importer, modname, ispkg in pkgutil.walk_packages(
            skills_pkg.__path__, prefix="skills."
        ):
            if not ispkg:
                try:
                    mod = importlib.import_module(modname)
                except Exception:
                    log.warning("Failed to import %s", modname, exc_info=True)
                    continue

                for attr_name in dir(mod):
                    attr = getattr(mod, attr_name)
                    if (
                        isinstance(attr, type)
                        and issubclass(attr, Skill)
                        and attr is not Skill
                    ):
                        instance = attr()
                        meta = instance.metadata()
                        self._skills[meta.skill_id] = instance
                        found.append(meta.skill_id)
                        log.info("Discovered skill: %s (%s)", meta.skill_id, meta.name)

        return found

    # -- registration ---------------------------------------------------------

    def register(self, skill: Skill) -> None:
        meta = skill.metadata()
        self._skills[meta.skill_id] = skill
        log.info("Registered skill: %s", meta.skill_id)

    # -- loading / running ----------------------------------------------------

    def load(self, skill_id: str) -> Skill:
        skill = self._get(skill_id)
        skill.load()
        log.info("Loaded skill %s (status=%s)", skill_id, skill.status.value)
        return skill

    def run(self, skill_id: str, context: dict[str, Any] | None = None) -> dict[str, Any]:
        skill = self._get(skill_id)
        if skill.status == SkillStatus.REGISTERED:
            skill.load()
        return skill.run(context or {})

    # -- introspection --------------------------------------------------------

    def list_skills(self) -> list[dict[str, Any]]:
        return [
            {**s.metadata().as_dict(), "status": s.status.value}
            for s in self._skills.values()
        ]

    def get(self, skill_id: str) -> Skill | None:
        return self._skills.get(skill_id)

    # -- internal -------------------------------------------------------------

    def _get(self, skill_id: str) -> Skill:
        skill = self._skills.get(skill_id)
        if skill is None:
            raise KeyError(f"Skill '{skill_id}' not found. Discovered: {list(self._skills)}")
        return skill
