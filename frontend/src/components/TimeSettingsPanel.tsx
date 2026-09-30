import {
  Alert,
  Button,
  Group,
  Loader,
  NumberInput,
  Select,
  SimpleGrid,
  Stack,
  Text,
} from "@mantine/core";
import type { TimeConfig, TimeSettings } from "../api/client";
import { useEditTime, useTime } from "../api/queries";

type NumberKey = {
  [K in keyof TimeConfig]: TimeConfig[K] extends number ? K : never;
}[keyof TimeConfig];

/** The seconds each action takes, as the "Seconds per action" grid lists them. */
const ACTIONS: readonly {
  key: NumberKey;
  label: string;
  step: number;
  min?: number;
  whole?: boolean;
}[] = [
  { key: "ah_search", label: "Search the AH (per item)", step: 1 },
  { key: "ah_buy", label: "Buy on the AH (per stack)", step: 0.5 },
  { key: "ah_post", label: "Post on the AH (per stack)", step: 0.5 },
  { key: "vendor_buy", label: "Buy from a vendor (per stack)", step: 0.5 },
  { key: "vendor_sell", label: "Sell to a vendor (per stack)", step: 0.5 },
  { key: "mail_send", label: "Send a mail", step: 1 },
  { key: "mail_attach", label: "Attach a stack", step: 0.5 },
  { key: "mail_open", label: "Open a mail", step: 0.5 },
  { key: "switch_character", label: "Switch characters", step: 5 },
  { key: "craft_overhead", label: "Extra per craft", step: 0.1 },
  {
    key: "run_speed",
    label: "Run speed (yards per second)",
    step: 0.5,
    min: 0.5,
  },
];

function cityOptions(settings: TimeSettings) {
  return [
    { value: "", label: "Wherever pays best" },
    ...settings.cities.map((c) => ({ value: c.name, label: c.name })),
  ];
}

/**
 * Crafts per session: one of the search's options, outside the Time assumptions panel, saved like the rest of the time
 * settings.
 */
export function CraftsPerSession() {
  const time = useTime();
  const { edit } = useEditTime();
  if (!time.data) return time.isError ? null : <Loader size="sm" />;
  const settings = time.data;
  return (
    <NumberInput
      label="Crafts per session"
      description="More crafts at once need more gold up front and bag space, but less running around per craft."
      value={settings.config.batch}
      onChange={(v) => {
        if (typeof v === "number" && v >= 1)
          edit({ city: settings.city, config: { ...settings.config, batch: Math.round(v) } });
      }}
      min={1}
      step={5}
      allowDecimal={false}
    />
  );
}

/** Where plans are timed and how long each action takes; saved on the server a moment after each change. */
export function TimeSettingsPanel() {
  const time = useTime();
  const { edit, saving } = useEditTime();
  if (time.isPending) return <Loader size="sm" />;
  if (time.isError) return <Alert color="red">{time.error.message}</Alert>;
  const settings = time.data;
  const set = (
    key: NumberKey,
    value: number | string,
    min = 0,
    whole = false,
  ) => {
    if (typeof value !== "number" || value < min) return; // an empty or out-of-range field keeps the old value
    edit({
      city: settings.city,
      config: { ...settings.config, [key]: whole ? Math.round(value) : value },
    });
  };
  const atDefaults =
    settings.city === null &&
    Object.entries(settings.config).every(
      ([key, value]) => value === settings.defaults[key as keyof TimeConfig],
    );
  return (
    <Stack>
      {settings.cities.length ? (
        <Select
          label="Craft Location"
          description="Some cities have shorter runs between mailboxes, vendors, etc, and vendors charge less where your reputation is good"
          data={cityOptions(settings)}
          value={settings.city ?? ""}
          onChange={(v) => edit({ city: v || null, config: settings.config })}
          allowDeselect={false}
          maw={420}
        />
      ) : (
        <Text size="sm" c="dimmed">
          No city maps for this game yet: times count casts, clicks and
          switching characters, not running.
        </Text>
      )}
      <Text size="sm" fw={500}>
        Seconds per action
      </Text>
      <SimpleGrid cols={{ base: 1, xs: 2 }}>
        {ACTIONS.map(({ key, label, step, min = 0, whole = false }) => (
          <NumberInput
            key={key}
            label={label}
            value={settings.config[key]}
            onChange={(v) => set(key, v, min, whole)}
            min={min}
            step={step}
            decimalScale={whole ? 0 : 2}
            allowDecimal={!whole}
          />
        ))}
      </SimpleGrid>
      <Group>
        <Button
          variant="light"
          size="xs"
          onClick={() => edit({ city: null, config: settings.defaults })}
          disabled={atDefaults}
        >
          Reset to defaults
        </Button>
        {saving && <Loader size="xs" aria-label="Saving" />}
      </Group>
    </Stack>
  );
}
