// Usage: node run.mjs <spec.json> <vectors.json> [--write]
// Parses each vector's program with @openuidev/lang-core and compares the result with its "expect"
// (or, with --write, stores it). Exit 1 when any vector differs. Vectors with only "expectReport" test the
// Dart validator (bound records, policy), which lang-core does not have; they are skipped here.
import { readFileSync, writeFileSync } from "node:fs";
import { createParser } from "@openuidev/lang-core";

const [specPath, vectorsPath, flag] = process.argv.slice(2);
if (!specPath || !vectorsPath) throw new Error("usage: run.mjs <spec.json> <vectors.json> [--write]");
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const file = JSON.parse(readFileSync(vectorsPath, "utf8"));
const parser = createParser(spec.schema, spec.root);
const project = (r) => ({
  hasRoot: r.root !== null || r.rootExpression !== undefined,
  ...JSON.parse(JSON.stringify({ meta: r.meta, stateDeclarations: r.stateDeclarations })),
});
const sorted = (v) => Array.isArray(v) ? v.map(sorted)
  : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sorted(v[k])])) : v;
let failed = 0;
const parseVectors = file.vectors.filter((v) => "expect" in v);
for (const v of parseVectors) {
  const got = project(parser.parse(v.program));
  if (flag === "--write") { v.expect = got; continue; }
  if (JSON.stringify(sorted(got)) !== JSON.stringify(sorted(v.expect))) {
    failed++;
    console.error(`FAIL ${v.id}\n  want ${JSON.stringify(v.expect)}\n  got  ${JSON.stringify(got)}`);
  }
}
if (flag === "--write") writeFileSync(vectorsPath, JSON.stringify(file, null, 2) + "\n");
const skipped = file.vectors.length - parseVectors.length;
console.log(`${parseVectors.length - failed}/${parseVectors.length} vectors match lang-core (${skipped} validator-only skipped)`);
process.exit(failed ? 1 : 0);
