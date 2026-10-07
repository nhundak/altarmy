import { IconDownload } from "./icons";
import type { CardSpec } from "./StartCard";

/** The Auto-upload card, the same on the Profit page's start cards and beside the Realm card's upload. */
export const AUTO_IMPORT_CARD: CardSpec<"auto"> = {
  key: "auto",
  title: "Auto-upload",
  blurb:
    "A small app on your gaming PC uploads your characters and auction scans whenever WoW saves them. Nothing to paste, and prices stay fresh.",
  short: "Set up Alt Army Sync.",
  icon: <IconDownload />,
};
