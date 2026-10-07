import pytest

from altarmy_site import talents
from altarmy_site.talents import BARTERING, MASTER_CHEF, WORKING_OVERTIME


def test_master_chef_gives_cooking_a_chance_of_an_extra_result_per_rank() -> None:
    ((profession, chance),) = talents.extra_results(((MASTER_CHEF, 3),))
    assert profession == "Cooking"
    assert chance == pytest.approx(0.3)
    assert talents.extra_results(()) == ()


def test_bartering_takes_five_percent_per_rank_off_vendor_prices() -> None:
    assert talents.vendor_discount(((BARTERING, 1),)) == 5
    assert talents.vendor_discount(((BARTERING, 2), (MASTER_CHEF, 5))) == 10
    assert talents.vendor_discount(()) == 0


def test_working_overtime_adds_four_percent_per_rank_to_the_skill_up_chance() -> None:
    assert talents.skill_bonus(((WORKING_OVERTIME, 3),)) == pytest.approx(0.12)
    assert talents.skill_bonus(((WORKING_OVERTIME, 9), (BARTERING, 2))) == pytest.approx(0.2)  # 5 ranks
    assert talents.skill_bonus(()) == 0.0


def test_ranks_are_capped_at_the_talents_max_rank() -> None:
    assert talents.vendor_discount(((BARTERING, 9),)) == 10
    ((_, chance),) = talents.extra_results(((MASTER_CHEF, 9),))
    assert chance == pytest.approx(0.5)


def test_other_talents_change_nothing() -> None:
    other = ((1225478, 5),)  # Well Rested
    assert talents.extra_results(other) == ()
    assert talents.vendor_discount(other) == 0
    assert talents.skill_bonus(other) == 0.0


def test_known_lists_only_registered_talents_with_their_max_rank() -> None:
    got = talents.known(((1225478, 5), (MASTER_CHEF, 9), (BARTERING, 1)))
    assert [(t.name, rank, t.max_rank) for t, rank in got] == [("Master Chef", 5, 5), ("Bartering", 1, 2)]
