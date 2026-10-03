"""Unit tests for scripts/generate-recipe-data.py. Run: python -m unittest scripts/test_generate_recipe_data.py"""
import csv
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("generate_recipe_data", os.path.join(HERE, "generate-recipe-data.py"))
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

SLA = ["ID", "SkillLine", "Spell", "MinSkillLineRank", "AcquireMethod", "TrivialSkillLineRankLow",
       "TrivialSkillLineRankHigh"]


def write(dirname, table, header, rows):
    path = os.path.join(dirname, table + ".csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    return path


class BuildRecipesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.paths = {
            "SkillLineAbility": write(d, "SkillLineAbility", SLA, [
                [1, 197, 2963, 1, 1, 25, 50],      # Bolt of Linen Cloth: starter
                [2, 197, 26745, 1, 0, 305, 325],   # Bolt of Netherweave: trainer
                [3, 333, 27984, 1, 0, 385, 415],   # Mongoose: enchant, recipe item
                [4, 185, 2543, 1, 0, 115, 155],    # Westfall Stew: item sold and quest reward
                [5, 171, 17635, 1, 0, 315, 330],   # Flask of the Titans: drop copy + reputation copy
                [6, 197, 9999, 1, 0, 10, 20],      # no reagents: not a recipe
                [7, 1, 8888, 1, 0, 10, 20],        # not a profession skill line
                [8, 202, 13240, 1, 0, 1, 1],       # placeholder bands, nothing teaches it
            ]),
            "SpellEffect": write(d, "SpellEffect", ["SpellID", "Effect", "EffectItemType"], [
                [2963, 24, 2996], [26745, 24, 21840], [27984, 53, 0], [2543, 24, 733],
                [17635, 24, 13510], [9999, 24, 1], [8888, 24, 1], [13240, 24, 10577],
            ]),
            "SpellReagents": write(d, "SpellReagents", ["SpellID", "Reagent_0"], [
                [2963, 2589], [26745, 21877], [27984, 22446], [2543, 1], [17635, 1], [8888, 1], [13240, 1],
            ]),
            "ItemEffect": write(d, "ItemEffect", ["ID", "ParentItemID", "TriggerType", "SpellID"], [
                [1, 22559, 6, 27984], [2, 728, 6, 2543], [3, 13519, 6, 17635], [4, 31354, 6, 17635],
                [5, 22559, 0, 1],  # a Use effect, not a learn one
            ]),
            "ItemSparse": write(d, "ItemSparse", ["ID", "RequiredSkillRank", "MinFactionID"], [
                [22559, 375, 0], [728, 75, 0], [13519, 300, 0], [31354, 300, 935],
            ]),
        }
        trainer = {26745: 300}
        quests = {}
        item_sources = {22559: "drop", 728: "vendor|quest", 13519: "drop", 31354: "vendor"}
        self.recipes = gen.build_recipes(self.paths, trainer, quests, item_sources)

    def tearDown(self):
        self.tmp.cleanup()

    def test_selects_profession_recipes_with_reagents(self):
        self.assertEqual(sorted(self.recipes), [2543, 2963, 13240, 17635, 26745, 27984])

    def test_starter_recipe(self):
        self.assertEqual(self.recipes[2963], ("tailoring", 2996, 1, 25, 50, "starter", None))

    def test_trainer_recipe_takes_server_skill(self):
        self.assertEqual(self.recipes[26745], ("tailoring", 21840, 300, 305, 325, "trainer", None))

    def test_enchant_has_no_result_item_and_uses_recipe_item(self):
        self.assertEqual(self.recipes[27984], ("enchanting", 0, 375, 385, 415, "drop", 22559))

    def test_item_with_several_sources_keeps_all(self):
        self.assertEqual(self.recipes[2543][5], "quest|vendor")

    def test_reputation_copy_joins_drop_copy(self):
        self.assertEqual(self.recipes[17635][5], "reputation|drop")
        self.assertEqual(self.recipes[17635][6], 13519)

    def test_placeholder_bands_and_untaught_recipe(self):
        self.assertEqual(self.recipes[13240], ("engineering", 10577, None, None, None, "trainer", None))


class OverridesTest(unittest.TestCase):
    def test_override_replaces_only_given_fields(self):
        recipes = {29361: ("mining", 23449, 350, 375, 400, "trainer", None)}
        out = gen.apply_overrides(recipes, {29361: (375, None)})
        self.assertEqual(out[29361], ("mining", 23449, 375, 375, 400, "trainer", None))
        out = gen.apply_overrides(recipes, {29361: (None, "trainer|quest")})
        self.assertEqual(out[29361][5], "trainer|quest")

    def test_override_for_unknown_spell_fails(self):
        with self.assertRaises(SystemExit):
            gen.apply_overrides({}, {1: (10, None)})


class RenderTest(unittest.TestCase):
    RECIPES = {
        26745: ("tailoring", 21840, 300, 305, 325, "trainer", None),
        27984: ("enchanting", 0, 375, 385, 415, "drop", 22559),
    }

    def test_round_trip(self):
        text = gen.render("tbc", "2.5.6.1", self.RECIPES)
        build, entries = gen.parse_existing(text)
        self.assertEqual(build, "2.5.6.1")
        self.assertEqual(entries, self.RECIPES)

    def test_client_guard(self):
        self.assertIn("if interface == 16001 then return end", gen.render("tbc", "b", self.RECIPES))
        self.assertIn("if interface ~= 16001 then return end", gen.render("forever", "b", self.RECIPES))

    def test_summary_lists_changes(self):
        new = dict(self.RECIPES)
        new[26745] = ("tailoring", 21840, 300, 305, 330, "trainer", None)
        del new[27984]
        new[2963] = ("tailoring", 2996, 1, 25, 50, "starter", None)
        text = gen.summarize("tbc", "old", "new", self.RECIPES, new, {2963: "Bolt of Linen Cloth"})
        self.assertIn("**1 added**, **1 removed**, **1 changed**", text)
        self.assertIn("- Bolt of Linen Cloth (2963, tailoring)", text)
        self.assertIn("gray: 325 → 330", text)

    def test_summary_at_the_pinned_build_names_it_once(self):
        # server data refreshes regenerate at the pinned build: no build change to show
        text = gen.summarize("tbc", "2.5.6.1", "2.5.6.1", self.RECIPES, self.RECIPES, {})
        self.assertIn("## TBC recipe data: build 2.5.6.1", text)
        self.assertIn("**0 added**, **0 removed**, **0 changed**", text)


if __name__ == "__main__":
    unittest.main()
