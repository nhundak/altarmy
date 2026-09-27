import { z } from "zod";

/** What the user wants from the search; it sets how results are ranked and presets some filters. */
export type Goal = "profit" | "budget" | "skill";

export const goalSchema = z.enum(["profit", "budget", "skill"]);

export const GOALS: readonly {
  key: Goal;
  title: string;
  blurb: string;
  details: string;
}[] = [
  {
    key: "profit",
    title: "Maximize profit",
    blurb: "The most gold for each hour of play, whatever the up front costs.",
    details:
      "Emphasis is placed on minimizing time wasted traveling and switching characters. Selling through the auction house is preferred, but be wary of items that look profitable, yet no one's buying.",
  },
  {
    key: "budget",
    title: "Make profit on a budget",
    blurb: "Reliable profit from every single craft, even if it takes longer.",
    details:
      "If you can save a few copper by crafting intermediate materials yourself, you'll do so. Selling reliable enchanting materials will be preferred, rather than intact items that might not sell.",
  },
  {
    key: "skill",
    title: "Skill up for minimum expense",
    blurb:
      "Focus on gaining skill points, with minimizing cost being more important than profit.",
    details:
      "Recipes that cannot grant skill are ignored. Recipes that make profit are nice, but assuming that's not possible, you'll focus on recipes with a high chance of skill up relative to the costs.",
  },
];

/**
 * What a goal does to the search: the order the server ranks in, and the filters written when it is picked (the user
 * can change those afterwards). `minProfit` is in gold, as the filter is typed; 0.0001 is one copper, so only
 * profitable recipes. Budget and skill up will also weigh selling on the auction house down, once the ranking can.
 */
export const GOAL_SEARCH: Readonly<
  Record<
    Goal,
    {
      sort: "profit" | "rate";
      includeTrivial: boolean;
      minProfit: number | null;
    }
  >
> = {
  profit: { sort: "rate", includeTrivial: true, minProfit: 0.0001 },
  budget: { sort: "profit", includeTrivial: true, minProfit: 0.0001 },
  skill: { sort: "profit", includeTrivial: false, minProfit: null },
};
