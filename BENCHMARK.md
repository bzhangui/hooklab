# Benchmarks

Benchmarks are evidence for regression detection, not a claim about production
HTTP throughput.

## Route evaluation

The bundled benchmark parses a representative nested JSON event and evaluates
three routing rules, including an array path.

~~~bash
moon bench --target native --release -p hooklab/hooklab/hooklab/engine
~~~

Local reference run on 14 September 2026:

| Environment | Mean | Range |
|---|---:|---:|
| AMD Ryzen 7 8845H, MoonBit 0.1.20260703, native release | 3.37 µs | 3.33–3.40 µs |

The exact value depends on hardware and toolchain version. Future optimization
changes should compare on the same machine and retain matching routing tests.
