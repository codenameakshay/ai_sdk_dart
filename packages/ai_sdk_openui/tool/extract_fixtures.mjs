// Usage: node extract_fixtures.mjs <open-intelligent-ui checkout> <out dir>
// Copies the pure-data fixture modules into a temp dir, rewrites their
// relative imports to .ts, loads them with Node's type stripping, and writes
// JSON fixtures plus the generated system prompts.
import { cpSync, mkdtempSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [repo, out] = process.argv.slice(2);
if (!repo || !out) throw new Error("usage: extract_fixtures.mjs <repo> <out>");

const files = {
  "src/app/gallery/programs.ts": "programs.ts",
  "src/app/gallery/tool-programs.ts": "tool-programs.ts",
  "src/app/gallery/composition-programs.ts": "composition-programs.ts",
  "src/lib/prompt-options.ts": "prompt-options.ts",
  "src/lib/demo-data.ts": "demo-data.ts",
};
const tmp = mkdtempSync(join(tmpdir(), "oiu-fixtures-"));
for (const [src, dst] of Object.entries(files)) {
  const text = readFileSync(join(repo, src), "utf8")
    .replace(/^import type .*$/gm, "")
    .replace(/from "\.\/([\w-]+)"/g, 'from "./$1.ts"');
  writeFileSync(join(tmp, dst), text);
}
const load = (f) => import(pathToFileURL(join(tmp, f)).href);
const { programs } = await load("programs.ts");
const { toolPrograms } = await load("tool-programs.ts");
const { compositionPrograms } = await load("composition-programs.ts");
const po = await load("prompt-options.ts");
const { demoToolSpecs } = await load("demo-data.ts");

mkdirSync(out, { recursive: true });
const write = (name, data) => writeFileSync(join(out, name), JSON.stringify(data, null, 2) + "\n");
write("gallery_programs.json", {
  toolPrograms,
  examples: [
    { id: "example-list", code: po.exampleShoppingList },
    { id: "example-trip", code: po.exampleTrip },
    { id: "example-steps", code: po.exampleSteps },
    { id: "example-dashboard", code: po.exampleDashboard },
  ],
  programs,
  compositionPrograms,
});
write("prompt_options.json", {
  promptOptions: po.promptOptions,
  dashboardPromptOptions: po.dashboardPromptOptions,
  demoToolSpecs,
});
for (const f of ["system-prompt.txt", "dashboard-system-prompt.txt"]) {
  cpSync(join(repo, "src/generated", f), join(out, f));
}
console.log(`programs ${programs.length}, tool ${toolPrograms.length}, composition ${compositionPrograms.length}`);
