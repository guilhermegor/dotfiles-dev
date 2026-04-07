# Python Coding Standards

Shared coding standards for all py-\* skills. Not a skill itself —
read by other skills via the Read tool.

## Linting compliance

**Primary:** Read the project's `ruff.toml` (or `pyproject.toml` `[tool.ruff]` section).
When present, it is the single source of truth for style, import ordering, and lint
rules — do not override or second-guess its settings.

**Fallback** (when no ruff config exists in the project):

- **ruff** with rule sets: `UP`, `E`, `F`, `ANN`, `B`, `SIM`, `I`, `ERA`, `S`, `PD`, `D`
  — covers pyupgrade, pycodestyle, flake8, annotations, bugbear, simplify, isort,
  eradicate, bandit, pandas-vet, and pydocstyle (`convention = "numpy"`).
- **mypy** in strict mode — full static type checking; no implicit `Any` allowed.
  Every variable, parameter, return type, and container element must carry an
  explicit type annotation.
- **vulture** — dead code detection; remove all unused imports, variables,
  functions, and unreachable branches.

## Formatting rules

- **Line length**: 99 characters maximum.
- **Indentation**: Tabs (4 spaces equivalent) — never mix tabs and spaces.
- **Python version**: Read `.python-version` from the project root; fall back to 3.9+
  if the file is absent.
- **Strings**: Double quotes everywhere (code and dict keys); single quotes only inside
  docstring body text.
- **f-strings**: Prefer over `.format()` and `%` formatting.
- **Imports**: isort order — stdlib → third-party → local; one import per line.
- **Long lines**: Break using Python's implied line continuation inside `()`, `[]`, `{}`.
- **Operators**: Consistent spacing around all operators.
- **Variable names**: Use descriptive, intent-revealing names. Rename single-letter
  or ambiguous variables when the meaning is unclear from context, except for
  conventional loop counters (`i`, `j`, `k`) and mathematical notation matching
  the domain.

## Type hints

- Mandatory on every function/method signature (parameters and return type).
- Preserve type information already encoded in variable names.
- `Optional[X]` / `Union[X, Y]` for Python < 3.10; `X | None` / `X | Y` allowed on
  Python 3.10+.
- `Literal["a", "b"]` for variables with a fixed set of allowed values.
- `NDArray[np.float64]` (from `numpy.typing`) instead of `np.ndarray`.
- Return dictionaries typed as `class Return<MethodName>(TypedDict)` with a Numpy-style
  docstring, one blank line between the docstring and the first field.
- Use `Protocol` (from `typing`) to define structural contracts for collaborators and
  injectable dependencies. Prefer `Protocol` over abstract base classes when the
  conforming class should not be forced to inherit. Name protocols after the role they
  fill, not the concrete implementation (e.g. `DataFetcher`, not `HttpClient`):

```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class DataFetcher(Protocol):
    """Contract for objects that fetch raw data from a source.

    Any class implementing 'fetch' with this signature satisfies the protocol
    without explicit inheritance.
    """

    def fetch(self, url: str) -> bytes:
        """Fetch raw bytes from the given URL.

        Parameters
        ----------
        url : str
            Resource location to fetch from

        Returns
        -------
        bytes
            Raw response body
        """
        ...
```

```python
class ReturnProcessData(TypedDict):
    """Return type for process_data.

    Attributes
    ----------
    value : Optional[float]
        Computed result
    valid : bool
        Whether the computation succeeded
    """

    value: Optional[float]
    valid: bool
```

## Docstrings

- **Style**: Numpy, 79-character line limit inside docstring body.
- **First line**: Imperative mood, ends with a period, on the same line as the opening `"""`.
- **Sections**: `Parameters`, `Returns`, `Raises`, `Notes`, `References` — include only
  sections that apply.
- **Quotes inside docstrings**: Single quotes (`'`) only — never double quotes.
- **References**: Preserve exactly as provided; allow URL line breaks when necessary.
- **Examples**: Preserve all existing docstring examples and doctests exactly as
  written; do not rewrite, reorder, or remove them.
- **Module docstring**: Every module must begin with a two-paragraph docstring —
  first paragraph: one-sentence summary; second paragraph: what the module provides.

```python
"""HTML data extraction utilities using lxml and requests.

This module provides a class for fetching and parsing HTML content from URLs
using lxml for XPath-based data extraction and requests for HTTP operations.
"""
```

## Validation methods

- Extract reusable guard logic into `_validate_<name>(self, ...)` methods.
- Place all `_validate_*` methods at the **top** of the class, before other methods.
- Each validation method raises a descriptive exception with the variable name and
  the violated constraint in the message.
- Document every `Raises` case in the method's docstring.

```python
def _validate_url(self, url: str) -> None:
    """Validate URL format and content.

    Parameters
    ----------
    url : str
        URL to validate

    Raises
    ------
    ValueError
        If URL is empty
        If URL is not a string
        If URL does not start with 'http://' or 'https://'
    """
    if not url:
        raise ValueError("URL cannot be empty")
    if not isinstance(url, str):
        raise ValueError("URL must be a string")
    if not (url.startswith("http://") or url.startswith("https://")):
        raise ValueError("URL must start with 'http://' or 'https://'")
```

## Exception handling

Always use `as err` and re-raise with `from err` to satisfy Ruff B904:

```python
try:
    result = risky_operation()
except Exception as err:
    raise ValueError(f"Operation failed: {err}") from err
```

Document every raised exception in the `Raises` section of the docstring.

## Sanity checks

Add guard clauses at the top of functions/methods for the categories below.
Use `_validate_*` helpers when the same check appears in multiple methods.

### 0–1 range (probabilities, p-values, correlations, confidence levels,
### normalised values, activation outputs, rates/percentages)
```python
if not 0.0 <= value <= 1.0:
    raise ValueError(f"'value' must be in [0, 1], got {value}")
```

### Positive numbers (counts, degrees of freedom, sample sizes, shape parameters,
### physical measurements, time values)
```python
if value <= 0:
    raise ValueError(f"'value' must be positive, got {value}")
```

### Negative numbers (negative coefficients, log of values in (0,1), eigenvalues,
### financial losses)
```python
if value >= 0:
    raise ValueError(f"'value' must be negative, got {value}")
```

### Arrays
```python
if len(array) == 0:
    raise ValueError("'array' must not be empty")
if array.shape != expected_shape:
    raise ValueError(f"'array' must have shape {expected_shape}, got {array.shape}")
if not np.all(np.isfinite(array)):
    raise ValueError("'array' contains NaN or infinite values")
if not np.issubdtype(array.dtype, np.number):
    raise ValueError("'array' must contain numeric values")
```

## Package preference

- Prefer packages already used in the project over introducing new ones.
- New third-party packages must score 80+ on the Snyk Advisor.
- `stpstone` is exempt from the Snyk score restriction.

## Reference implementation

```python
"""Data processing utilities for numerical arrays.

This module provides functions for validating and processing numerical data using NumPy.
It includes input validation and statistical computations with a focus on robust error
handling.
"""

from typing import Optional, Literal, TypedDict

import numpy as np
from numpy.typing import NDArray


class ReturnProcessData(TypedDict):
    """Return type for process_data.

    Attributes
    ----------
    value : Optional[float]
        Computed statistical result
    valid : bool
        Whether the computation succeeded
    """

    value: Optional[float]
    valid: bool


def validate_input(value: float, name: str) -> None:
    """Validate that a value is between 0 and 1.

    Parameters
    ----------
    value : float
        Value to validate
    name : str
        Variable name for error messages

    Raises
    ------
    ValueError
        If value is outside [0, 1] range
    """
    if not 0.0 <= value <= 1.0:
        raise ValueError(f"'{name}' must be between 0 and 1, got {value}")


def process_data(
    data: NDArray[np.float64],
    method: Literal["mean", "median"] = "mean",
) -> ReturnProcessData:
    """Process numerical data using the specified method.

    Parameters
    ----------
    data : NDArray[np.float64]
        Input data array (must not be empty)
    method : Literal['mean', 'median']
        Processing method (default: 'mean')

    Returns
    -------
    ReturnProcessData
        Dictionary containing the computed result and validity flag

    Raises
    ------
    ValueError
        If 'data' is empty
        If 'data' contains NaN or infinite values

    References
    ----------
    .. [1] https://numpy.org/doc/stable/reference/generated/numpy.mean.html
    .. [2] https://numpy.org/doc/stable/reference/generated/numpy.median.html
    """
    if len(data) == 0:
        raise ValueError("'data' must not be empty")
    if not np.all(np.isfinite(data)):
        raise ValueError("'data' contains NaN or infinite values")
    return ReturnProcessData(
        value=float(np.mean(data)) if method == "mean" else float(np.median(data)),
        valid=True,
    )
```
