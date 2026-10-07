from altarmy_site import reputation

VANILLA = {6: 10, 7: 10, 8: 10}


def test_only_the_city_factions_at_a_real_standing_are_kept() -> None:
    pairs = [(76, 6), (909, 8), (72, 0), (68, 9), (530, 5), (47, 4)]  # Darkmoon Faire, and two bad standings
    assert reputation.city_standings(pairs) == ((47, 4), (76, 6), (530, 5))


def test_a_faction_given_twice_keeps_its_last_standing() -> None:
    assert reputation.city_standings([(76, 5), (76, 7)]) == ((76, 7),)


def test_vendor_discounts_follow_the_versions_schedule() -> None:
    standings = ((81, 8), (76, 6), (68, 5), (530, 4))
    assert reputation.vendor_discounts(standings, VANILLA) == ((76, 10), (81, 10))
    graded = {5: 5, 6: 10, 7: 15, 8: 20}
    assert reputation.vendor_discounts(standings, graded) == ((68, 5), (76, 10), (81, 20))
    assert reputation.vendor_discounts(standings, {}) == ()
