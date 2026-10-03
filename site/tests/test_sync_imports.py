"""Alt Army Sync is built from a few of the package's modules (scripts/build_sync.py): they may import only
the standard library, each other and the tray's extras, so no server code slips into the exe unnoticed."""

import ast
import sys
from pathlib import Path

import pytest

import altarmy_profit

PACKAGE = Path(altarmy_profit.__file__).parent
SYNC_MODULES = {"tray", "tray_core", "watch", "signin", "wowfiles", "versions"}
TRAY_EXTRAS = {"pystray", "PIL"}


def imports(module: str) -> set[str]:
    """What a module imports: top-level names for absolute imports, sibling module names for relative ones."""
    found: set[str] = set()
    for node in ast.walk(ast.parse((PACKAGE / f"{module}.py").read_text(encoding="utf-8"))):
        if isinstance(node, ast.Import):
            found |= {alias.name.split(".")[0] for alias in node.names}
        elif isinstance(node, ast.ImportFrom):
            if node.level == 0:
                found.add((node.module or "").split(".")[0])
            elif node.module:  # from .x import y
                found.add("." + node.module.split(".")[0])
            else:  # from . import x, y
                found |= {"." + alias.name for alias in node.names}
    return found


@pytest.mark.parametrize("module", sorted(SYNC_MODULES))
def test_sync_modules_import_only_the_standard_library_and_each_other(module: str) -> None:
    allowed = set(sys.stdlib_module_names) | TRAY_EXTRAS | {"." + m for m in SYNC_MODULES}
    assert imports(module) - allowed == set()
