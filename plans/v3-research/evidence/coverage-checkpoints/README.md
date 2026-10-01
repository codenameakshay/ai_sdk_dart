# Coverage checkpoints

These isolated measurements use Flutter3.44.3/Dart3.12.2. Source paths are normalized to repository-relative paths. They do not replace the required final `make coverage-check` run.

| Package | Hit / executable lines | Coverage | Behavioral additions |
|---|---:|---:|---|
| Provider | 278/278 | 100% | Abort observation races, Dio scope disposal, canonical variants and capability values |
| Core | 2945/3048 | 96.62% | Object body policy, validator errors, approval defaults and provider-message conversion |
| Telemetry | 206/222 | 92.79% | Bounds, caller-owned clients, in-flight capacity, disposal and nested attributes |
| JSON Schema | 53/53 | 100% | Invalid limits and nonfinite data before decoder execution |

Parent independently ran the core/provider suites:781passed. Parent telemetry/schema suites:48passed. Measurements and parent tests are separate evidence; the parent did not rerun each isolated LCOV formatter. No coverage exclusions or threshold reductions were added. Core and telemetry still have uncovered branches; these remain incomplete against the aggregate99%gate.
