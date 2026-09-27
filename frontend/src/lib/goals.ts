import { z } from "zod";

/** What the user wants from the search; it sets how results are ranked and presets some filters. */
export type Goal = "profit" | "budget" | "skill";

export const goalSchema = z.enum(["profit", "budget", "skill"]);

export const GOALS: readonly {
  key: Goal;
  title: string;
  blurb: string;
  details: string;
  /** Said after `details`, highlighted, and followed by `points` as a list. */
  caution?: string;
  points?: readonly string[];
}[] = [
  {
    key: "profit",
    title: "Maximize profit",
    blurb: "The most gold for each hour of play, whatever the up front costs.",
    details:
      "Emphasis is placed on minimizing time wasted travelling and switching characters. We'll show you the theoretical profits from selling on the auction house,",
    caution: "but you must take an active role in:",
    points: [
      "Evaluating which items you think are likely to sell",
      "Taking care not to flood the market",
    ],
  },
  {
    key: "budget",
    title: "Make profit on a budget",
    blurb: "Reliable profit from every single craft, even if it takes longer.",
    details:
      "If you can save a few copper by crafting intermediate materials yourself, we'll point it out. We'll usually only recommend selling enchanting materials and other well known trade goods. These tend to have smaller margins, but are more predictable than selling intact items which can be hit or miss.",
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
