# Dependency Injection

## Anything with a lifecycle or that should be swappable in tests goes through `Depends`

DB sessions, HTTP clients, the current authenticated user, feature-flag clients — if a
test would ever want to substitute it, it belongs behind `Depends(...)`, not
instantiated or imported as a module-level singleton inside the handler.

```python
# Bad — bypasses FastAPI's dependency lifecycle and test overrides
@router.get("/orders")
async def list_orders():
    db = SessionLocal()
    return db.query(Order).all()

# Good
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.get("/orders", response_model=list[OrderOut])
async def list_orders(db: Session = Depends(get_db)) -> list[Order]:
    return db.query(Order).all()
```

## Cleanup-requiring resources use a `yield` dependency

The code after `yield` runs whether the request succeeded or raised — that's the
mechanism for guaranteed `.close()`/commit/rollback, not a `finally` block duplicated
per route:

```python
def get_db():
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
```

## Don't call a dependency function directly in the handler body

```python
# Bad — same bug as above in a subtler form
async def get_endpoint(request: Request):
    user = get_current_user(request.headers.get("Authorization"))  # direct call
    ...

# Good
async def get_endpoint(user: User = Depends(get_current_user)):
    ...
```

Calling it directly means `app.dependency_overrides` can't substitute a fake user in
tests, and FastAPI's dependency caching (same dependency resolved once per request even
if used by multiple sub-dependencies) doesn't apply.

## Compose auth via dependency chaining, not repeated `if` per route

```python
async def get_current_user(token: str = Depends(oauth2_scheme)) -> User:
    ...

async def get_current_active_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Admin only")
    return user

@router.delete("/users/{user_id}")
async def delete_user(user_id: int, admin: User = Depends(get_current_active_admin)):
    ...
```

The role check lives in one place and is declarative at the route signature — a
reviewer can see the access requirement without reading the handler body, and it can't
be forgotten on a new route the way an inline `if user.role != "admin"` can.

## Expensive/global setup belongs in `lifespan`, not a per-request dependency

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http_client = httpx.AsyncClient()
    yield
    await app.state.http_client.aclose()

def get_http_client(request: Request) -> httpx.AsyncClient:
    return request.app.state.http_client
```

A dependency that opens a new `httpx.AsyncClient()` (or loads a model, or opens a DB
engine) on every request recreates expensive state per-request instead of once at
startup — `get_http_client` here just hands out the one instance created in `lifespan`.

## Use `app.dependency_overrides` in tests, not monkeypatching

```python
app.dependency_overrides[get_db] = lambda: test_session
```

It's the mechanism FastAPI ships specifically so dependency injection doesn't get in
the way of testing — if a test is reaching for `unittest.mock.patch` on something
that's already a `Depends`, that's a sign the override should be used instead.

## Blocking I/O inside `async def` blocks every concurrent request

```python
# Bad — blocks the event loop for every other in-flight request
@router.get("/rates")
async def get_rates():
    resp = requests.get("https://api.example.com/rates")  # sync call in async def
    return resp.json()

# Good — either use an async client...
@router.get("/rates")
async def get_rates(client: httpx.AsyncClient = Depends(get_http_client)):
    resp = await client.get("https://api.example.com/rates")
    return resp.json()

# ...or declare the route as plain `def` so FastAPI runs it in the threadpool
@router.get("/rates")
def get_rates():
    resp = requests.get("https://api.example.com/rates")
    return resp.json()
```

The rule only applies to `async def`. A plain `def` route or dependency already runs in
FastAPI's threadpool, so a blocking call there doesn't stall the event loop.
