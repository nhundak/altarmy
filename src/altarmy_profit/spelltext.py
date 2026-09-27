"""Item spell effects as tooltip text (pure, no I/O): the "Use:", "Equip:" and "Chance on hit:" lines.

A Spell's description is a template with `$` variables the client fills from the spell's effects:
`$s1` (effect 1's value, a range when it has a variance: "1050 to 1750"), `$o1` (a periodic effect's total
over its duration), `$d` (the duration), `$t1` (the tick period), `$m1`/`$M1` (the range's ends), `$q1`
(the effect's misc value), `$a1` (its radius), `$h` (proc chance), `$u` (max stacks), `$x1` (chain targets),
`$PL` (the player's level), `$17534s1` (another spell's value), `$@spelldesc1131` (another description,
inlined), `${$m1/60}` (arithmetic, `${...}.1` with decimals), `$/10;s1` (divided), `$lsec:secs;` and
`$ghim:her;` (plural and gender choices), `$?condition[then][else]` (a condition we cannot evaluate: the
else branch), `$@spellicon` (dropped). Anything else stays as written, so a line is never wrong, only
unfinished. `expand` covers what the item spells of the Forever client use.
"""

from __future__ import annotations

import ast
import re
from collections.abc import Mapping
from dataclasses import dataclass, field

from .itemstats import Effect

MAX_DEPTH = 3  # nested $@spelldesc
TRIGGERS: Mapping[int, str] = {0: "Use", 1: "Equip", 2: "Chance on hit"}  # ItemEffect.TriggerType


@dataclass(frozen=True)
class EffectValues:
    """One SpellEffect row's numbers."""

    base: float  # EffectBasePointsF
    variance: float = 0.0  # the value is base * (1 -/+ variance / 2)
    period_ms: int = 0  # EffectAuraPeriod: a periodic effect ticks this often
    misc: int = 0  # EffectMiscValue_0
    radius: float = 0.0  # SpellRadius' Radius, yards
    chain: int = 0  # EffectChainTargets


@dataclass(frozen=True)
class SpellData:
    """What the descriptions of a set of spells refer to (any spell not here reads 0 / empty)."""

    descriptions: Mapping[int, str]
    effects: Mapping[int, tuple[EffectValues, ...]] = field(default_factory=dict)  # by effect index
    durations: Mapping[int, int] = field(default_factory=dict)  # ms; -1 for "until cancelled"
    proc_chance: Mapping[int, int] = field(default_factory=dict)  # percent
    max_stacks: Mapping[int, int] = field(default_factory=dict)


SPELL_REF = re.compile(r"\$(?:@spelldesc)?(\d+)")


def referenced(text: str) -> set[int]:
    """The other spells a description pulls values or text from."""
    return {int(m) for m in SPELL_REF.findall(text)}


def _number(x: float) -> str:
    """1400 -> "1400", 874.8 -> "874.8"."""
    return f"{round(x, 2):g}"


def _range(v: EffectValues) -> tuple[float, float]:
    base = abs(v.base)
    return base * (1 - v.variance / 2), base * (1 + v.variance / 2)


def format_value(v: EffectValues, duration_ms: int = 0) -> str:
    """`$s`: the effect's value ("1400"), or its range when it varies ("1050 to 1750"); with a duration,
    `$o`: a periodic effect's total over it."""
    if duration_ms > 0 and v.period_ms > 0:
        return _number(abs(v.base) * (duration_ms / v.period_ms))
    lo, hi = _range(v)
    if v.variance > 0:
        return f"{round(lo)} to {round(hi)}"
    return _number(lo)


def _units(ms: int, sec: str, minute: str, hour: str, hours: str) -> str:
    seconds = ms / 1000
    if seconds < 60:
        return f"{_number(seconds)} {sec}"
    if seconds < 3600:
        return f"{_number(seconds / 60)} {minute}"
    h = seconds / 3600
    return f"1 {hour}" if h == 1 else f"{_number(h)} {hours}"


def format_duration(ms: int) -> str:
    """`$d`: "30 sec", "2 min", "1 hour", "2 hrs"; "" when the spell has no duration."""
    return _units(ms, "sec", "min", "hour", "hrs") if ms > 0 else ""


def cooldown_text(ms: int) -> str:
    """The "(2 Min Cooldown)" suffix of a Use line; "" without a cooldown."""
    return f"({_units(ms, 'Sec', 'Min', 'Hour', 'Hrs')} Cooldown)" if ms > 0 else ""


_ICON = re.compile(r"\$@spellicon\d+\s?")
_DESC = re.compile(r"\$@spelldesc(\d+)")
_PLURAL = re.compile(r"\$[lL]([^:;$]*):([^;$]*);")
_GENDER = re.compile(r"\$[gG]([^:;$]*):([^;$]*);")
_EXPR = re.compile(r"\$\{([^{}]*)\}(?:\.(\d))?")
_DIVIDED = re.compile(r"\$/(\d+);(\d*)([a-zA-Z]+)(\d*)")
_VAR = re.compile(r"\$(\d*)(PL|[sSmMoOdDtTaAqQhHuUxX])(\d*)")
_NUMBER = re.compile(r"\d+(?:\.\d+)?")
_KEEP = "\x00"  # stands in for "$" in text that must survive the remaining passes
_ARITH_OPS = (ast.Add, ast.Sub, ast.Mult, ast.Div, ast.USub, ast.UAdd)


def _arith(expr: str) -> float | None:
    """A safe evaluation of `+ - * /` over numbers, or None for anything else."""
    try:
        tree = ast.parse(expr.strip(), mode="eval")
    except SyntaxError:
        return None

    def ev(node: ast.AST) -> float:
        if isinstance(node, ast.Constant) and isinstance(node.value, int | float):
            return float(node.value)
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub | ast.UAdd):
            v = ev(node.operand)
            return -v if isinstance(node.op, ast.USub) else v
        if isinstance(node, ast.BinOp) and isinstance(node.op, _ARITH_OPS):
            a, b = ev(node.left), ev(node.right)
            if isinstance(node.op, ast.Add):
                return a + b
            if isinstance(node.op, ast.Sub):
                return a - b
            if isinstance(node.op, ast.Mult):
                return a * b
            if b == 0:
                raise ValueError("division by zero")
            return a / b
        raise ValueError("not arithmetic")

    try:
        return ev(tree.body)
    except (ValueError, RecursionError):
        return None


def _conditionals(text: str) -> str:
    """`$?cond[then]?cond2[then2][else]` -> the else branch (an item tooltip is read by nobody in
    particular, so conditions on the reader's class, talents or level cannot be answered)."""
    out = []
    i = 0
    while True:
        start = text.find("$?", i)
        if start < 0:
            out.append(text[i:])
            return "".join(out)
        out.append(text[i:start])
        pos = text.find("[", start)
        if pos < 0:
            out.append(text[start:])
            return "".join(out)
        branches: list[str] = []
        while pos < len(text) and text[pos] == "[":
            depth = 0
            end = pos
            for end in range(pos, len(text)):
                depth += {"[": 1, "]": -1}.get(text[end], 0)
                if depth == 0:
                    break
            branches.append(text[pos + 1 : end])
            pos = end + 1
            if pos < len(text) and text[pos] == "?":  # another condition: skip to its branch
                pos = text.find("[", pos)
                if pos < 0:
                    pos = len(text)
        out.append(branches[-1] if len(branches) > 1 else "")
        i = pos


class _Expander:
    def __init__(self, data: SpellData, player_level: int) -> None:
        self.data = data
        self.player_level = player_level

    def effect(self, spell: int, index: str) -> EffectValues | None:
        effects = self.data.effects.get(spell, ())
        i = int(index) - 1 if index else 0
        return effects[i] if 0 <= i < len(effects) else None

    def value(self, spell: int, var: str, index: str) -> float | None:
        """A variable's number, signed, as arithmetic uses it (`${$m1/-1000}`); None when unknown."""
        if var == "PL":
            return float(self.player_level)
        if var in "dD":
            return self.data.durations.get(spell, 0) / 1000
        if var in "hH":
            return float(self.data.proc_chance.get(spell, 0))
        if var in "uU":
            return float(self.data.max_stacks.get(spell, 0))
        v = self.effect(spell, index)
        if v is None:
            return None
        if var in "sS":
            return v.base
        if var in "mM":
            return v.base * (1 - v.variance / 2) if var == "m" else v.base * (1 + v.variance / 2)
        if var in "oO":
            duration = self.data.durations.get(spell, 0)
            return v.base * (duration / v.period_ms) if duration > 0 and v.period_ms > 0 else v.base
        if var in "tT":
            return v.period_ms / 1000
        if var in "aA":
            return v.radius
        if var in "qQ":
            return float(v.misc)
        return float(v.chain)  # x

    def text(self, spell: int, var: str, index: str) -> str | None:
        """A variable as displayed: values unsigned (the text carries the sign), durations as words."""
        if var in "dD":
            return format_duration(self.data.durations.get(spell, 0))
        if var in "sS":
            v = self.effect(spell, index)
            return None if v is None else format_value(v)
        if var in "oO":
            v = self.effect(spell, index)
            return None if v is None else format_value(v, self.data.durations.get(spell, 0))
        n = self.value(spell, var, index)
        return None if n is None else _number(abs(n))

    def expand(self, text: str, spell: int, depth: int = 0) -> str:
        if depth > MAX_DEPTH:
            return ""
        text = _ICON.sub("", text)
        text = _DESC.sub(
            lambda m: self.expand(self.data.descriptions.get(int(m[1]), ""), int(m[1]), depth + 1), text
        )
        text = _conditionals(text)

        def var(m: re.Match[str]) -> str:
            s = int(m[1]) if m[1] else spell
            out = self.text(s, m[2], m[3])
            return m[0] if out is None else out

        def divided(m: re.Match[str]) -> str:
            s = int(m[2]) if m[2] else spell
            n = self.value(s, m[3], m[4])
            return m[0] if n is None else _number(abs(n) / int(m[1]))

        def expr(m: re.Match[str]) -> str:
            def number(v: re.Match[str]) -> str:
                s = int(v[1]) if v[1] else spell
                n = self.value(s, v[2], v[3])
                return v[0] if n is None else repr(n)

            inner = _VAR.sub(number, m[1])
            n = _arith(inner)
            if n is None:
                return m[0].replace("$", _KEEP)  # left as written, safe from the passes below
            return f"{n:.{m[2]}f}" if m[2] else _number(n)

        text = _EXPR.sub(expr, text)
        text = _DIVIDED.sub(divided, text)
        text = _VAR.sub(var, text)

        def plural(m: re.Match[str]) -> str:
            before = _NUMBER.findall(m.string[: m.start()])
            return m[1] if before and float(before[-1]) == 1 else m[2]

        text = _PLURAL.sub(plural, text)
        text = _GENDER.sub(lambda m: m[1], text)
        text = re.sub(r"[ \t]{2,}", " ", text.replace("\r\n", "\n")).strip()
        return text.replace(_KEEP, "$")


def expand(text: str, spell_id: int, data: SpellData, *, player_level: int = 60) -> str:
    """`text` (a description of `spell_id`) with its variables filled from `data`."""
    return _Expander(data, player_level).expand(text, spell_id)


def render_effect(
    trigger: str, spell_id: int, cooldown_ms: int, data: SpellData, player_level: int = 60
) -> Effect | None:
    """The green line of one item effect; None when the spell has no description."""
    description = data.descriptions.get(spell_id, "")
    text = expand(description, spell_id, data, player_level=player_level) if description else ""
    if not text:
        return None
    if trigger == "Use" and cooldown_ms > 0:
        text = f"{text} {cooldown_text(cooldown_ms)}"
    return Effect(trigger, text)
