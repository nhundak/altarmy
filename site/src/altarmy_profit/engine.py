"""Pure profit engine: no I/O. All money is integer copper."""

from __future__ import annotations

import itertools
import math
from collections.abc import Callable, Collection, Iterable, Iterator, Mapping, Sequence
from dataclasses import dataclass, field, replace
from functools import cached_property
from typing import Literal

from . import book, timing
from .reputation import vendor_discounts
from .timing import Timing
from .versions import AH_CUT as AH_CUT
from .versions import MAIL_POSTAGE as MAIL_POSTAGE

# A flip's recipe id: FLIP_ID_BASE + the item id (inside 32 bits)
FLIP_ID_BASE = 2_000_000_000
MAX_CHAIN_DEPTH = 3
DISENCHANTABLE_CLASSES = (2, 4)  # weapon, armor
DISENCHANTABLE_QUALITIES = (2, 3, 4)
ALL_EXITS = frozenset({"vendor", "ah", "disenchant"})  # ways to sell a craft (Exit.kind)
# The exit of an enchant, which makes nothing to sell: cast for the skill point alone, at a dead loss. Not
# among `ALL_EXITS`: enchants rank only where it is asked for.
SKILL_EXIT = "skill"
# Keeping what a craft made while skilling up, when no vendor buys it: worth nothing, but the skill point
# was the point. Only for the characters being skilled up (`Market.skill_crafters`), and only when asked for.
KEEP_EXIT = "keep"
# A skill-up run (`run_until_cheaper`) never asks for more crafts than this at once
RUN_CEILING = 100
# WoW: Forever's Arcane Salvager (an Enchanting-made station): near it a disenchant has this chance of a
# second roll of the same table, so it yields 1.1 times the materials on average
ARCANE_SALVAGER_BONUS = 0.10
# Which recipes nobody has learned count: none, those a character can train (see `Learning`, `can_learn`),
# all of their professions'.
Unlearned = Literal["none", "train", "all"]
MAX_LOOK_AHEAD = 50  # the most skill a recipe "to train" may need beyond what the character has
# What teaches a recipe: a profession trainer (no item teaches its spell), a recipe item that can be traded,
# or only recipe items that bind on pickup.
Source = Literal["trainer", "recipe", "bop"]
ALL_SOURCES: tuple[Source, ...] = ("trainer", "recipe", "bop")
DEFAULT_SOURCES: frozenset[Source] = frozenset({"trainer", "recipe"})
# Real professions offered in the UI; the DB also holds junk skill lines (test, class, etc.).
PROFESSIONS = (
    "Alchemy",
    "Blacksmithing",
    "Cooking",
    "Enchanting",
    "Engineering",
    "First Aid",
    "Fishing",
    "Herbalism",
    "Jewelcrafting",
    "Leatherworking",
    "Mining",
    "Poisons",
    "Skinning",
    "Tailoring",
)


@dataclass(frozen=True)
class Item:
    id: int
    name: str
    quality: int = 1
    item_level: int = 0
    class_id: int = 0
    sell_price: int = 0
    vendor_price: int | None = None  # copper per unit if a vendor sells it (unlimited stock)
    stack_size: int = 1  # units per stack: one mail attachment
    tradable: bool = True  # False when it binds on pickup (or is a quest item): never mailed or on the AH
    disenchantable: bool = True  # False when the item is flagged so (Enchanting's wands, PvP rank gear)


@dataclass(frozen=True)
class Recipe:
    id: int
    name: str
    output_item_id: int
    output_count: int = 1
    reagents: tuple[tuple[int, int], ...] = ()  # (item_id, count)
    skill_name: str = ""
    min_skill: int = 0
    spell_id: int = 0  # the craft spell; Alt Army's recipe ids
    trivial_low: int = 0  # skill where it turns yellow; 0 if unknown
    trivial_high: int = 0  # skill where it turns grey (no more skillups); 0 if unknown
    cast_time_ms: int = 0  # one cast; 0 if instant or unknown
    station: str = ""  # the crafting station it is cast at (`timing.station_kind`: anvil, loom, ...); "" none
    learn_skill: int = 0  # skill the recipe item teaching it requires; 0 if none does (a trainer's)
    source: Source = "trainer"  # what teaches it
    # "craft"; "convert": enchanting materials turned into others with their Use spell (3 lesser essences
    # into a greater and back); "flip": gear bought on the AH to disenchant (`Market` makes these). The
    # last two need no profession: anyone does them, they never skill up, and they rank only when
    # disenchant is a way to sell (see `Market.rank`). "enchant": a profession's spell enchanting an item,
    # which makes none (`output_item_id` 0): it has only the `SKILL_EXIT`, and only someone it can skill up
    # casts it
    kind: str = "craft"

    @property
    def is_conversion(self) -> bool:
        return self.kind == "convert"

    @property
    def is_flip(self) -> bool:
        return self.kind == "flip"

    @property
    def is_enchant(self) -> bool:
        return self.kind == "enchant"

    @property
    def anyone(self) -> bool:
        """No profession's recipe: a conversion or a flip."""
        return self.kind in ("convert", "flip")

    @property
    def required_skill(self) -> int:
        """Skill needed to learn it: its recipe item's requirement, else (DB2 doesn't say what a trainer
        asks) the skill where it turns yellow, which is never below the real requirement."""
        return self.learn_skill or max(self.min_skill, self.trivial_low)


@dataclass(frozen=True)
class Crafter:
    """One character who may craft or disenchant: their (profession, rank, max rank) triples and learned
    craft spells, plus what their Legacy talents do (see `talents`): a chance per profession of one extra
    result from a craft, a percent off vendor prices, and a chance added to every craft's chance of a skill
    point (Working Overtime; never to a grey recipe's). Their standings with the city factions take more
    off at those factions' vendors (see `Market`'s `reputation_discounts`)."""

    name: str
    professions: tuple[tuple[str, int, int], ...]
    known_spells: frozenset[int]
    extra_results: tuple[tuple[str, float], ...] = ()  # (profession, chance of one extra result)
    vendor_discount: int = 0  # percent off what they buy from vendors
    reputations: tuple[tuple[int, int], ...] = ()  # (faction id, standing 1 Hated .. 8 Exalted)
    skill_bonus: float = 0.0  # added to the chance of a skill point from a craft that can give one

    def extra_chance(self, profession: str) -> float:
        """Their chance of one extra result from a `profession` craft."""
        return sum(c for p, c in self.extra_results if p.lower() == profession.lower())

    def has(self, profession: str) -> bool:
        return self.skill(profession) is not None

    def skill(self, profession: str) -> tuple[int, int] | None:
        """Their (rank, max rank) in `profession`; None if they don't have it."""
        return next(((r, m) for p, r, m in self.professions if p.lower() == profession.lower()), None)

    @property
    def enchanting(self) -> int:
        """Enchanting skill; 0 if they don't have it."""
        skill = self.skill("enchanting")
        return skill[0] if skill else 0


@dataclass(frozen=True)
class Learning:
    """Which recipes nobody has learned count as craftable: with "train" those taught by one of `sources`
    that need at most `look_ahead` more skill than the character has (0: trainable right now)."""

    unlearned: Unlearned = "none"
    look_ahead: int = 0
    sources: frozenset[Source] = DEFAULT_SOURCES

    @staticmethod
    def of(value: Learning | Unlearned) -> Learning:
        """`value` itself, or the plain mode with the default look-ahead and sources."""
        return value if isinstance(value, Learning) else Learning(value)

    def normalized(self) -> Learning:
        """Without what its mode ignores, so equal choices compare equal (cache keys)."""
        return self if self.unlearned == "train" else Learning(self.unlearned)


def can_learn(recipe: Recipe, crafter: Crafter, unlearned: Learning | Unlearned) -> bool:
    """Whether `crafter` counts as able to craft `recipe` without having learned it: never with "none"; with
    "train" if one of the chosen sources teaches it and their skill in its profession is at most the
    look-ahead below its `required_skill`; with "all" if they have its profession."""
    learning = Learning.of(unlearned)
    if learning.unlearned == "none":
        return False
    skill = crafter.skill(recipe.skill_name)
    if skill is None:
        return False
    if learning.unlearned == "all":
        return True
    return recipe.source in learning.sources and recipe.required_skill <= skill[0] + learning.look_ahead


def can_skill_up(recipe: Recipe, crafter: Crafter) -> bool:
    """Whether crafting `recipe` can raise `crafter`'s skill: it isn't grey for them and they aren't at their
    profession's cap. Recipes without skill thresholds count as able to; conversions and flips never do."""
    if recipe.anyone:
        return False
    if not recipe.trivial_high:
        return True
    skill = crafter.skill(recipe.skill_name)
    return skill is not None and skill[0] < recipe.trivial_high and skill[0] < skill[1]


def skill_up_chance(recipe: Recipe, crafter: Crafter) -> float:
    """The chance a craft of `recipe` gives `crafter` a skill point: 0 unless `can_skill_up`; 1 while it is
    orange (below `trivial_low`, or its thresholds are unknown); then falling evenly from 1 at yellow to 0
    at grey; plus the crafter's `skill_bonus`, up to 1."""
    if not can_skill_up(recipe, crafter):
        return 0.0
    skill = crafter.skill(recipe.skill_name)
    if not recipe.trivial_high or skill is None or skill[0] < recipe.trivial_low:
        return 1.0
    chance = (recipe.trivial_high - skill[0]) / (recipe.trivial_high - recipe.trivial_low)
    return min(1.0, chance + crafter.skill_bonus)


def expected_skill_ups(recipe: Recipe, crafter: Crafter | None, crafts: int) -> float:
    """The skill points `crafter` can expect from `crafts` crafts of `recipe` in a row: craft by craft, each
    at the chance for the skill the crafts before it are expected to have reached (`skill_up_chance`'s
    rule, the crafter's `skill_bonus` included), never past grey or the profession's cap. While the recipe
    is yellow or green the chance falls linearly with the skill, so the expected skill gives the expected
    chance exactly; only a session crossing into yellow, reaching the cap or reaching a chance of 1 with
    the bonus is approximate. Without a crafter every craft counts (but a
    conversion's or a flip's)."""
    if recipe.anyone:
        return 0.0
    if crafter is None:
        return float(crafts)
    if not can_skill_up(recipe, crafter):
        return 0.0
    skill = crafter.skill(recipe.skill_name)
    if skill is None:  # can_skill_up allows a recipe without thresholds to anyone
        return float(crafts)
    rank, cap = skill
    limit = min(cap, recipe.trivial_high) if recipe.trivial_high else cap
    level = float(rank)
    for _ in range(crafts):
        if level >= limit - 1e-9:
            break
        chance = (
            1.0
            if not recipe.trivial_high or level < recipe.trivial_low
            else min(
                1.0,
                (recipe.trivial_high - level) / (recipe.trivial_high - recipe.trivial_low)
                + crafter.skill_bonus,
            )
        )
        level += min(chance, limit - level)
    return level - rank


def _chance_at(recipe: Recipe, crafter: Crafter, level: float) -> float:
    """`skill_up_chance`'s rule at `level` (orange: 1; then falling evenly to 0 at grey; plus the crafter's
    `skill_bonus`), for a skill the crafter is expected to reach."""
    low, high = recipe.trivial_low, recipe.trivial_high
    if not high or level < low:
        return 1.0
    if level >= high or high <= low:
        return 0.0
    return min(1.0, (high - level) / (high - low) + crafter.skill_bonus)


def _reach(recipe: Recipe, crafter: Crafter, points: int) -> Iterator[float]:
    """The chance that `crafter` has `points` skill points after 1, 2, ... crafts of `recipe` (each craft a
    point at the chance for the skill reached so far), without end. Exact over the per-craft chances."""
    skill = crafter.skill(recipe.skill_name)
    rank = skill[0] if skill is not None else 0
    dist = [1.0] + [0.0] * points  # dist[k]: the chance of k points so far (`points`: done)
    while True:
        nxt = [0.0] * (points + 1)
        nxt[points] = dist[points]
        for k in range(points):
            p = _chance_at(recipe, crafter, rank + k)
            nxt[k + 1] += dist[k] * p
            nxt[k] += dist[k] * (1 - p)
        dist = nxt
        yield dist[points]


def reach_chances(recipe: Recipe, crafter: Crafter, points: int, crafts: int) -> tuple[float, ...]:
    """The chance of `points` skill points after each of 1 to `crafts` crafts (`_reach`); all 1 for none."""
    if points <= 0:
        return (1.0,) * crafts
    return tuple(itertools.islice(_reach(recipe, crafter, points), crafts))


def crafts_quantile(
    recipe: Recipe, crafter: Crafter, points: int, q: float = 0.8, ceiling: int = RUN_CEILING
) -> int:
    """How many crafts give `crafter` `points` skill points with probability at least `q` (`_reach`): what
    to buy for, so that an unlucky run still gets there. At least one craft, at most `ceiling`."""
    if points <= 0:
        return 1
    for n, chance in enumerate(itertools.islice(_reach(recipe, crafter, points), ceiling), start=1):
        if chance >= q - 1e-12:
            return n
    return ceiling


def _per_point(cost: float, chance: float) -> float:
    """What a skill point costs at `chance` a craft of `cost` (infinite when it gives none)."""
    return cost / chance if chance > 0 else math.inf


@dataclass(frozen=True)
class Rival:
    """A recipe a skill-up run competes with: what a craft of it comes to (`cost`: spent less what selling
    what it makes brings back, per craft) and from what skill the crafter can learn it (0: they can now)."""

    recipe: Recipe
    cost: float
    from_skill: int = 0


@dataclass(frozen=True)
class SkillRuns:
    """Rank each recipe as a run (`run_until_cheaper`), of at most `ceiling` crafts."""

    ceiling: int = RUN_CEILING


@dataclass(frozen=True)
class SkillRun:
    """A run of one recipe for one crafter: the crafts it is expected to take, the skill they bring the
    crafter to, why it stops there (`reason`: rival, another recipe giving a cheaper point by then (`rival`);
    trivial, the recipe about to turn grey; cap, the crafter's profession cap; ceiling, `SkillRuns.ceiling`
    crafts), and the crafts that get there four times in five."""

    crafts: int
    stop_skill: int
    reason: str
    rival: Recipe | None
    crafts_p80: int
    reach: tuple[float, ...] = ()


# How far past the crafts that get there four times in five `SkillRun.reach` goes: twice them, at least
# this many more
REACH_MORE = 20


def run_until_cheaper(
    recipe: Recipe, crafter: Crafter, cost: float, rivals: Sequence[Rival], ceiling: int = RUN_CEILING
) -> SkillRun:
    """How long `crafter` should go on crafting `recipe` (`cost` a craft, as `Rival.cost`) to raise its
    profession as cheaply as possible: craft by craft at the skill the crafts before are expected to have
    reached (as `expected_skill_ups`), until one of the `rivals` it was giving a cheaper point than at the
    start (or one they can't learn yet, from the skill they can) gives a cheaper one, the recipe is about to
    turn grey (its last point is due at `trivial_high` - 1), they reach their cap, or `ceiling` crafts. A
    point costs a craft's cost over the chance of a point (`skill_up_chance`'s rule). A run about to turn
    grey names the rival giving the cheapest point there, if any gives a cheaper one than its own last point
    (watched or not: it is what to craft next), as a `rival` stop; only without one is it `trivial`."""
    skill = crafter.skill(recipe.skill_name)
    rank, cap = skill if skill is not None else (0, 0)
    start = _per_point(cost, _chance_at(recipe, crafter, rank))
    watched = [
        r
        for r in rivals
        if r.recipe.id != recipe.id
        and (r.from_skill > rank or _per_point(r.cost, _chance_at(r.recipe, crafter, rank)) >= start)
    ]
    level, crafts = float(rank), 0
    reason, by = "ceiling", None
    while True:
        if skill is not None and level >= cap - 1e-9:
            reason = "cap"
            break
        chance = _chance_at(recipe, crafter, level)
        mine = _per_point(cost, chance)
        trivial = chance <= 0 or bool(recipe.trivial_high and level >= recipe.trivial_high - 1 - 1e-9)
        cheaper = [
            (per, r)
            for r in (rivals if trivial else watched)
            if r.recipe.id != recipe.id
            and r.from_skill <= level + 1e-9
            and (per := _per_point(r.cost, _chance_at(r.recipe, crafter, level))) < mine - 1e-9
        ]
        if trivial and not cheaper:
            reason = "trivial"
            break
        if cheaper:
            reason, by = "rival", min(cheaper, key=lambda c: c[0])[1].recipe
            break
        if crafts >= ceiling:
            break
        level = min(level + chance, float(cap)) if skill is not None else level + chance
        crafts += 1
    crafts = max(1, crafts)
    points = max(1, round(level - rank))
    p80 = max(crafts, crafts_quantile(recipe, crafter, points, 0.8, max(ceiling, crafts)))
    reach = reach_chances(recipe, crafter, points, max(2 * p80, p80 + REACH_MORE))
    return SkillRun(crafts, round(level), reason, by, p80, reach)


@dataclass(frozen=True)
class DisenchantRow:
    item_class: int
    quality: int
    min_ilvl: int
    max_ilvl: int
    result_item_id: int
    chance: float
    min_count: int
    max_count: int


@dataclass(frozen=True)
class Material:
    """One possible disenchant result for an item."""

    item_id: int
    name: str
    chance: float
    min_count: int
    max_count: int
    value: int | None  # expected net AH copper per disenchant (chance x average count); None if unpriced


@dataclass
class Exit:
    kind: str  # vendor | ah | disenchant | skill (an enchant's: nothing is sold)
    value: int  # copper per item, after cuts
    materials: tuple[Material, ...] = ()  # disenchant only: what it yields
    postage: int = 0  # copper per item to mail it to the character who can use this exit
    mail_to: str = ""  # that character; "" if the crafter can use it themselves


@dataclass(frozen=True)
class Step:
    """One instruction in a recipe's shopping/crafting/selling sequence."""

    action: (
        str  # buy | gather (the user's own: `value` what selling it would have made) | craft | mail | sell
    )
    item_id: int
    name: str
    quantity: int
    value: int = 0  # copper for the whole step: negative when buying or mailing, positive when selling
    via: str = ""  # buy: vendor | ah; craft: recipe name; mail: recipient; sell: vendor | ah | disenchant
    who: str = ""  # the character doing it; "" if no characters are known
    # the tree paths (see `Choices`) of the nodes it stands for: several when merged; "sell" for the sale
    paths: tuple[str, ...] = field(default=(), compare=False)
    discount: int = 0  # buy from a vendor: percent off from the buyer's Legacy talents (Bartering)
    rep_discount: int = 0  # buy from a vendor: percent off for the buyer's standing with the vendor's faction
    bonus: float = 0.0  # sell: expected extra units on top of `quantity` (Master Chef), counted in `value`
    # seconds of play per craft of the recipe the step itself takes (clicks, casts); travel is in `Timing`
    seconds: float = field(default=0.0, compare=False)
    station: str = field(default="", compare=False)  # craft: the station it is cast at; "" anywhere
    # sell by disenchanting: the disenchanting's share of `seconds` (the rest is posting the materials)
    lead_seconds: float = field(default=0.0, compare=False)
    convert: bool = False  # craft: a conversion (`Recipe.is_conversion`), not a profession craft
    enchant: bool = False  # craft: an enchant (`Recipe.is_enchant`): `name` is the spell's, no item is made


@dataclass(frozen=True)
class Option:
    """One way to get a node's items: buy them (`key` vendor | ah) or craft them (`key` craft:<recipe id>)."""

    key: str
    cost: int  # copper for the node's quantity this way, with postage (its own subtree at its cheapest)
    source: str = ""  # vendor | ah if bought; gather if the user gathers it (`Market.gathered`)
    via: str = ""  # recipe name if crafted
    crafter: str = ""  # who crafts it: the cheapest character for that recipe
    seconds: float = field(default=0.0, compare=False)  # estimated play time per craft this way (see Node)
    convert: bool = False  # crafted by a conversion (`Recipe.is_conversion`)


@dataclass(frozen=True)
class SellOption:
    """One way to sell a craft and the best profit it gives."""

    kind: str  # vendor | ah | disenchant
    profit: int


@dataclass(frozen=True)
class Node:
    """One item in a craft's reagent tree: bought (no inputs) or crafted from its inputs, possibly by
    another character who then mails it on."""

    item_id: int
    name: str
    quantity: int  # units this branch needs
    cost: int  # copper spent on them: quantity x price if bought, sum of inputs if crafted; plus postage
    via: str = ""  # recipe name if crafted
    crafts: int = 0  # recipe runs if crafted: whole batches, so `made` may exceed `quantity`
    made: int = 0  # units those crafts produce
    inputs: tuple[Node, ...] = ()
    source: str = ""  # vendor | ah if bought
    crafter: str = ""  # who buys or crafts it; "" if no characters are known
    mail_to: str = ""  # who it is mailed to (the parent's crafter); "" if not mailed
    postage: int = 0  # copper for that mail, included in cost
    discount: int = 0  # bought from a vendor: percent off the buyer gets (Bartering)
    rep_discount: int = 0  # bought from a vendor: percent off for their standing with the vendor's faction
    short: int = 0  # bought on the AH: units more than it lists, counted at its dearest price
    # every way to get these items, cheapest first; empty for the recipe's own craft
    options: tuple[Option, ...] = field(default=(), compare=False)
    option: str = field(default="", compare=False)  # the key of the option taken; "" for the recipe's craft
    # With a time model: estimated play time per craft of the recipe for this whole branch, travel and
    # switches shared out over the batch (what plans are chosen by); the node's own buy or craft clicks and
    # casts, and its mail's, per craft; and where it is crafted.
    seconds: float = field(default=0.0, compare=False)
    act_seconds: float = field(default=0.0, compare=False)
    mail_seconds: float = field(default=0.0, compare=False)
    station: str = field(default="", compare=False)
    convert: bool = False  # crafted by a conversion (`Recipe.is_conversion`)
    flip: bool = False  # a flip's root (`Recipe.is_flip`): nothing is crafted, the bought input is sold
    enchant: bool = False  # an enchant's root (`Recipe.is_enchant`): item 0, named after the spell


@dataclass(frozen=True, eq=False)
class TimeModel:
    """How plans are timed: the user's `timing.TimeConfig` in one city, or with `fastest` in whichever of
    those cities is quickest for each plan (`city` then only guides the estimate plans are chosen by). With
    a time value, plans are chosen by copper plus the value of the play time they take.

    The city also prices vendor buys (a vendor charges a buyer by their standing with its faction), and
    those prices are `city`'s: the `fastest` cities must charge the crafters the same (`city_prices`)."""

    config: timing.TimeConfig
    city: timing.CityMap
    fastest: tuple[timing.CityMap, ...] = ()

    @property
    def key(self) -> tuple[tuple[str, ...], timing.TimeConfig]:
        """What a ranking under this model depends on (cities by name: maps are loaded once)."""
        return (self.city.name, *(c.name for c in self.fastest)), self.config


@dataclass
class Result:
    recipe: Recipe
    cost: int  # for `crafts` crafts: reagents plus postage
    revenue: int  # for `crafts` crafts (best exit x (output_count x crafts + bonus_output))
    best_exit: str
    tree: Node  # the recipe's craft, with its reagents as inputs
    exits: list[Exit] = field(default_factory=list)
    postage: int = 0  # mailing the output to whoever sells it (included in cost)
    mail_to: str = ""  # who the output is mailed to; "" if the crafter sells it
    crafter: str = ""  # who does the final craft; "" if no characters are known
    sell_options: list[SellOption] = field(default_factory=list)  # each exit's best profit, best first
    bonus_output: float = 0.0  # expected extra units from the crafter's talents (Master Chef), all crafts
    skill_chance: float = 0.0  # that the first craft gives `crafter` a skill point (1 without characters)
    skill_ups: float = 0.0  # the skill points `crafter` can expect from all `crafts` (`expected_skill_ups`)
    skill_ups_bonus: float = 0.0  # the part of `skill_ups` owed to the crafter's `skill_bonus`
    # As a skill-up run (`evaluate`'s `skill_run`, `run_until_cheaper`): the skill it takes the crafter
    # to, why it stops there (`SkillRun.reason`), the recipe whose point is cheaper by then (its output's
    # name, and its item id unless it is an enchant; "" and 0 unless `stop_reason` is rival), the crafts that
    # get there four times in five
    stop_skill: int = 0
    stop_reason: str = ""
    overtaken_by: str = ""
    overtaken_by_item: int = 0
    crafts_p80: int = 0
    # the chance the crafter has reached `stop_skill` after each of 1, 2, ... crafts (`reach_chances`; past
    # the end, at least the last)
    reach_chances: tuple[float, ...] = ()
    # With a time model: the estimated play time per craft (what the plan was chosen by), and the per-craft
    # seconds of the sale and of mailing the output to whoever sells it
    seconds: float = field(default=0.0, compare=False)
    sell_seconds: float = field(default=0.0, compare=False)
    disenchant_seconds: float = field(default=0.0, compare=False)  # the disenchanting part of `sell_seconds`
    mail_seconds: float = field(default=0.0, compare=False)
    time_model: TimeModel | None = field(default=None, compare=False, repr=False)
    crafts: int = 1  # how many crafts cost, revenue, steps and tree are for (a session's)
    # who -> {faction id: percent off at that faction's vendors}: where the plan's vendor prices hold
    reputations: Mapping[str, Mapping[int, int]] = field(default_factory=dict, compare=False, repr=False)
    # the same recipe planned in the cities that charge the crafters differently (each timed in its own
    # cities), when this one was picked from among them; see `service.best_of`
    alternatives: tuple[Result, ...] = field(default=(), compare=False, repr=False)

    @cached_property
    def steps(self) -> list[Step]:
        """Per character: buys, crafts (sub-crafts first), mails, then the sale (see `plan_steps`). Planned
        when first read, so a ranking never schedules results nobody looks at. Pure over frozen fields, so
        two threads reading a shared result at once merely plan the same steps twice."""
        return plan_steps(
            self.tree,
            self.best_exit,
            self.revenue,
            self.mail_to,
            self.postage,
            self.bonus_output,
            self.sell_seconds,
            self.mail_seconds,
            self.disenchant_seconds,
        )

    @cached_property
    def timing(self) -> Timing | None:
        """How long a batch takes in the model's city (with `fastest`, the quickest of its cities that has
        every station the plan needs), routed step by step (see `time_result`); None without a time model.
        Worked out when first read, like `steps`."""
        model = self.time_model
        if model is None:
            return None
        if not model.fastest:
            return time_result(self, model)
        timings = [time_result(self, replace(model, city=c, fastest=())) for c in model.fastest]
        usable = [t for t in timings if not t.missing] or timings
        return min(usable, key=lambda t: t.total_seconds)

    @property
    def rate(self) -> int | None:
        """Copper per hour of play; None without a time model."""
        t = self.timing
        return None if t is None else t.per_hour(self.profit)

    @property
    def short(self) -> int:
        """Units the plan buys on the AH beyond what is listed there (see `Node.short`)."""
        return _short(self.tree)

    @property
    def profit(self) -> int:
        return self.revenue - self.cost

    @property
    def roi(self) -> float:
        return self.profit / self.cost if self.cost else 0.0


@dataclass(frozen=True)
class Filters:
    """Inclusive bounds on a result's cost and profit (copper) and ROI (0.5 = 50%); None is unbounded."""

    min_cost: int | None = None
    max_cost: int | None = None
    min_profit: int | None = None
    max_profit: int | None = None
    min_roi: float | None = None
    max_roi: float | None = None

    def accepts(self, r: Result) -> bool:
        def within(value: float, lo: float | None, hi: float | None) -> bool:
            return (lo is None or value >= lo) and (hi is None or value <= hi)

        return (
            within(r.cost, self.min_cost, self.max_cost)
            and within(r.profit, self.min_profit, self.max_profit)
            and within(r.roi, self.min_roi, self.max_roi)
        )


# The cheapest way to hold (item, quantity) at a character with that many chain levels above it: the same
# whichever recipe asks, so one memo serves a whole ranking.
Memo = dict[tuple[int, int, str, int], Node | None]
# The user's picks by tree path ("r" is the recipe's craft, "r.0" its first reagent, "r.0.1" that one's
# second reagent, "sell" the exit): an Option key, or an exit kind for "sell". Unknown keys are ignored.
Choices = Mapping[str, str]
ROOT = "r"
SELL = "sell"


def _touches(choices: Choices, path: str) -> bool:
    """Whether any choice is at `path` or below it."""
    return any(k == path or k.startswith(path + ".") for k in choices)


def _option(key: str, node: Node) -> Option:
    if node.via:
        return Option(
            key, node.cost, via=node.via, crafter=node.crafter, seconds=node.seconds, convert=node.convert
        )
    return Option(key, node.cost, source=node.source, seconds=node.seconds)


def ah_net(price: int, cut: float = AH_CUT) -> int:
    return int(price * (1 - cut))


def vendor_price(list_price: int, talent: int = 0, reputation: int = 0) -> int:
    """What a vendor charges per unit after the buyer's talent (Bartering) and reputation discounts, both
    in percent, rounded up. The two add up, as vanilla adds its reputation and rank discounts: an
    assumption until a Forever vendor's price has been compared."""
    return -(-list_price * max(0, 100 - talent - reputation) // 100)


def _price_holders(
    city: timing.CityMap, item_id: int, known: Mapping[int, int]
) -> tuple[int, tuple[str, ...]]:
    """(the best percent off among `city`'s sellers of the item for a buyer with `known` discounts by
    faction, the vendors giving it); (0, ()) if none gives one."""
    by_seller = {v: known.get(city.reputation_of(v), 0) for v in city.sellers(item_id)}
    best = max(by_seller.values(), default=0)
    if best <= 0:
        return 0, ()
    return best, tuple(v for v, percent in by_seller.items() if percent == best)


def city_prices(city: timing.CityMap, buyers: Sequence[Mapping[int, int]]) -> frozenset[tuple[int, int, int]]:
    """What `city`'s vendors take off for `buyers` (each their discounts by faction, in percent): (index of
    the buyer, item id, percent) for every item one of them gets cheaper there. Cities where this is equal
    charge those buyers the same for everything, so a plan costs the same in each."""
    items = sorted({i for stock in city.vendor_items.values() for i in stock})
    return frozenset(
        (n, i, percent)
        for n, known in enumerate(buyers)
        if known
        for i in items
        if (percent := _price_holders(city, i, known)[0])
    )


StepKey = tuple[str, int, str, str]  # (action, item_id, who, via): a merged step
_ACTION_RANK = {"buy": 0, "gather": 0, "craft": 1, "mail": 2, "sell": 3}


def _schedule(steps: dict[StepKey, Step], deps: dict[StepKey, set[StepKey]]) -> list[Step]:
    """`steps` (in tree walk order) with every step after those in `deps` it needs, switching characters
    as rarely as possible: one character at a time does everything they can (all their buys, then crafts,
    then mails, then the sale), preferring whoever can finish outright, else whoever can do the most, else
    the first met. A character comes back only for what waited on someone else's mail."""
    index = {key: i for i, key in enumerate(steps)}
    done: set[StepKey] = set()
    out: list[Step] = []
    while len(done) < len(steps):
        best: tuple[tuple[bool, int, int], list[StepKey]] | None = None
        for who in dict.fromkeys(key[2] for key in steps if key not in done):
            theirs = [key for key in steps if key[2] == who and key not in done]
            ready: set[StepKey] = set()
            grew = True
            while grew:
                grew = False
                for key in theirs:
                    if key not in ready and all(d in done or d in ready for d in deps[key]):
                        ready.add(key)
                        grew = True
            if not ready:
                continue
            block = sorted(ready, key=lambda k: (_ACTION_RANK[k[0]], index[k]))
            score = (len(ready) < len(theirs), -len(ready), index[block[0]])
            if best is None or score < best[0]:
                best = (score, block)
        assert best is not None, "a step depends on itself"
        out.extend(steps[key] for key in best[1])
        done.update(best[1])
    return out


def plan_steps(
    tree: Node,
    sell_via: str,
    revenue: int,
    mail_to: str = "",
    postage: int = 0,
    bonus: float = 0.0,
    sell_seconds: float = 0.0,
    mail_seconds: float = 0.0,
    disenchant_seconds: float = 0.0,
) -> list[Step]:
    """Instructions for a craft tree: buy every bought reagent (merged per item and character), craft
    intermediates, mail each to the character who needs it, craft, mail the output to `mail_to` if set
    (`postage` in total), then sell (`bonus` expected extra units besides the made ones; an enchant, sold
    via `SKILL_EXIT`, ends with its cast). Nothing comes
    before what it needs; within that, the steps are
    grouped per character, each doing all their buys, then crafts, then mails before another takes
    over (see `_schedule`). Sub-crafts are whole crafts, so a multi-output intermediate may leave
    spares. Each step names the tree paths it stands for (a mail its craft's) and carries its nodes'
    seconds (`sell_seconds` and `mail_seconds` for the sale and the output's mail)."""
    steps: dict[StepKey, Step] = {}  # in walk order
    deps: dict[StepKey, set[StepKey]] = {}

    def add(step: Step, needs: set[StepKey]) -> StepKey:
        key = (step.action, step.item_id, step.who, step.via)
        had = steps.get(key)
        steps[key] = (
            replace(
                step,
                quantity=step.quantity + had.quantity,
                value=step.value + had.value,
                paths=had.paths + step.paths,
                seconds=step.seconds + had.seconds,
            )
            if had
            else step
        )
        deps.setdefault(key, set()).update(needs)
        return key

    def walk(node: Node, path: str) -> StepKey:
        """Adds the node's steps; the key of the one that puts its items in its consumer's hands."""
        at = (path,)
        if not node.via:
            step = Step(
                "gather" if node.source == "gather" else "buy",
                node.item_id,
                node.name,
                node.quantity,
                -node.cost,
                node.source,
                node.crafter,
                at,
                discount=node.discount,
                rep_discount=node.rep_discount,
                seconds=node.act_seconds,
            )
            return add(step, set())
        inputs = {walk(n, f"{path}.{i}") for i, n in enumerate(node.inputs)}
        craft = add(_craft_step(node, at), inputs)
        if not node.mail_to:
            return craft
        mail = Step(
            "mail",
            node.item_id,
            node.name,
            node.quantity,
            -node.postage,
            node.mail_to,
            node.crafter,
            at,
            seconds=node.mail_seconds,
        )
        return add(mail, {craft})

    inputs = {walk(n, f"{ROOT}.{i}") for i, n in enumerate(tree.inputs)}
    who, root = tree.crafter, (ROOT,)
    # a flip crafts nothing: what was bought is what is sold
    last = next(iter(inputs)) if tree.flip else add(_craft_step(tree, root), inputs)
    if mail_to:
        mail = Step(
            "mail", tree.item_id, tree.name, tree.made, -postage, mail_to, who, root, seconds=mail_seconds
        )
        last = add(mail, {last})
    if sell_via == SKILL_EXIT:
        return _schedule(steps, deps)
    sale = Step(
        "sell",
        tree.item_id,
        tree.name,
        tree.made,
        revenue,
        sell_via,
        mail_to or who,
        (SELL,),
        bonus=bonus,
        seconds=sell_seconds,
        lead_seconds=disenchant_seconds,
    )
    add(sale, {last})
    return _schedule(steps, deps)


def _craft_step(node: Node, paths: tuple[str, ...]) -> Step:
    return Step(
        "craft",
        node.item_id,
        node.name,
        node.made,
        via=node.via,
        who=node.crafter,
        paths=paths,
        seconds=node.act_seconds,
        station=node.station,
        convert=node.convert,
        enchant=node.enchant,
    )


# --- exact timing ------------------------------------------------------------------------------------
_STEP_KIND = {("buy", "ah"): "ah", ("buy", "vendor"): "vendor", ("sell", "ah"): "ah"}


def _step_kind(step: Step) -> str:
    """The `timing.BREAKDOWN` kind a step's seconds count as."""
    if step.action in ("craft", "mail"):
        return step.action
    if step.action == "sell":
        return {"ah": "ah", "vendor": "vendor"}.get(step.via, "disenchant")
    return _STEP_KIND.get((step.action, step.via), "vendor")


def time_result(result: Result, model: TimeModel) -> timing.Timing:
    """How long a batch of `result` takes in the model's city: its steps in order, one block per stretch a
    character is logged in (see `_schedule`), each routed through the city (`timing.time_blocks`). A
    character who was mailed something starts at the mailbox; one search per item on the AH is paid per
    batch, for buying and for selling (disenchant materials count as sold on the AH). A vendor buy is made
    where the buyer's reputation gets them the best price (`vendor_holders`)."""
    blocks: list[timing.Block] = []
    mailed: set[str] = set()  # who has been sent something so far
    run: list[Step] = []
    holders = vendor_holders(result, model.city)

    def close() -> None:
        if not run:
            return
        who = run[0].who
        searched = {s.item_id for s in run if s.via == "ah"}
        bought = {
            s.item_id for s in run if s.action == "buy" and s.via == "ah"
        }  # one mail each, however many
        searched |= {m.item_id for s in run if s.via == "disenchant" for m in _materials(result)}
        per_craft: dict[str, float] = {}
        for s in run:
            kind = _step_kind(s)
            per_craft[kind] = per_craft.get(kind, 0.0) + s.seconds
        stations = tuple(dict.fromkeys(s.station for s in run if s.action == "craft" and s.station))
        blocks.append(
            timing.Block(
                who,
                receives_mail=who in mailed,
                buys_ah=any(s.action == "buy" and s.via == "ah" for s in run),
                vendor_items=frozenset(s.item_id for s in run if s.action == "buy" and s.via == "vendor"),
                vendor_sellers={item_id: at for (buyer, item_id), at in holders.items() if buyer == who},
                stations=stations,
                sends_mail=any(s.action == "mail" for s in run),
                sells_ah=any(s.action == "sell" and s.via in ("ah", "disenchant") for s in run),
                sells_vendor=any(s.action == "sell" and s.via == "vendor" for s in run),
                fixed={
                    "ah": model.config.ah_search * len(searched),
                    "mail": model.config.mail_open * len(bought),
                },
                per_craft=per_craft,
            )
        )
        mailed.difference_update({who})
        mailed.update(s.via for s in run if s.action == "mail")
        run.clear()

    for step in result.steps:
        if run and step.who != run[0].who:
            close()
        run.append(step)
    close()
    return timing.time_blocks(blocks, model.config, model.city)


def vendor_holders(result: Result, city: timing.CityMap) -> dict[tuple[str, int], frozenset[str]]:
    """For each vendor buy of `result`, as (buyer, item id): the vendors in `city` who give that buyer their
    best price there. A buy nobody there discounts is left out: any seller will do."""
    out: dict[tuple[str, int], frozenset[str]] = {}
    for s in result.steps:
        if s.action == "buy" and s.via == "vendor":
            _, sellers = _price_holders(city, s.item_id, result.reputations.get(s.who, {}))
            if sellers:
                out[s.who, s.item_id] = frozenset(sellers)
    return out


def cost_in(result: Result, city: timing.CityMap, items: Mapping[int, Item]) -> int:
    """What `result`'s plan costs with its vendor buys made in `city`, each at the best price a vendor there
    gives the buyer. The plan stays as it is: for a city that charges the crafters differently from the one
    it was chosen in, another plan may be cheaper still."""

    def extra(n: Node) -> int:
        more = sum(extra(i) for i in n.inputs)
        item = items.get(n.item_id)
        if n.source == "vendor" and item is not None and item.vendor_price is not None:
            percent, _ = _price_holders(city, n.item_id, result.reputations.get(n.crafter, {}))
            more += n.quantity * vendor_price(item.vendor_price, n.discount, percent) - n.cost
        return more

    return result.cost + extra(result.tree)


def reputation_faction(result: Result, who: str, item_id: int) -> int:
    """The faction whose standing gets `who` their discount on `item_id` in the city the result is timed
    in: that of the vendor nearest the hub who gives it. 0 if none does, or without a timing."""
    city, model = timed_city(result), result.time_model
    if city is None or model is None:
        return 0
    _, sellers = _price_holders(city, item_id, result.reputations.get(who, {}))
    seller = city.vendor_for(item_id, city.hub.id, model.config, sellers)
    return 0 if seller is None else city.reputation_of(seller.id)


@dataclass(frozen=True)
class Detail:
    """One line of a plan spelled out: `switch` to another character, `start` (where a character's stretch
    begins: the hub), `go` somewhere (with what to take from the mailbox there), or do a `step` (an index
    into the result's `steps`)."""

    kind: str  # switch | start | go | step
    who: str
    step: int | None = None
    location_id: str = ""  # start: where they stand; go: where to
    retrieve: tuple[tuple[int, str, int], ...] = ()  # go to collect: (item id, name, quantity) waiting there
    seconds: float = 0.0  # go: the run there


def timed_city(result: Result) -> timing.CityMap | None:
    """The city `result.timing` was worked out in; None without a time model."""
    model, t = result.time_model, result.timing
    if model is None or t is None:
        return None
    return next((c for c in (model.city, *model.fastest) if c.name == t.city), model.city)


def _placed(station: str) -> bool:
    return bool(station) and station not in timing.DEPLOYABLE


class _Spelling:
    """One character's stretch being spelled out: the steps still to say, where they stand, the lines."""

    def __init__(
        self,
        steps: Sequence[Step],
        run: Sequence[int],
        out: list[Detail],
        start: str,
        leg: Callable[[str, str], float],
    ) -> None:
        self.steps, self.out, self.leg = steps, out, leg
        self.who = steps[run[0]].who
        self.pending = list(run)
        self.at = start

    def take(self, match: Callable[[Step], bool]) -> None:
        for i in [i for i in self.pending if match(self.steps[i])]:
            self.pending.remove(i)
            self.out.append(Detail("step", self.who, i))

    def go(self, loc: str, retrieve: tuple[tuple[int, str, int], ...] = ()) -> None:
        if loc != self.at or retrieve:
            seconds = self.leg(self.at, loc)
            self.out.append(Detail("go", self.who, location_id=loc, retrieve=retrieve, seconds=seconds))
        self.at = loc

    def crafts(self, station: str | None) -> None:
        """Crafts in order: those needing no placed station, and those at `station` (every one if None), up
        to the first that needs another station."""
        for i in list(self.pending):
            s = self.steps[i]
            if s.action != "craft":
                continue
            if _placed(s.station) and station is not None and s.station != station:
                break
            self.pending.remove(i)
            self.out.append(Detail("step", self.who, i))


def detailed_steps(result: Result) -> list[Detail]:
    """The result's steps with where to go in between, following the route its timing took: per character
    (as `time_result` splits them), buys where they are bought, a stop at the mailbox to collect AH
    purchases and alts' mail, crafts at their stations (the rest where the character stands), then mail and
    sales where they happen. Each character's stretch opens with where they start (the hub). Every step
    appears once; empty without a timing."""
    city, t, model = timed_city(result), result.timing, result.time_model
    if city is None or t is None or model is None:
        return []
    config = model.config

    def leg(a: str, b: str) -> float:
        return city.seconds(a, b, config)

    steps = result.steps
    stops = list(t.stops)
    holders = vendor_holders(result, city)
    out: list[Detail] = []
    mailed: dict[str, list[tuple[int, str, int]]] = {}  # recipient -> what waits in their mailbox
    runs: list[list[int]] = []
    for i, step in enumerate(steps):
        if runs and steps[runs[-1][0]].who == step.who:
            runs[-1].append(i)
        else:
            runs.append([i])
    for n, run in enumerate(runs):
        me = _Spelling(steps, run, out, city.hub.id, leg)
        if n:
            out.append(Detail("switch", me.who, seconds=config.switch_character))
        out.append(Detail("start", me.who, location_id=city.hub.id))
        mine: list[timing.Stop] = []
        while stops and stops[0].who == me.who:
            mine.append(stops.pop(0))
        vendors = [
            st.location_id
            for st in mine
            if st.phase == "gather" and city.location(st.location_id).kind == "vendor"
        ]
        disposing = False
        for st in mine:
            loc = st.location_id
            kind = city.location(loc).kind
            if st.phase == "gather":
                me.go(loc)
                if kind == "ah":
                    me.take(_ah_buy)
                else:  # what this vendor sells; the last vendor also takes what no vendor here sells
                    sold = city.vendor_items.get(loc, frozenset())
                    me.take(_vendor_buy(sold, loc == vendors[-1], loc, holders))
            elif st.phase == "collect":
                bought = [
                    (steps[i].item_id, steps[i].name, steps[i].quantity) for i in run if _ah_buy(steps[i])
                ]
                me.go(loc, tuple(bought + mailed.pop(me.who, [])))
            elif st.phase == "station":
                me.go(loc)
                me.crafts(kind)
            else:
                if not disposing:
                    disposing = True
                    me.crafts(None)  # whatever is left, where they stand (a station the city lacks)
                me.go(loc)
                if kind == "mailbox":
                    me.take(lambda s: s.action == "mail")
                elif kind == "ah":
                    me.take(lambda s: s.action == "sell" and s.via in ("ah", "disenchant"))
                else:
                    me.take(lambda s: s.action == "sell" and s.via == "vendor")
        me.crafts(None)
        for i in me.pending:  # nothing should be left; if something is, it still gets said
            out.append(Detail("step", me.who, i))
        for i in run:
            if steps[i].action == "mail":
                mailed.setdefault(steps[i].via, []).append(
                    (steps[i].item_id, steps[i].name, steps[i].quantity)
                )
    return out


def _vendor_buy(
    sold: frozenset[int], anything: bool, loc: str, holders: Mapping[tuple[str, int], frozenset[str]]
) -> Callable[[Step], bool]:
    """The vendor buys made at `loc`: what it sells (`anything` still to buy, at the last vendor), but a
    buy at a reputation discount only if this vendor gives it."""

    def here(s: Step) -> bool:
        if s.action != "buy" or s.via != "vendor":
            return False
        return anything or (s.item_id in sold and loc in holders.get((s.who, s.item_id), (loc,)))

    return here


def _recosted(node: Node, cost: int, short: int) -> Node:
    """`node` at another cost, the option it took with it."""
    if cost == node.cost and short == node.short:
        return node
    options = tuple(replace(o, cost=cost) if o.key == node.option else o for o in node.options)
    return replace(node, cost=cost, short=short, options=options)


def _short(node: Node) -> int:
    return node.short + sum(_short(i) for i in node.inputs)


def _ah_buy(step: Step) -> bool:
    return step.action == "buy" and step.via == "ah"


def _materials(result: Result) -> tuple[Material, ...]:
    return next((e.materials for e in result.exits if e.kind == "disenchant"), ())


class Market:
    def __init__(
        self,
        items: dict[int, Item],
        recipes: list[Recipe],
        prices: dict[int, int],
        disenchant: list[DisenchantRow] | None = None,
        ah_cut: float = AH_CUT,
        *,
        crafters: Sequence[Crafter] = (),
        unlearned: Learning | Unlearned = "none",
        exits: frozenset[str] = ALL_EXITS,
        no_ah: frozenset[int] = frozenset(),
        include_trivial: bool = True,
        skill_crafters: frozenset[str] = frozenset(),
        final_crafter: str = "",
        mail_postage: int = MAIL_POSTAGE,
        sell_prices: dict[int, int] | None = None,
        time: TimeModel | None = None,
        books: Mapping[int, book.Ladder] | None = None,
        reputation_discounts: Mapping[int, int] | None = None,
        arcane_salvager: bool = False,
        gathered: Mapping[int, int] | None = None,
        later_rivals: Sequence[Rival] = (),
    ):
        """`crafters` are the characters who craft and disenchant, mailing items between them; without
        them one unnamed character does everything. When nobody has learned a recipe, `unlearned` says who
        may craft it anyway (see `can_learn`). Crafts are only sold via `exits`, and items in
        `no_ah` never on the AH (they may still be bought there). Without `include_trivial` the final craft
        is only done by a character it can give a skillup (see `can_skill_up`); sub-crafts may be grey.
        `skill_crafters` names the characters being skilled up: the final craft is then done only by one of
        them, the lowest-skilled in the recipe's profession (sub-crafts still by anyone). A `final_crafter`
        (the user's pick) does every final craft they can, whatever the other two say, and no other.
        `mail_postage` is the copper charged per mail attachment on this game version. Reagents are bought
        at `prices`; crafts and disenchant materials are sold at `sell_prices` (default: `prices`), which
        may be more conservative than the newest listing. With a `time` model every node and result
        carries estimated play time, and with its time value plans are chosen by copper plus the value of
        that time (see `_effective`).

        An item in `books` is bought up its ladder instead (`book.cost`): the units listed at each price,
        cheapest first, so what it costs depends on how many are needed; units the book is short of are
        counted at its dearest price and reported (`Node.short`). Branches of one plan buying the same
        item share its ladder (`_share_books`).

        `reputation_discounts` is the game version's percent off at a vendor by the buyer's standing with
        the vendor's faction (standing -> percent). It needs the `time` model's city, which says whose
        vendors sell an item there: a buyer pays the best price a vendor there gives them, and the plan is
        routed to such a vendor. Without a time model every vendor charges the list price.

        With `arcane_salvager` every disenchant is done at an Arcane Salvager: its materials are worth
        `ARCANE_SALVAGER_BONUS` more (each `Material` still describes one roll).

        `gathered` are items the user gathers themselves, each with what a unit is worth to them (what
        selling it would have made): they can be had for that, as a `gather` option after buying it.

        `later_rivals` are recipes the characters can't learn yet that a skill-up run may meet on the way
        (`run_until_cheaper`); the recipes they can do now are its rivals too (`_rivals`)."""
        self.items = items
        self.gathered = dict(gathered or {})
        self.later_rivals = tuple(later_rivals)
        self._rival_cache: dict[str, list[Rival]] = {}
        self.recipes = recipes
        self.prices = prices
        self.books = books or {}
        self.sell_prices = prices if sell_prices is None else sell_prices
        self.disenchant = disenchant or []
        self.arcane_salvager = arcane_salvager
        self.ah_cut = ah_cut
        self.crafters = crafters
        self.unlearned = Learning.of(unlearned)
        self.exits = exits
        self.no_ah = no_ah
        self.include_trivial = include_trivial
        self.skill_crafters = skill_crafters
        self.final_crafter = final_crafter
        self.mail_postage = mail_postage
        self.time = time
        self._per_second = time.config.time_value / 3600 if time else 0.0  # copper a second of play is worth
        self._trips: dict[str, float] = {}
        # flips are this market's own: made anew from its items and prices, whatever `recipes` held
        self.recipes = [r for r in recipes if not r.is_flip] + self._flips()
        self._by_output: dict[int, list[Recipe]] = {}
        for r in self.recipes:
            if not r.is_flip and not r.is_enchant:  # neither is a way to get an item
                self._by_output.setdefault(r.output_item_id, []).append(r)
        self._who_crafts = {r.id: self._crafter_names(r) for r in self.recipes}
        self._by_name = {c.name: c for c in crafters}
        self.reputation_discounts = dict(reputation_discounts or {})
        # who -> {faction id: percent off at that faction's vendors}, for those with any
        self._rep: dict[str, dict[int, int]] = {
            c.name: known
            for c in crafters
            if (known := dict(vendor_discounts(c.reputations, self.reputation_discounts)))
        }
        self._holders: dict[tuple[int, str], tuple[int, tuple[str, ...]]] = {}  # memo for `_reputation`

    def _flips(self) -> list[Recipe]:
        """A flip for every item that can be disenchanted (`_disenchant_rows`) and bought on the AH: buy
        it, disenchant it, sell the materials."""
        return [
            Recipe(FLIP_ID_BASE + i, item.name, i, 1, ((i, 1),), kind="flip")
            for i, item in sorted(self.items.items())
            if self._listed(i) and self._disenchant_rows(item)
        ]

    def _listed(self, item_id: int) -> int:
        """Units that can be bought on the AH: its ladder's (the levels plans count on), else one if it has
        a price but no ladder (cheapest-listing prices), else none."""
        if item_id in self.books:
            return sum(lv.quantity for lv in self.books[item_id])
        return 1 if item_id in self.prices else 0

    # --- selling ---------------------------------------------------------------------
    def _disenchant_rows(self, item: Item) -> list[DisenchantRow]:
        if (
            not item.disenchantable
            or item.class_id not in DISENCHANTABLE_CLASSES
            or item.quality not in DISENCHANTABLE_QUALITIES
        ):
            return []
        return [
            d
            for d in self.disenchant
            if d.item_class == item.class_id
            and d.quality == item.quality
            and d.min_ilvl <= item.item_level <= d.max_ilvl
        ]

    def _expected(self, d: DisenchantRow) -> float | None:
        """Expected net AH copper from one disenchant row; None if its result is unpriced."""
        price = self.sell_prices.get(d.result_item_id)
        if price is None:
            return None
        rolls = 1 + ARCANE_SALVAGER_BONUS if self.arcane_salvager else 1
        return rolls * d.chance * (d.min_count + d.max_count) / 2 * ah_net(price, self.ah_cut)

    def disenchant_materials(self, item: Item) -> list[Material]:
        """What disenchanting one item can yield; empty if it can't be disenchanted."""
        out = []
        for d in self._disenchant_rows(item):
            value = self._expected(d)
            name = self._name(d.result_item_id)
            out.append(
                Material(
                    d.result_item_id,
                    name,
                    d.chance,
                    d.min_count,
                    d.max_count,
                    None if value is None else int(value),
                )
            )
        return out

    def disenchant_value(self, item: Item) -> int | None:
        """Expected net AH value of disenchanting one item; None if not applicable/unpriced."""
        total = sum(v for d in self._disenchant_rows(item) if (v := self._expected(d)) is not None)
        return int(total) if total else None

    def exits_for(self, item_id: int) -> list[Exit]:
        item = self.items.get(item_id)
        if item is None:
            return []
        out: list[Exit] = []
        if item.sell_price > 0:
            out.append(Exit("vendor", item.sell_price))
        if item_id in self.sell_prices and item_id not in self.no_ah and item.tradable:
            out.append(Exit("ah", ah_net(self.sell_prices[item_id], self.ah_cut)))
        de = self.disenchant_value(item)
        if de:
            out.append(Exit("disenchant", de, tuple(self.disenchant_materials(item))))
        if KEEP_EXIT in self.exits and self.skill_crafters:
            out.append(Exit(KEEP_EXIT, 0))  # last: any exit that pays wins a tie
        return out

    def _disenchanter(self, who: str) -> tuple[str, int] | None:
        """Who disenchants what `who` crafted and the postage per item to get it to them.

        ("", 0) if `who` enchants (or no characters are known), the best other enchanter and
        `mail_postage` otherwise, None if nobody enchants.
        """
        if not self.crafters or any(c.name == who and c.enchanting for c in self.crafters):
            return "", 0
        enchanters = [c for c in self.crafters if c.enchanting]
        if not enchanters:
            return None
        best = min(enchanters, key=lambda c: (-c.enchanting, c.name))
        return best.name, self.mail_postage

    def _exits_at(self, exits: list[Exit], who: str, item_id: int) -> list[Exit]:
        """`exits` for `item_id` `who` holds: disenchanting charged postage or dropped per `_disenchanter`,
        and never mailed if the item is soulbound."""
        out = []
        for e in exits:
            if e.kind == "disenchant":
                de = self._disenchanter(who)
                if de is None or (de[0] and not self._tradable(item_id)):
                    continue
                e = replace(e, mail_to=de[0], postage=de[1])
            out.append(e)
        return out

    def _tradable(self, item_id: int) -> bool:
        item = self.items.get(item_id)
        return item is None or item.tradable

    def postage(self, item_id: int, qty: int) -> int:
        """Copper to mail `qty` units: one attachment per stack."""
        return self.mail_postage * -(-qty // self._stack(item_id))

    def _stack(self, item_id: int) -> int:
        item = self.items.get(item_id)
        return max(1, item.stack_size) if item else 1

    # --- play time -----------------------------------------------------------------------------------
    # Seconds are per craft of the recipe being evaluated. A batch clicks once per whole stack (and sends
    # whole mails); those clicks, trips across the city, character switches and AH searches are shared by
    # the batch.
    def _effective(self, copper: int, seconds: float) -> float:
        """What a plan costs counting its play time at the time value: plans are compared by this."""
        return copper + self._per_second * seconds

    def _per_batch(self, count: float) -> float:
        """A per-batch count of actions, rounded up to whole ones, per craft."""
        assert self.time is not None
        batch = self.time.config.batch
        return math.ceil(count - 1e-9) / batch

    def _stacks(self, item_id: int, qty: float) -> float:
        """Per craft, the stacks a batch handles for `qty` units a craft: whole stacks, since a click takes
        as long for one unit as for a full stack (20 crafts needing 1 salt each buy one stack of 20)."""
        assert self.time is not None
        return self._per_batch(qty * self.time.config.batch / self._stack(item_id))

    def _trip(self, target: str) -> float:
        """A trip from the hub to `target` (a location id or kind) and back, shared by the batch."""
        assert self.time is not None
        got = self._trips.get(target)
        if got is None:
            got = self.time.city.trip(target, self.time.config) / self.time.config.batch
            self._trips[target] = got
        return got

    def _buy_seconds(self, item_id: int, qty: int, source: str, buyer: str = "") -> tuple[float, float]:
        """(the buy's own seconds, with the shared trip and search) for `qty` units from `source`; a vendor
        buy's trip is to the nearest seller who gives `buyer` their price."""
        if self.time is None:
            return 0.0, 0.0
        cfg, stacks = self.time.config, self._stacks(item_id, qty)
        if source == "ah":  # the purchase arrives by mail: one mail per item, and a trip to the mailbox
            act = cfg.ah_buy * stacks
            return act, act + (cfg.ah_search + cfg.mail_open) / cfg.batch + self._trip("ah") + self._trip(
                "mailbox"
            )
        act = cfg.vendor_buy * stacks
        _, holders = self._reputation(item_id, buyer)
        key = f"vendor-of:{item_id}:{buyer if holders else ''}"
        if key not in self._trips:
            seller = self.time.city.vendor_for(item_id, self.time.city.hub.id, cfg, holders or None)
            self._trips[key] = self._trip(seller.id if seller else "vendor")
        return act, act + self._trips[key]

    def _mail_seconds(self, item_id: int, qty: int) -> tuple[float, float]:
        """(sending and taking `qty` units, with both characters' mailbox trips and the switch)."""
        if self.time is None:
            return 0.0, 0.0
        cfg, stacks = self.time.config, self._stacks(item_id, qty)
        mails = self._per_batch(stacks * cfg.batch / cfg.mail_attachments)
        act = cfg.mail_attach * stacks + mails * (cfg.mail_send + cfg.mail_open)
        return act, act + cfg.switch_character / cfg.batch + 2 * self._trip("mailbox")

    def _craft_seconds(self, recipe: Recipe, runs: int) -> tuple[float, float, str]:
        """(`runs` casts, with the shared trip to its station, the station kind). A flip casts nothing."""
        if self.time is None or recipe.is_flip:
            return 0.0, 0.0, ""
        station = recipe.station
        act = runs * (recipe.cast_time_ms / 1000 + self.time.config.craft_overhead)
        return act, act + (self._trip(station) if station else 0.0), station

    def _sell_seconds(self, exit: Exit, item_id: int, made: int) -> tuple[float, float]:
        """(selling `made` units via `exit`, with its shared trip and searches)."""
        if self.time is None:
            return 0.0, 0.0
        cfg = self.time.config
        if exit.kind == SKILL_EXIT:
            return 0.0, 0.0
        if exit.kind == "vendor":
            act = cfg.vendor_sell * self._stacks(item_id, made)
            return act, act + self._trip("vendor")
        if exit.kind == "ah":
            act = cfg.ah_post * self._stacks(item_id, made)
            return act, act + cfg.ah_search / cfg.batch + self._trip("ah")
        posts = sum(
            self._stacks(m.item_id, m.chance * (m.min_count + m.max_count) / 2 * made) for m in exit.materials
        )
        act = cfg.disenchant * made + cfg.ah_post * posts
        return act, act + cfg.ah_search * len(exit.materials) / cfg.batch + self._trip("ah")

    # --- buying / chains ---------------------------------------------------------------
    def _crafter_names(self, recipe: Recipe) -> list[str]:
        """Who can craft `recipe` (`crafters_of`), plus the characters being skilled up who could learn it
        although someone else already has: a recipe an alt knows is still one to skill up on."""
        if not self.crafters:
            return [""]  # one unnamed character who does everything
        names = [c.name for c in crafters_of(recipe, self.crafters, self.unlearned)]
        if self.skill_crafters and not recipe.anyone:
            names += [
                c.name
                for c in self.crafters
                if c.name in self.skill_crafters
                and c.name not in names
                and can_learn(recipe, c, self.unlearned)
            ]
        return names

    def _final_crafters(self, recipe: Recipe) -> list[str]:
        """Who may do `recipe`'s final craft: anyone who can craft it, or without `include_trivial` only
        those it can give a skillup (everyone if no characters are known); with `skill_crafters`, only the
        lowest-skilled of those among them; with a `final_crafter`, only them. An enchant is cast for the
        skill point alone, so only ever by someone it can give one."""
        who = self._who(recipe)
        if not self.crafters:
            return who
        if recipe.is_enchant:
            who = [w for w in who if can_skill_up(recipe, self._by_name[w])]
        if self.final_crafter:
            return [w for w in who if w == self.final_crafter]
        if not self.include_trivial:
            who = [w for w in who if can_skill_up(recipe, self._by_name[w])]
        if self.skill_crafters:
            who = [w for w in who if w in self.skill_crafters]
            ranks = {w: (self._by_name[w].skill(recipe.skill_name) or (0, 0))[0] for w in who}
            who = [w for w in who if ranks[w] == min(ranks.values())]
        return who

    def _reputation(self, item_id: int, buyer: str) -> tuple[int, tuple[str, ...]]:
        """The best percent off `buyer`'s standings get them on `item_id` in the model's city, and the
        vendors there who give it; (0, ()) without a city, a standing that counts or such a vendor."""
        known = self._rep.get(buyer)
        if self.time is None or not known:
            return 0, ()
        key = (item_id, buyer)
        got = self._holders.get(key)
        if got is None:
            got = self._holders[key] = _price_holders(self.time.city, item_id, known)
        return got

    def _vendor_unit(self, item: Item, buyer: str) -> tuple[int, int, int]:
        """What `buyer` pays a vendor per unit of `item` (see `vendor_price`), and the percent off their
        talents and their reputation get them."""
        assert item.vendor_price is not None
        c = self._by_name.get(buyer)
        discount = c.vendor_discount if c else 0
        reputation, _ = self._reputation(item.id, buyer)
        return vendor_price(item.vendor_price, discount, reputation), discount, reputation

    def _bonus_output(self, recipe: Recipe, who: str) -> float:
        """Expected extra units a craft of `recipe` by `who` gives (Master Chef)."""
        c = self._by_name.get(who)
        return c.extra_chance(recipe.skill_name) if c else 0.0

    def _who(self, recipe: Recipe) -> list[str]:
        """Who can craft `recipe`."""
        got = self._who_crafts.get(recipe.id)
        return got if got is not None else self._crafter_names(recipe)

    def _name(self, item_id: int) -> str:
        return self.items[item_id].name if item_id in self.items else str(item_id)

    def _ah_cost(self, item_id: int, qty: int, skip: int = 0) -> tuple[int, int] | None:
        """(copper, units short) for `qty` units off the auction house, after `skip` units already taken
        from the item's ladder; None if it has no price there."""
        ladder = self.books.get(item_id)
        if ladder:
            upto, before = book.cost(ladder, skip + qty), book.cost(ladder, skip)
            assert upto is not None and before is not None
            return upto[0] - before[0], upto[1] - before[1]
        if item_id in self.prices:
            return qty * self.prices[item_id], 0
        return None

    def _share_books(self, tree: Node) -> Node:
        """`tree` with the auction house buys of an item that several of its branches buy costed as one
        walk up the item's ladder, in the tree's order: each branch was planned as if the cheapest units
        were its own. Costs change up to the root; the plan stays as chosen."""
        buys: dict[int, int] = {}

        def count(n: Node) -> None:
            if n.source == "ah" and n.item_id in self.books:
                buys[n.item_id] = buys.get(n.item_id, 0) + 1
            for i in n.inputs:
                count(i)

        count(tree)
        shared = {item_id for item_id, times in buys.items() if times > 1}
        if not shared:
            return tree
        taken: dict[int, int] = {}

        def walk(n: Node) -> Node:
            if n.source == "ah" and n.item_id in shared:
                skip = taken.get(n.item_id, 0)
                taken[n.item_id] = skip + n.quantity
                got = self._ah_cost(n.item_id, n.quantity, skip)
                assert got is not None
                return _recosted(n, got[0], got[1])
            inputs = tuple(walk(i) for i in n.inputs)
            added = sum(new.cost - old.cost for new, old in zip(inputs, n.inputs, strict=True))
            return replace(_recosted(n, n.cost + added, n.short), inputs=inputs)

        return walk(tree)

    def _obtain(
        self,
        item_id: int,
        qty: int,
        at: str,
        depth: int,
        memo: Memo,
        path: str = ROOT,
        choices: Choices | None = None,
    ) -> Node | None:
        """The cheapest way for `at` to hold `qty` units, or the one `choices` picks at `path`: buy them
        (vendor or AH), or craft them in whole batches (themselves, or, unless the item is soulbound,
        another character who mails them over), or gather them (`gathered`). Ties prefer the vendor, then
        the AH, then gathering, then crafting. The
        node lists every option. Chains stop `MAX_CHAIN_DEPTH` levels down, which also ends any cycle: a
        chain through the item itself is never cheaper than getting it directly, so it loses the tie."""
        choices = choices or {}
        key = (item_id, qty, at, depth)
        # A subtree's cheapest plan doesn't depend on where it sits, unless the user changed something in it.
        chosen = _touches(choices, path)
        if not chosen and key in memo:
            return memo[key]
        name = self._name(item_id)
        candidates: list[tuple[str, Node]] = []
        item = self.items.get(item_id)
        if item is not None and item.vendor_price is not None:
            unit, discount, reputation = self._vendor_unit(item, at)
            act, est = self._buy_seconds(item_id, qty, "vendor", at)
            candidates.append(
                (
                    "vendor",
                    Node(
                        item_id,
                        name,
                        qty,
                        qty * unit,
                        source="vendor",
                        crafter=at,
                        discount=discount,
                        rep_discount=reputation,
                        seconds=est,
                        act_seconds=act,
                    ),
                )
            )
        listed = self._ah_cost(item_id, qty)
        if listed is not None:
            act, est = self._buy_seconds(item_id, qty, "ah")
            bought = Node(
                item_id,
                name,
                qty,
                listed[0],
                source="ah",
                crafter=at,
                short=listed[1],
                seconds=est,
                act_seconds=act,
            )
            candidates.append(("ah", bought))
        worth = self.gathered.get(item_id)
        if worth is not None:
            candidates.append(("gather", Node(item_id, name, qty, qty * worth, source="gather", crafter=at)))
        if depth < MAX_CHAIN_DEPTH:
            tradable = item is None or item.tradable
            for r in self._by_output.get(item_id, []):
                if any(i == item_id for i, _ in r.reagents):
                    continue  # a recipe that consumes what it makes is no way to get it
                runs = -(-qty // r.output_count)
                crafted: list[Node] = []
                for who in sorted(self._who(r), key=lambda w: w != at):
                    if who != at and not tradable:
                        continue
                    node = self._craft(r, qty, runs, who, depth + 1, memo, path, choices)
                    if node is not None and who != at:
                        p = self.postage(item_id, qty)
                        act, est = self._mail_seconds(item_id, qty)
                        node = replace(
                            node,
                            cost=node.cost + p,
                            mail_to=at,
                            postage=p,
                            seconds=node.seconds + est,
                            mail_seconds=act,
                        )
                    if node is not None:
                        crafted.append(node)
                if crafted:
                    best_craft = min(crafted, key=lambda n: self._effective(n.cost, n.seconds))
                    candidates.append((f"craft:{r.id}", best_craft))
        best: Node | None = None
        if candidates:
            # stable: ties keep the preference order; without a time value this is the cheapest first
            ranked = sorted(candidates, key=lambda c: self._effective(c[1].cost, c[1].seconds))
            taken, picked = next((c for c in ranked if c[0] == choices.get(path)), ranked[0])
            best = replace(picked, options=tuple(_option(k, n) for k, n in ranked), option=taken)
        if not chosen:
            memo[key] = best
        return best

    def _craft(
        self,
        recipe: Recipe,
        qty: int,
        runs: int,
        who: str,
        depth: int,
        memo: Memo,
        path: str = ROOT,
        choices: Choices | None = None,
    ) -> Node | None:
        """`runs` crafts of `recipe` by `who` (the node at `path`), getting each reagent the cheapest way
        or as `choices` says; None if one can't be had. A conversion's input is only bought: converted
        back from what it makes, it would go round in circles."""
        inputs = []
        below = MAX_CHAIN_DEPTH if recipe.anyone else depth
        for i, (item_id, count) in enumerate(recipe.reagents):
            got = self._obtain(item_id, count * runs, who, below, memo, f"{path}.{i}", choices)
            if got is None:
                return None
            inputs.append(got)
        item_id = recipe.output_item_id
        cost = sum(n.cost for n in inputs)
        made = recipe.output_count * runs
        act, est, station = self._craft_seconds(recipe, runs)
        return Node(
            item_id,
            recipe.name if recipe.is_enchant else self._name(item_id),
            qty,
            cost,
            recipe.name,
            runs,
            made,
            tuple(inputs),
            crafter=who,
            seconds=est + sum(n.seconds for n in inputs),
            act_seconds=act,
            station=station,
            convert=recipe.is_conversion,
            flip=recipe.is_flip,
            enchant=recipe.is_enchant,
        )

    # --- evaluation --------------------------------------------------------------------
    def evaluate(
        self,
        recipe: Recipe,
        choices: Choices | None = None,
        memo: Memo | None = None,
        crafts: int = 1,
        skill_run: SkillRuns | None = None,
    ) -> Result | None:
        """The most profitable way to craft and sell `recipe`: over who crafts it, how each reagent
        is had (and mailed), and the exit. `choices` fixes some of those (see `Choices`). A `memo` from an
        earlier evaluation on this market saves working the shared subtrees out again. With `crafts`, the
        plan is for that many crafts at once (a session): sub-crafts are whole batches for all of them, and
        cost, revenue and steps are the session's. With a `skill_run`, a crafter who has the recipe's
        profession makes a run of it instead (`run_until_cheaper`): as many crafts as it takes until another
        recipe would give them a cheaper skill point."""
        choices = choices or {}
        if recipe.is_flip:  # never more than are listed
            crafts = min(crafts, self._listed(recipe.output_item_id))
            if crafts <= 0:
                return None
        allowed = self._sell_kinds(recipe)
        # an enchant makes nothing: its one exit is worth nothing, and nothing is mailed to be sold
        found = [Exit(SKILL_EXIT, 0)] if recipe.is_enchant else self.exits_for(recipe.output_item_id)
        exits = [e for e in found if e.kind in allowed]
        if not exits:
            return None
        if memo is None:
            memo = {}
        by_exit: dict[str, Result] = {}  # the most profitable result for each way of selling
        for who in self._final_crafters(recipe):
            crafter = self._by_name.get(who)
            run = (
                self._skill_run(recipe, crafter, skill_run, memo)
                if skill_run is not None
                and crafter is not None
                and not recipe.anyone
                and crafter.skill(recipe.skill_name) is not None
                else None
            )
            n = run.crafts if run is not None else crafts
            tree = self._craft(recipe, recipe.output_count * n, n, who, 0, memo, ROOT, choices)
            here = self._exits_at(exits, who, recipe.output_item_id)
            if tree is None or not here:
                continue
            tree = self._share_books(tree)
            mail = self.postage(recipe.output_item_id, tree.made)
            mail_act, mail_est = self._mail_seconds(recipe.output_item_id, tree.made)
            # A Master Chef's extra results are counted at their expected number; mailing them is not charged.
            bonus = self._bonus_output(recipe, who) * n
            chance = (
                skill_up_chance(recipe, crafter) if crafter is not None else 0.0 if recipe.anyone else 1.0
            )
            ups = expected_skill_ups(recipe, crafter, n)
            ups_bonus = (
                ups - expected_skill_ups(recipe, replace(crafter, skill_bonus=0.0), n)
                if crafter is not None and crafter.skill_bonus
                else 0.0
            )
            for exit in here:
                postage = mail if exit.postage else 0
                revenue = round(exit.value * (recipe.output_count * n + bonus))
                sell_act, sell_est = self._sell_seconds(exit, recipe.output_item_id, tree.made)
                seconds = tree.seconds + sell_est + (mail_est if exit.postage else 0.0)
                had = by_exit.get(exit.kind)
                worth = revenue - self._effective(tree.cost + postage, seconds)
                if had is not None and worth <= had.profit - self._per_second * had.seconds:
                    continue  # ties keep the earlier crafter
                by_exit[exit.kind] = Result(
                    recipe,
                    tree.cost + postage,
                    revenue,
                    exit.kind,
                    tree,
                    here,
                    postage,
                    exit.mail_to,
                    who,
                    bonus_output=bonus,
                    skill_chance=chance,
                    skill_ups=ups,
                    skill_ups_bonus=ups_bonus,
                    seconds=seconds,
                    sell_seconds=sell_act,
                    disenchant_seconds=(
                        self.time.config.disenchant * tree.made
                        if self.time is not None and exit.kind == "disenchant"
                        else 0.0
                    ),
                    mail_seconds=mail_act if exit.postage else 0.0,
                    time_model=self.time,
                    crafts=n,
                    reputations=self._rep,
                    stop_skill=run.stop_skill if run is not None else 0,
                    stop_reason=run.reason if run is not None else "",
                    overtaken_by=self._name(run.rival.output_item_id)
                    if run is not None and run.rival is not None and not run.rival.is_enchant
                    else run.rival.name
                    if run is not None and run.rival is not None
                    else "",
                    overtaken_by_item=run.rival.output_item_id
                    if run is not None and run.rival is not None and not run.rival.is_enchant
                    else 0,
                    crafts_p80=run.crafts_p80 if run is not None else 0,
                    reach_chances=run.reach if run is not None else (),
                )
        if not by_exit:
            return None
        # stable sort over the exits' order (vendor, ah, disenchant): ties keep the earlier, unmailed one
        ranked = sorted(by_exit.values(), key=lambda r: self._per_second * r.seconds - r.profit)
        picked = by_exit.get(choices.get(SELL, ""), ranked[0])
        picked.sell_options = [SellOption(r.best_exit, r.profit) for r in ranked]
        return picked

    def _skill_run(self, recipe: Recipe, crafter: Crafter, runs: SkillRuns, memo: Memo) -> SkillRun:
        """`crafter`'s run of `recipe` against the other recipes of its profession (`_rivals`)."""
        rivals = self._rivals(recipe.skill_name, memo)
        cost = next((r.cost for r in rivals if r.recipe.id == recipe.id), None)
        if cost is None:
            one = self.evaluate(recipe, memo=memo)
            cost = float(-one.profit) if one is not None else 0.0
        return run_until_cheaper(recipe, crafter, cost, rivals, runs.ceiling)

    def _rivals(self, skill_name: str, memo: Memo) -> list[Rival]:
        """Every recipe of the profession that gives a skill point now, with what a craft of it comes to, and
        the `later_rivals` of it; worked out once per market."""
        key = skill_name.lower()
        found = self._rival_cache.get(key)
        if found is None:
            found = []
            for r in self.recipes:
                if r.anyone or r.skill_name.lower() != key:
                    continue
                one = self.evaluate(r, memo=memo)
                if one is not None and one.skill_chance > 0:
                    found.append(Rival(r, float(-one.profit)))
            found += [x for x in self.later_rivals if x.recipe.skill_name.lower() == key]
            self._rival_cache[key] = found
        return found

    def _sell_kinds(self, recipe: Recipe) -> Collection[str]:
        """The exits `recipe`'s output may be sold by. A conversion sells what it makes on the AH, but only
        when disenchant is allowed: it is the same bet on enchanting materials' AH prices. A flip is only
        disenchanted (reselling it would be another strategy). An enchant has only the `SKILL_EXIT`, which
        nothing else has."""
        if recipe.is_enchant:
            return self.exits & {SKILL_EXIT}
        if not recipe.anyone:
            return self.exits
        if "disenchant" not in self.exits:
            return ()
        return {"disenchant"} if recipe.is_flip else self.exits | {"ah"}

    def rank(
        self,
        min_profit: int = 0,
        skill_name: str | None = None,
        crafts: int = 1,
        only: Collection[int] | None = None,
        skill_run: SkillRuns | None = None,
    ) -> list[Result]:
        """Every recipe's best result for `crafts` crafts at once with at least `min_profit`, most
        profitable first (of the recipes with ids in `only`, if given). One memo serves the whole ranking:
        an intermediate is worked out once however many recipes need it. Conversions skill nobody up, so
        they are left out when skilling up (without `include_trivial`, or with `skill_crafters`)."""
        results = []
        memo: Memo = {}
        skilling = not self.include_trivial or bool(self.skill_crafters)
        for r in self.recipes:
            if r.anyone and skilling:
                continue
            if skill_name and r.skill_name.lower() != skill_name.lower():
                continue
            if only is not None and r.id not in only:
                continue
            res = self.evaluate(r, memo=memo, crafts=crafts, skill_run=skill_run)
            if res and res.profit >= min_profit:
                results.append(res)
        return sorted(results, key=lambda x: x.profit, reverse=True)


def recipes_using(recipes: Sequence[Recipe], items: Collection[int]) -> frozenset[int]:
    """The ids of the recipes whose plans can involve one of `items`: as a reagent, or through a reagent
    another of `recipes` makes from one, however deep. What the other recipes cost doesn't depend on what
    those items cost."""
    touched = set(items)
    found: set[int] = set()
    grew = bool(touched)
    while grew:
        grew = False
        for r in recipes:
            if r.id not in found and any(i in touched for i, _ in r.reagents):
                found.add(r.id)
                if not r.is_enchant:  # it makes no item
                    touched.add(r.output_item_id)
                grew = True
    return frozenset(found)


def recipes_for_professions(recipes: Iterable[Recipe], professions: Iterable[str]) -> list[Recipe]:
    """Recipes from the given professions (case-insensitive). A Market built from these only chains
    through recipes you can craft."""
    wanted = {p.lower() for p in professions}
    return [r for r in recipes if r.skill_name.lower() in wanted]


def recipes_for_characters(
    recipes: Iterable[Recipe], crafters: Sequence[Crafter], unlearned: Learning | Unlearned
) -> list[Recipe]:
    """Recipes the characters have learned, plus those `unlearned` lets one of them craft (`can_learn`).

    A Market built from these sub-crafts through any of the characters' recipes, whoever knows them.
    Conversions and flips need no learning: anyone can do them.
    """
    known = frozenset().union(*(c.known_spells for c in crafters))
    learning = Learning.of(unlearned)
    return [
        r
        for r in recipes
        if r.anyone or r.spell_id in known or any(can_learn(r, c, learning) for c in crafters)
    ]


def crafters_of(
    recipe: Recipe, crafters: Iterable[Crafter], unlearned: Learning | Unlearned
) -> list[Crafter]:
    """Who can craft `recipe`: those who learned it, or with nobody having learned it, those `unlearned`
    lets (`can_learn`, as in `recipes_for_characters`). Anyone converts or flips."""
    crafters = list(crafters)
    if recipe.anyone:
        return crafters
    known = [c for c in crafters if recipe.spell_id in c.known_spells]
    if known:
        return known
    return [c for c in crafters if can_learn(recipe, c, unlearned)]


def format_money(copper: int) -> str:
    sign = "-" if copper < 0 else ""
    copper = abs(copper)
    return f"{sign}{copper // 10000}g {copper // 100 % 100:02d}s {copper % 100:02d}c"
