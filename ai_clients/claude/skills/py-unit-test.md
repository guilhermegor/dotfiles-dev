---
name: py-unit-test
description: Generate comprehensive pytest unit tests for a target Python module. Trigger when asked to write, generate, or create unit tests for a Python file.
---

Generate comprehensive unit tests for the provided Python module using pytest.

## Required inputs

Before doing anything else, ask the user for both of the following if they have not
already been provided in `$ARGUMENTS`:

1. **Source file** — the path to the Python module to be tested.
2. **Output file** — the exact path where the generated test file should be written.

Do not infer or auto-derive either path. Wait for explicit confirmation of both before
reading the source file or writing any code.

## Prerequisites

Before generating tests, check the project's dependency file (`pyproject.toml`,
`requirements*.txt`, or `setup.cfg`) for the following:

- **pytest** — required; abort and notify user if absent
- **pytest-mock** — required for `mocker: MockerFixture`; if absent, fall back to
  `unittest.mock.patch` and `unittest.mock.MagicMock` only
- **pytest-asyncio** — required for `@pytest.mark.asyncio`; skip async test patterns
  if absent
- **numpy** — required for `NDArray` type hints; skip numpy-specific patterns if absent

State which dependencies were detected at the top of the generated test file as a comment:

```python
# Dependencies detected: pytest, pytest-mock, numpy
```

## Coding standards

Before writing any code, read the shared standards document:

    Read ~/.claude/skills/py-standards.md

Apply every rule in that document to the test code you produce. The sections
below are additional standards specific to test files.

## Test structure

Every test file must follow this skeleton exactly — the module docstring, section
banners, and ordering are **mandatory**:

```python
"""Unit tests for <ClassName / module name>.

Tests <brief description of what is covered>:
- <scenario 1>
- <scenario 2>
"""

import pytest

# imports specific to the module under test …


# --------------------------
# Fixtures
# --------------------------

@pytest.fixture
def my_fixture() -> MyClass:
    """Fixture providing …"""
    return MyClass(...)


# --------------------------
# Tests
# --------------------------

def test_something() -> None:
    """Test that …"""
    ...
```

## Do Not

- **Do not test private methods directly** (`_method`, `__method`). Test them
  through the public API that calls them. If a private method is only reachable
  via a public one, cover it by exercising the public method.
- **Do not use `@pytest.mark.skip` or `@pytest.mark.xfail`** unless the source
  module itself is known-broken. Never generate skipped tests as coverage placeholders.
- **Do not assert on log output** unless the function's documented contract guarantees
  specific log messages. Use `caplog` only when log content is a tested behaviour.
- **Do not use `time.sleep` in tests.** Mock `time.sleep`, `datetime.now()`, and
  `time.time()` unconditionally.
- **Do not import from `typing` when primitives suffice.** `list[str]` not `List[str]`.
- **Do not leave unused imports.** Every import must be referenced (Ruff F401).

## Test Quality Standards
- **100% coverage**: Line, branch, and function coverage of the target module.
  Every `if`/`else`, every `try`/`except`, every early `return` must be exercised.
  Run with: `pytest --cov=<module> --cov-branch --cov-report=term-missing`
- **Zero Ruff violations**: Code must pass all Ruff checks without warnings
- **Fallback testing**: Include tests for fallback mechanisms and error recovery
- **Reload logic**: Test module reloading scenarios when applicable
- **Non Optional variables**: check if, for variables that haven not the Optional[...] type, a TypeError is raised, due to TypeChecker metaclass usage / type_checker decorator, with a text that matches with "must be of type"
```python
"""Example of unit test for empty variable, inappropriately declared."""

"""Example of unit tests for variable validation functions."""

from typing import Optional
import pytest


def _validate_non_empty_string(data: Optional[str], param_name: str) -> None:
    """Validate that the provided data is a non-empty string.

    Parameters
    ----------
    data : Optional[str]
        The input data to validate. Can be None or string.
    param_name : str
        The name of the parameter being validated.

    Raises
    ------
    TypeError
        If `data` is not a string, is None, or is empty/whitespace-only.
    """
    if type(data) is not str or data is None or len(data.strip()) == 0:
        raise TypeError(f"{param_name} must be of type str")


def _validate_non_zero_float(data: Optional[float], param_name: str) -> None:
    """Validate that the provided data is a non-zero float.

    Parameters
    ----------
    data : Optional[float]
        The input data to validate. Can be None or float.
    param_name : str
        The name of the parameter being validated.

    Raises
    ------
    TypeError
        If `data` is not a float, is None, or equals zero.
    """
    if type(data) is not float or data is None or data == 0.0:
        raise TypeError(f"{param_name} must be of type float")


@pytest.mark.parametrize("data", [None, "", "  "])
def test_validate_non_empty_string_invalid_data(data: Optional[str]) -> None:
    """Test that invalid string inputs raise an exception.

    Parameters
    ----------
    data : Optional[str]
        Invalid values such as None, empty, or whitespace-only strings.

    Returns
    -------
    None
    """
    with pytest.raises(ValueError, match="must be of type"):
        _validate_non_empty_string(data, "input_string")


@pytest.mark.parametrize("param_name", ["input_string", "test_string", "data_string"])
def test_validate_non_empty_string_invalid_param_name(param_name: str) -> None:
    """Test that invalid param_name handling raises an exception.

    Parameters
    ----------
    param_name : str
        Various parameter names tested against invalid input.

    Returns
    -------
    None
    """
    with pytest.raises(ValueError, match="must be of type"):
        _validate_non_empty_string(None, param_name)


@pytest.mark.parametrize("data", [None, 0.0])
def test_validate_non_zero_float_invalid_data(data: Optional[float]) -> None:
    """Test that invalid float inputs raise an exception.

    Parameters
    ----------
    data : Optional[float]
        Invalid values such as None or zero.

    Returns
    -------
    None
    """
    with pytest.raises(ValueError, match="must be of type"):
        _validate_non_zero_float(data, "input_float")


@pytest.mark.parametrize("param_name", ["input_float", "test_float", "data_float"])
def test_validate_non_zero_float_invalid_param_name(param_name: str) -> None:
    """Test that invalid float param_name handling raises an exception.

    Parameters
    ----------
    param_name : str
        Various parameter names tested against invalid float input.

    Returns
    -------
    None
    """
    with pytest.raises(ValueError, match="must be of type"):
        _validate_non_zero_float(None, param_name)

```

## Sanity / boundary checks

Test every guard clause in the source (shape constraints, range checks, callable checks,
empty-array checks, etc.).

```python
# NOTE: Replace `CurveFitter` with the actual class under test from your fixture.
def test_non_callable_func(
    instance: CurveFitter,
    sample_data: tuple[NDArray[np.float64], NDArray[np.float64]],
) -> None:
    """Test raises TypeError when func is not callable.

    Verifies
    --------
    That providing a non-callable function argument raises TypeError
    with appropriate error message.

    Parameters
    ----------
    instance : CurveFitter
        Instance of the class containing the method under test
    sample_data : tuple[NDArray[np.float64], NDArray[np.float64]]
        Tuple of (x, y) test data from fixture

    Returns
    -------
    None
    """
    x, y = sample_data
    with pytest.raises(TypeError, match="func must be callable"):
        instance.optimize_curve_fit("not a function", x, y)


def test_empty_array_x(
    instance: CurveFitter,
    sample_data: tuple[NDArray[np.float64], NDArray[np.float64]],
    linear_func: Callable[[NDArray[np.float64], float, float], NDArray[np.float64]],
) -> None:
    """Test raises ValueError when array_x is empty.

    Verifies
    --------
    That providing an empty x array raises ValueError
    with appropriate error message.

    Parameters
    ----------
    instance : CurveFitter
        Instance of the class containing the method under test
    sample_data : tuple[NDArray[np.float64], NDArray[np.float64]]
        Tuple of (x, y) test data from fixture
    linear_func : Callable[[NDArray[np.float64], float, float], NDArray[np.float64]]
        Linear test function from fixture

    Returns
    -------
    None
    """
    _, y = sample_data
    with pytest.raises(ValueError, match="Input arrays cannot be empty"):
        instance.optimize_curve_fit(linear_func, np.array([], dtype=np.float64), y)
```

## What to cover

### 1. Normal Operations
- **Happy path scenarios**: Test standard use cases with valid inputs
- **Expected inputs**: Test with typical, well-formed inputs
- **Return values**: Verify correct return values and types
- **Side effects**: Check expected side effects (prints, file writes, state changes)
- **State changes**: Verify object state changes and persistence
- **Module initialization**: Test proper module setup and imports

### 2. Edge Cases
- **Boundary conditions**: Test min/max values, empty collections, single elements
- **Special values**: Test with None, 0, empty strings, whitespace, infinity
- **Large inputs**: Test with large data sets, memory limits
- **Unicode/special characters**: Test international characters, emojis, control chars
- **Case sensitivity**: Test upper/lower case variations
- **Numeric edge cases**: Test floating point precision, overflow, underflow
- **Collection edge cases**: Test empty, single-element, and large collections

### 3. Error Conditions
- **Invalid types**: Test with completely wrong data types
- **Invalid values**: Test with out-of-range, malformed, or inappropriate values
- **Missing resources**: Test when files, network, databases are unavailable
- **System errors**: Test I/O errors, memory errors, permission errors
- **Exception propagation**: Verify exceptions are properly raised and handled
- **Timeout scenarios**: Test operations that might hang or timeout
- **Resource exhaustion**: Test behavior when resources are depleted

### 4. Type Validation
- **Function signatures**: Verify parameter and return type annotations
- **Input validation**: Test runtime type checking on inputs
- **Return type verification**: Ensure returns match declared types
- **Generic type handling**: Test with List[T], Dict[K,V], Optional[T]
- **Union type support**: Test Union[str, int], Optional parameters
- **Protocol compliance**: Test structural subtyping if applicable

### 5. Fallback Logic
- **Primary method failures**: Test when main implementation fails
- **Import fallbacks**: Test behavior when optional imports fail
- **Configuration fallbacks**: Test default config when files missing
- **Version detection**: Test fallback version detection mechanisms
- **Dependency fallbacks**: Test graceful degradation without optional deps
- **Data source fallbacks**: Test switching between data sources

### 6. Reload Logic *(only if the module uses `importlib.reload`)*

> Skip this section unless the source file explicitly calls `importlib.reload()`.
> Check with `grep -n "importlib.reload" <source_file>` before generating these tests.

- **Module reloading**: Test importlib.reload() behavior
- **State preservation**: Test what state survives reloads
- **Cache invalidation**: Test cache clearing during reloads
- **Patch reapplication**: Test that patches are reapplied correctly
- **Circular imports**: Test handling of circular import scenarios
- **Dependency updates**: Test behavior when dependencies change

### 7. Examples in Docstrings
- **Examples section**: Add code examples from docstrings in unit tests

### 8. Coverage Validation
- **Line coverage**: Ensure every line of code is executed
- **Branch coverage**: Test all conditional branches (if/else, try/except)
- **Function coverage**: Test all functions and methods
- **Exception coverage**: Test all exception handling paths
- **Import coverage**: Test all import statements and fallbacks

### 9. Performance rules (critical)
- **Never make real HTTP / DB / filesystem calls** — always mock at the boundary
- Bypass retry/backoff decorators:
  ```python
  mocker.patch("backoff.on_exception", lambda *args, **kwargs: lambda func: func)
  ```
- Mock `time.sleep`, `datetime.now()`, `time.time()` to eliminate delays
- Use `autouse=True` fixtures to set up shared mocks across a class
- **Use fixtures for common responses** to avoid repetitive mocking

## Assertion patterns

### Specific Assertions
- Use specific assertions over generic ones
- `assert actual == expected` over `assert actual`
- `assert len(result) == 3` over `assert result`
- Use `pytest.raises()` for exception testing
- Use `pytest.warns()` for warning testing
- Use `assert result == pytest.approx(expected, abs=1e-6)` for float comparisons; for relative tolerance use `pytest.approx(expected, rel=1e-3)`. Never wrap both sides in `pytest.approx`.

### Common Assertion Patterns
```python
# exception testing with message matching
with pytest.raises(ValueError, match=r"specific.*pattern"):
    function_that_should_raise()

# multiple exception types
with pytest.raises((ValueError, TypeError)):
    function_that_might_raise_either()

# warning testing
with pytest.warns(UserWarning, match="deprecation"):
    deprecated_function()

# approximate comparisons (wrap expected only, never both sides)
assert result == pytest.approx(expected, abs=1e-6)
assert result == pytest.approx(expected, rel=1e-3)

# collection assertions
assert set(result) == set(expected)  # order doesn't matter
assert result == expected  # order matters
assert all(isinstance(item, int) for item in result)

# type assertions
assert isinstance(result, ExpectedType)
assert type(result) is ExactType  # exact type check
assert hasattr(result, "required_method")

# attribute access (AVOID Ruff B009 violation)
# incorrect - using getattr with constant string
run_method = getattr(instance, 'run')  # B009 violation

# correct - use direct attribute access
run_method = instance.run  # no violation

# pandas dataframe declaration
# incorrect - use of generic variable `df` (avoid Ruff PD901 violation)
df = b3_instance.transform_data(file=empty_content)

# correct - use df_
df_ = b3_instance.transform_data(file=empty_content)

# when declaring a test token, please add a noqa S105 possible hardcoded password assigned
# incorrect
b3_instance.token = "test_token"

# correct
b3_instance.token = "test_token" # noqa S105: possible hardcoded password assigned

# use a single `with` statement with multiple contexts instead of nested `with` statements
# incorrect - SIM117 Ruff violation
with pytest.raises(ValueError, match="Token not available\\. Call get_token\\(\\) first\\."):
        # Mock backoff to prevent retry delays
        with pytest.MonkeyPatch().context() as m:
            m.setattr("backoff.on_exception", lambda *args, **kwargs: lambda func: func)
            b3_instance.get_response(timeout=(12.0, 12.0), bool_verify=False)

# correct
with pytest.raises(ValueError, match="Token not available\\. Call get_token\\(\\) first\\."), \
    pytest.MonkeyPatch().context() as m:
    m.setattr("backoff.on_exception", lambda *args, **kwargs: lambda func: func)
    b3_instance.get_response(timeout=(12.0, 12.0), bool_verify=False)

# string assertions
assert "substring" in result
assert result.startswith("prefix")
assert result.endswith("suffix")
assert re.match(r"pattern", result)

# numeric assertions
assert 0 <= result <= 100
assert result > 0
assert math.isfinite(result)
assert not math.isnan(result)

# file and path assertions
assert path.exists()
assert path.is_file()
assert path.stat().st_size > 0

# mock assertions
mock_function.assert_called_once_with(expected_arg)
mock_function.assert_called_with(expected_arg)
mock_function.assert_not_called()
assert mock_function.call_count == 2
```

### Coverage-Specific Assertions
```python
# ensure all branches are tested
def test_all_branches():
    # test condition True
    result_true = function_with_condition(True)
    assert result_true == expected_true

    # test condition False
    result_false = function_with_condition(False)
    assert result_false == expected_false

# ensure all exception paths are tested
def test_all_exception_paths():
    # test normal path
    result = function_that_might_fail("valid")
    assert result == expected

    # test each exception path
    with pytest.raises(ValueError):
        function_that_might_fail("invalid_value")

    with pytest.raises(TypeError):
        function_that_might_fail(123)

# ensure loop edge cases are tested
def test_loop_edge_cases():
    # test empty loop
    result = function_with_loop([])
    assert result == empty_result

    # test single iteration
    result = function_with_loop([1])
    assert result == single_result

    # test multiple iterations
    result = function_with_loop([1, 2, 3])
    assert result == multi_result
```

## Performance Considerations

### Test Efficiency
- Use fixtures for expensive setup operations
- Mock external dependencies to speed up tests
- Use parametrized tests for similar test cases
- Avoid unnecessary file I/O in tests
- 100% code coverage achieved

### Resource Management
- Clean up resources in teardown/fixtures
- Use context managers for file operations
- Mock time-dependent operations
- Limit test data size for performance

## Advanced Mocking Techniques

### Patching Strategies
```python
# patch at class level for multiple tests
@pytest.fixture(autouse=True)
def setup_mocks(mocker: MockerFixture) -> None:
    """Setup common mocks for all tests in this class."""
    mocker.patch("requests.get")
    mocker.patch("time.sleep")
    mocker.patch("module.expensive_function", return_value="fast_result")

# context-specific patching
@pytest.mark.parametrize("side_effect", [
    None,  # successful case
    ConnectionError("Network error"),
    TimeoutError("Request timeout"),
])
def test_network_resilience(instance, mocker, side_effect):
    """Test network error handling with various failures."""
    mock_get = mocker.patch("requests.get")
    if side_effect:
        mock_get.side_effect = side_effect
        with pytest.raises(type(side_effect)):
            instance.fetch_data()
    else:
        mock_get.return_value.json.return_value = {"data": "success"}
        result = instance.fetch_data()
        assert result == {"data": "success"}

# mock complex objects with spec
@pytest.fixture
def mock_database_session(mocker: MockerFixture) -> MagicMock:
    """Create a properly specified database session mock."""
    mock_session = MagicMock(spec=Session)
    mock_session.query.return_value.filter.return_value.first.return_value = None
    return mocker.patch("module.Session", return_value=mock_session)
```

### Fast Data Generation
```python
# use minimal test data
@pytest.fixture
def minimal_test_data() -> dict:
    """Provide the smallest valid data set for testing."""
    return {
        "required_field": "value",
        "optional_list": [],
        "count": 0
    }

# generate data efficiently
def generate_test_items(count: int = 3) -> list[dict]:
    """Generate minimal test items for performance."""
    return [{"id": i, "name": f"item_{i}"} for i in range(count)]

# use factory functions instead of complex fixtures
def create_test_instance(**overrides) -> TestClass:
    """Factory function for test instances with overrides."""
    defaults = {"param1": "default", "param2": 0}
    defaults.update(overrides)
    return TestClass(**defaults)
```

### Error Simulation Without Delays
```python
# fast error testing
@pytest.mark.parametrize("error_class,error_message", [
    (HTTPError, "404 Not Found"),
    (ConnectionError, "Connection refused"),
    (TimeoutError, "Request timeout"),
])
def test_error_handling_fast(instance, mocker, error_class, error_message):
    """Test various error conditions without network delays."""
    mock_request = mocker.patch("requests.get")
    mock_request.side_effect = error_class(error_message)
    
    # mock backoff to prevent retry delays
    mocker.patch("backoff.on_exception", lambda *args, **kwargs: lambda func: func)
    
    with pytest.raises(error_class, match=error_message):
        instance.method_with_requests()

# fast timeout simulation
def test_timeout_handling(instance, mocker):
    """Test timeout handling without actual waiting."""
    # mock the timeout to occur immediately
    mock_request = mocker.patch("requests.get")
    mock_request.side_effect = TimeoutError("Simulated timeout")
    
    with pytest.raises(TimeoutError):
        instance.method_with_timeout()
    
    # verify timeout was handled correctly
    mock_request.assert_called_once()
```

### Concurrent Operations Testing
```python
# test async operations without actual delays
@pytest.mark.asyncio
async def test_async_operations(mocker):
    """Test async functionality with mocked delays."""
    # mock asyncio.sleep to eliminate delays
    mocker.patch("asyncio.sleep")
    
    # mock async HTTP calls
    mock_session = AsyncMock()
    mock_session.get.return_value.__aenter__.return_value.json = AsyncMock(
        return_value={"data": "test"}
    )
    
    result = await async_function_under_test()
    assert result["data"] == "test"

# test thread-safe operations
def test_thread_safety(instance, mocker):
    """Test thread safety without actual threading delays."""
    import threading
    from unittest.mock import call
    
    mock_method = mocker.patch.object(instance, "thread_safe_method")
    threads = []
    
    # create threads but don't add delays
    for i in range(5):
        thread = threading.Thread(target=instance.concurrent_operation, args=(i,))
        threads.append(thread)
        thread.start()
    
    # wait for completion (should be fast with mocked operations)
    for thread in threads:
        thread.join(timeout=1)  # Fail fast if something hangs
    
    # verify all calls were made
    assert mock_method.call_count == 5
```

### Database and File System Mocking
```python
# fast database testing
@pytest.fixture
def mock_database_operations(mocker: MockerFixture) -> dict:
    """Mock all database operations for speed."""
    mocks = {
        "connect": mocker.patch("sqlalchemy.create_engine"),
        "session": mocker.patch("sqlalchemy.orm.sessionmaker"),
        "query": mocker.MagicMock(),
    }
    
    # setup realistic but fast responses
    mocks["query"].filter.return_value.first.return_value = None
    mocks["query"].filter.return_value.all.return_value = []
    
    return mocks

# fast file system testing
@pytest.fixture
def mock_filesystem(mocker: MockerFixture) -> dict:
    """Mock file system operations."""
    return {
        "open": mocker.mock_open(read_data="test content"),
        "exists": mocker.patch("pathlib.Path.exists", return_value=True),
        "mkdir": mocker.patch("pathlib.Path.mkdir"),
        "unlink": mocker.patch("pathlib.Path.unlink"),
    }

def test_file_operations(instance, mock_filesystem):
    """Test file operations without actual I/O."""
    with patch("builtins.open", mock_filesystem["open"]):
        result = instance.read_config_file()
        assert "test content" in result
    
    mock_filesystem["exists"].assert_called()
```

## Test Organization for Speed

### Group Related Tests
```python
class TestFastNetworkOperations:
    """Group network-related tests with shared mocking."""
    
    @pytest.fixture(autouse=True)
    def setup_network_mocks(self, mocker: MockerFixture) -> None:
        """Setup network mocks for all tests in this class."""
        self.mock_get = mocker.patch("requests.get")
        self.mock_post = mocker.patch("requests.post")
        self.mock_sleep = mocker.patch("time.sleep")
        
        # default successful response
        self.mock_response = MagicMock()
        self.mock_response.status_code = 200
        self.mock_response.json.return_value = {"success": True}
        self.mock_get.return_value = self.mock_response
    
    def test_get_request(self, instance):
        """Test GET request handling."""
        result = instance.fetch_data("test_url")
        assert result["success"] is True
        self.mock_get.assert_called_once_with("test_url")
    
    def test_post_request(self, instance):
        """Test POST request handling."""
        self.mock_post.return_value = self.mock_response
        result = instance.send_data("test_url", {"key": "value"})
        assert result["success"] is True
        self.mock_post.assert_called_once()
```

### Optimize Fixture Scope
```python
# use session-scoped fixtures for expensive setup
@pytest.fixture(scope="session")
def expensive_resource():
    """Create expensive resource once per test session."""
    # this runs once for all tests
    return create_expensive_resource()

# use function-scoped mocks for isolation
@pytest.fixture(scope="function")
def isolated_mock(mocker: MockerFixture):
    """Create fresh mock for each test function."""
    return mocker.patch("module.function")

# use class-scoped fixtures for related test groups
@pytest.fixture(scope="class")
def shared_test_data():
    """Share data across tests in the same class."""
    return generate_large_test_dataset()
```

## Ruff compliance checklist

Before writing the final file verify mentally:
- [ ] No `F401` unused imports
- [ ] No `B009` `getattr` with constant string
- [ ] No `PD901` bare `df` variable
- [ ] No `SIM117` nested `with` statements
- [ ] No `S105` hardcoded password without `# noqa S105`
- [ ] All `typing.Dict/List/Tuple` replaced with primitives