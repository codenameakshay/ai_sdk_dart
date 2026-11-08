// The reference's checked-in prompts (src/generated/*system-prompt.txt) predate
// its own source at the pinned commit: spec.json and prompt-options.ts from the
// same commit have newer text. These are the only allowed differences, each
// taken from that newer source. Regenerate with tool/prompt_drift.py.

/// Stale golden line -> the line the current source produces.
const promptLineUpdates = <String, String>{
  'Title(text: string, size?: "sm" | "md" | "lg" | "xl" | "2xl" | "3xl", color?: Color) — Heading; lg for a card title, 2xl for a big number.':
      'Title(text: string, size?: "sm" | "md" | "lg" | "xl" | "2xl" | "3xl", color?: Color) — Heading; md for a card title, lg for a section, 2xl for a big number.',
  'Badge(text: string, color?: "neutral" | "info" | "success" | "warning" | "danger" | "purple" | "pink")':
      'Badge(text: string, color?: "neutral" | "info" | "success" | "warning" | "danger" | "purple" | "pink", icon?: string) — Pill tag; icon is an optional leading lucide name.',
  'days = Col(@Each(plan, "d", Row([Box([SearchImage(d.place, 1, "lg")], null, null, null, null, null, null, 96), Col([Text([Icon("map-pin", "sm"), " Day " + d.day + " · " + d.title], "md", null, "semibold"), Text(d.text, "sm", "muted")], 1)], 4, "start")), 5)':
      'days = Col(@Each(plan, "d", Row([Box([SearchImage(d.place, 1, "lg")], null, null, null, null, null, null, 96), Col([Text([Icon("map-pin", "sm"), " Day " + d.day + " · " + d.title], "md", null, "semibold"), Text(d.text, "sm", "muted")], 1)], 4, "start")), 4)',
  'root = Col([head, kpis, Grid([weekly, byRegion], 2, 280, 4), top], 4)':
      'root = Col([head, kpis, Grid([weekly, byRegion], 2, 280, 4), top])',
};

/// Lines the current source adds, after the golden line they follow.
const promptLineInserts = <(String, List<String>)>[
  (
    '- Compose the answer like a page, not a form letter: a Title, a short Text, then a mix of blocks that show the content. SearchImage for every place, dish, product or thing that has a look (the app finds the photo, so never say you cannot show photos); Row, Grid and Carousel to set things side by side; Badge rows for quick facts; Card only to group a block; Popover for an aside.',
    [
      '- Spacing is a system with three tiers that always nest: inner (gap 1-2, 4-8px) for a title with its subtitle, tags or line; group (gap 3-4, 12-16px) between blocks inside a Card or grid cell; section (24px) between the blocks of the page. Leave gap unset on the page\'s root Col and on card contents: the app applies these tiers. Set a gap only on a Row or Grid. Never use one gap for everything, and never a gap larger than the section gap.',
      '- A photo beside text is a media row: Row([Box([SearchImage(query, 1.33)]), Col([Title(..., "md"), Row([Badge(...), Badge(...)], 1, null, null, true), Text(..., "sm")], 2)], 4, "start"). The app sizes the photo to a third of the row (at most 200px) and top-aligns the text. Facts are Badges, never Buttons or boxed pills.',
      '- Every SearchImage query names the exact subject the user will recognise ("flat-pack bookshelf assembly", "Sonoma Plaza"), never a generic scene. If no photo would show the subject, use no image.',
      '- Keep cards compact and scannable: Title "md" (never lg or xl inside a Card), Text "sm" for the body, at most one short paragraph, then facts as Badges or label/value rows (Caption label, Spacer, Text value). Don\'t write bold-lead paragraphs like "**Weekend rhythm:** ..." or long prose in a card. Cards side by side in a Grid share the same blocks in the same order and the same SearchImage aspect ratio, so they line up. For example: c = Card([SearchImage("Sonoma Plaza", 1.5), Col([Title("Sonoma", "md"), Row([Badge("1 h drive", null, "car"), Badge("Wine country", "purple")], 1, null, null, true)], 2), Text("A slow plaza, tasting rooms and quiet back roads.", "sm"), Col([Row([Caption("Best for"), Spacer(), Text("Food and wine", "sm")]), Row([Caption("Trade-off"), Spacer(), Text("Tastings add up", "sm")])], 1)])',
    ],
  ),
];
