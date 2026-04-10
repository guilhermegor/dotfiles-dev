---
name: s:py-perf
description: Review Python code for performance issues and optimization opportunities. Trigger when asked to check performance, optimize, or find bottlenecks in Python code.
effort: high
argument-hint: [source-file-or-directory]
allowed-tools: Read Glob Grep
---

Review the provided Python source code for performance issues and optimisation
opportunities. Report findings as a structured list with current pattern vs
suggested pattern — do not modify any files.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source** — path to a `.py` file or a package directory.

Do not infer the path. Wait for explicit confirmation before reading files.

If a directory is provided, walk it recursively and review all `.py` files.
Skip test files unless explicitly asked.

## Performance categories

### I/O patterns
- Synchronous I/O where `async` is available and the framework supports it.
- Blocking calls inside an async event loop (`requests` in `asyncio` code).
- N+1 query patterns (database call inside a loop).
- Missing connection pooling or session reuse (creating new HTTP sessions per request).
- Unbuffered file reads/writes.

### Memory
- Unnecessary copies (`list(generator)` when iteration suffices).
- Large list comprehensions that could be generators.
- Missing `__slots__` on data-heavy classes with many instances.
- Accumulating data in memory instead of streaming/chunking.
- Holding references to large objects longer than needed.

### Algorithmic complexity
- O(n^2) patterns where O(n) or O(n log n) is possible (nested loops over same data).
- Repeated linear lookups where a `dict` or `set` would give O(1).
- Sorting when only min/max is needed (`sorted(data)[0]` vs `min(data)`).
- Recomputing values inside loops that could be computed once outside.

### Data structures
- `list` used for membership tests where `set` or `frozenset` is appropriate.
- Repeated string concatenation in a loop instead of `"".join()` or `io.StringIO`.
- `dict` where `collections.defaultdict` or `collections.Counter` simplifies logic.
- Nested dicts where a dataclass or NamedTuple would be clearer and faster.

### Import overhead
- Heavy imports at module level that are only used in rare code paths.
- Lazy import opportunities for optional or expensive dependencies.

### Caching
- Repeated expensive computation with the same arguments (missing `functools.lru_cache`
  or `functools.cache`).
- Missing memoisation for recursive functions.
- Redundant database/API calls for the same data within a request lifecycle.

### Pandas and NumPy specific
- `iterrows()` or `itertuples()` where vectorised operations are possible.
- `DataFrame.apply()` with a simple function that has a vectorised equivalent.
- Creating intermediate DataFrames where chaining would avoid copies.
- `np.append()` in a loop instead of pre-allocating and filling.
- Using Python loops over NumPy arrays instead of broadcasting.
- `copy()` where a view suffices (and vice versa when mutation safety is needed).

### Serialisation
- `json.dumps()` / `json.loads()` inside tight loops instead of batch processing.
- Repeated parsing of the same data structure.
- Using `json` where `orjson` or `msgpack` would significantly improve throughput.

## Impact levels

- **Critical** — orders-of-magnitude improvement possible; likely causes timeouts
  or OOM in production.
- **High** — significant measurable improvement (2x-10x); affects user-facing latency.
- **Medium** — noticeable improvement; good engineering practice.
- **Low** — micro-optimisation; only matters in hot paths.

## Output format

```
## Performance Review: <filename or package>

### Critical (<count>)
- `file.py:42` — N+1 query pattern: database call inside loop.
  **Current:** `for item in items: db.query(item.id)`
  **Suggested:** Batch query with `db.query(Item).filter(Item.id.in_(ids))`

### High (<count>)
- `file.py:87` — List used for membership test in hot path.
  **Current:** `if value in large_list:`
  **Suggested:** `if value in large_set:`

### Medium (<count>)
...

### Summary
<1-2 sentence overall performance assessment>
<Top recommendation for highest-impact improvement>
```

## Do Not

- Do not modify any files — this is a read-only review.
- Do not run any commands or benchmarks.
- Do not recommend micro-optimisations (e.g., local variable caching) unless the code
  is in a proven hot path.
- Do not suggest switching languages or frameworks.
- Do not report more than 20 findings — prioritise by impact.
