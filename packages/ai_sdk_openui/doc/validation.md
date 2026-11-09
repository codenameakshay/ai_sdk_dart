# Validating programs outside Dart

A server can check every OpenUI program before it forwards it to a client, in any language. It needs
three things from this package: the library as a JSON spec, the report format below, and the
conformance vectors that prove its validator gives the same reports as the Dart one.

## 1. Export the spec

```sh
dart run ai_sdk_openui:openui spec intelligent-ui > spec.json   # the built-in library
dart run ai_sdk_openui:openui spec spec.json > spec.json.new     # canonicalise an existing file
```

`openui spec` prints canonical JSON: object keys sorted, arrays in their own order, two-space indents
and a final newline. The members of a JSON Schema `properties` object are the one exception: they keep
their order, because that order is the positional order of a component's or call's arguments. The same
library always gives the same bytes, so a regenerated `spec.json` diffs only when the library changes.

A library with host components cannot be loaded by the CLI. Print its spec from a one-file script; the
bytes are the same as `openui spec` would print:

```dart
import 'dart:io';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:my_app/ui_library.dart'; // your OpenUiLibrary

void main() => stdout.write(canonicalJson(myLibrary.toSpec()));
```

What a validator reads from the spec:

- `root`: the root component name.
- `schema.$defs.<Component>`: the component's params. `properties` in order are the positional
  arguments; `required` lists the required ones.
- `"x-openui-bound": true` on a schema: a bound-only value (see below). It can sit on a param or on any
  object field or list item inside one.
- `schema.actions.<Name>.params` and `schema.functions.<Name>.params`: library `@Action` and
  `@Function` params, in the same form.
- Restricted action slots (section 4): a param whose schema is a step shape, or a union of
  step shapes, takes only those steps.
- `policy` (optional): the caps below. Policy flags on `openui spec` write it
  (`--max-nodes=24 --max-depth=8 --max-string=280 --unknown=fail --allow-actions=ToAssistant,Pay`).
  `openui validate` applies a spec's `policy`, with its own flags taking precedence key by key.

## 2. The policy

`ValidationPolicy.toJson()` and `ValidationPolicy.fromJson()` use this form. Every key is optional.

| Key | Value | Issue when exceeded |
| --- | --- | --- |
| `maxNodes` | integer | `too-many-nodes` |
| `maxDepth` | integer, the root is depth 1 | `too-deep` |
| `maxStringLength` | integer, in UTF-16 code units | `string-too-long` |
| `unknownComponents` | `"drop"` (default) or `"fail"` | `unknown-component` is a warning or an error |
| `allowedActions` | names of built-in steps and library actions | `action-not-allowed` |

## 3. Bound-only values

A program reads host data through bound records (`BoundRecord('order', json)` is `$order`). A value
marked bound-only takes only a path into a bound record: `$order.total`, `$order.items[0]`, an alias
statement that is such a path, or an `@Each` item over one. An index in a path must be a literal or a
bound path itself. Anything else is a `bound-only` error: a literal, arithmetic, a ternary, a function
call, a computed index such as `$order[$k]` (it lets the program pick the field), a `$variable` the
program declares, or an `@Each` item over a literal list. A program cannot shadow a record: when `$order` is bound, a program
declaration of `$order` is ignored.

Inside an object or list written out in the program, each bound-only field or item is checked on its
own and reported at its own path (`/payment/amount`, `/ids/0`). A container that holds bound-only
parts must be written out, be null, or be a bound path itself. A computed container (state, a
ternary, a call) is a `bound-only` error at the container's path, because its fields cannot be checked.

For `anyOf` and `oneOf`, bound-only constraints apply to every alternative compatible with the
literal's JSON type. An alternative of another type does not constrain that literal. When alternatives
overlap, their bound-only constraints all apply; an unrestricted alternative cannot erase one. A
computed value has no known literal type, so every alternative is checked. Null remains allowed here;
required/null validation is separate.

### Record schemas

A validator can also know the shape of each record: a JSON Schema per `$name`
(`library.validate(program, boundSchemas: {r'$order': schema})`, `openui validate --bound-schemas=<file>`
with a JSON object of the same form). A name with a schema counts as bound. Then every bound path that is
the value of a component prop or a library function or action param, or of an object field or list item
written out inside one, bound-only or not, is checked (built-in `@` functions are not):

- It must exist in the schema, or it is an `unknown-bound-path` error. A field exists when `properties`
  lists it or `additionalProperties` is a schema or `true`; an array has numeric indexes and `length`; a
  string has `length`. A bound index (`$order.items[$order.pick]`) matches any item or field.
  An `@Each` item reads the schema of the source's `items`.
- Its JSON type (`integer` counts as `number`; `anyOf`/`oneOf` join their options) must share a type with
  the prop's schema, or it is a `type-mismatch` error. A schema without `type` matches anything.

A record without a schema is not checked beyond section 3.

## 4. Action slots

A step shape is an object schema whose `type` property is a `const`. `Steps` and `S.actionRef` emit one
into `$defs` for each step a slot lists. The const names the step:

| `type` const | Step |
| --- | --- |
| `continue_conversation` | `@ToAssistant` |
| `open_url` | `@OpenUrl` |
| `set` | `@Set` |
| `reset` | `@Reset` |
| any other value | the library action of that name, such as `@Copy` |

A param whose schema is a step shape, or a union of step shapes (a `{"type": "null"}` option is
ignored), is a restricted slot. Each step given to it must be one it lists: the step itself, every step
in `Action([...])`, and the steps of both branches of a ternary. Otherwise it is a `type-mismatch` error at
the param's path, and the prop is dropped. The generic `ActionExpression` slot (`actionSchema`) takes any
step.

## 5. The report

`ValidationReport.toJson()`, which `openui validate` prints:

```json
{
  "ok": false,
  "issues": [
    {
      "code": "bound-only",
      "severity": "error",
      "message": "field \"/amount\" accepts only a path into a host-bound $variable, such as $order.total",
      "statementId": "root",
      "component": "Out",
      "path": "/amount"
    }
  ],
  "stats": {"nodes": 1, "depth": 1, "statements": 1}
}
```

This is a stable contract: codes, field names, severity values and path syntax change only in a major
version. A minor version can add codes; treat an unknown code with `"severity": "error"` as an error.

- `ok` is true when the program has a root and no issue has severity `error`.
- `severity` is `"error"` or `"warning"`.
- `message` is for people. It is not part of the contract and the vectors do not state it.
- `statementId` is the statement the issue is in, when there is one.
- `component` is the component or call the issue is about. For `action-not-allowed` it is the
  component whose prop holds the action.
- `path` is omitted when empty. It starts at the statement: `/<param>` and then `/<field>` or
  `/<index>` for each step into an object or list. A component written as its own statement starts a
  new path, and its `statementId` names that statement.
- `stats.nodes` counts components, `stats.depth` is the deepest nesting (the root is 1) and
  `stats.statements` counts statements.

| Code | Severity | Meaning |
| --- | --- | --- |
| `missing-required` | error | a required param is missing |
| `null-required` | error | a required param is null |
| `type-mismatch` | error | a value does not match its param's schema, a bound value's type does not fit (section 3), or a step is outside its action slot (section 4) |
| `excess-args` | error | more arguments than params; the extra ones are dropped |
| `unknown-component` | warning with `drop`, error with `fail` | the library has no such component |
| `unknown-function` | error | an `@Name` that is no built-in, function or action |
| `inline-reserved` | error | `Query` or `Mutation` used inline instead of as a statement |
| `no-root` | error, or warning when another statement calls the root component | no usable root |
| `bound-only` | error | a bound-only value is not a bound path (section 3) |
| `unknown-bound-path` | error | a bound path the record's schema does not have (section 3) |
| `incomplete` | error | the program ends inside an unfinished statement |
| `unresolved` | warning | a reference is never defined |
| `orphaned` | warning | a statement is not reachable from the root |
| `too-many-nodes` | error | over `maxNodes` |
| `too-deep` | error | over `maxDepth`; reported once |
| `string-too-long` | error | over `maxStringLength` |
| `action-not-allowed` | error | a step or action outside `allowedActions` |

## 6. Conformance vectors

`conformance/vectors.json` holds two kinds of vectors:

- Parse vectors have `expect`: the parse result `@openuidev/lang-core` gives the program against the
  spec named by the top-level `spec`. `make test-openui-conformance` checks them against lang-core.
- Validator vectors have `expectReport`. They run against the spec named by the top-level
  `validatorSpec` (`conformance/validator-spec.json`), with these optional inputs:
  - `bound`: the bound record names, with the `$`.
  - `boundSchemas`: a JSON Schema per bound record name; these names count as bound too.
  - `policy`: the policy, in the form of section 2.

  `expectReport` is the full report of section 5 without the `message` fields. The lang-core runner
  skips these vectors.

A validator passes when, for every validator vector, it gives exactly `expectReport`, issues in the
same order. The Dart tests (`test/validator_vectors_test.dart`) run every vector through
`validateProgram`, so the vectors cannot drift from the Dart validator, and they check that
`validator-spec.json` is the canonical spec of its library.
