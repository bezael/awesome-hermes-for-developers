# Pydantic Validation

## Explicit request models, never raw `dict`/`Any`

```python
# Bad — no validation, no docs, no autocomplete downstream
@router.post("/users")
async def create_user(payload: dict) -> dict:
    ...

# Good
class UserCreate(BaseModel):
    email: EmailStr
    password: constr(min_length=8)
    full_name: str = Field(max_length=120)

@router.post("/users", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def create_user(payload: UserCreate) -> UserOut:
    ...
```

If the handler accepts `dict`/`Any`, FastAPI can't validate it, can't document it in
`/docs`, and every field access downstream needs a manual `.get()` + type check that
Pydantic would have done for free.

## Field-level constraints over manual `if` checks

Put the constraint on the field, not in the function body:

```python
class Pagination(BaseModel):
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)
```

vs. the handler doing `if page < 1: raise HTTPException(...)` — the manual version is
easy to forget on one of several similar endpoints, and it doesn't show up in the
generated OpenAPI schema as a documented constraint.

Prefer specialized types over `str` + a regex you maintain yourself:

| Instead of | Use |
|---|---|
| `str` + manual email regex | `EmailStr` |
| `str` + manual URL check | `HttpUrl` / `AnyUrl` |
| `str` with a length check in the body | `constr(min_length=..., max_length=...)` |
| `int` with a manual range check | `conint(ge=..., le=...)` |
| `str` matched against an enum of values by hand | a Python `Enum` as the field type |

## Separate request and response models

Never let the same model serve as both the request body and the `response_model` if it
carries anything internal:

```python
# Bad — UserOut = User model reused as-is; password_hash leaks in the response
class User(BaseModel):
    id: int
    email: EmailStr
    password_hash: str

@router.post("/users", response_model=User)  # leaks password_hash
async def create_user(payload: User): ...

# Good — explicit output shape
class UserOut(BaseModel):
    id: int
    email: EmailStr

@router.post("/users", response_model=UserOut)
async def create_user(payload: UserCreate) -> UserOut: ...
```

`response_model` isn't just documentation — FastAPI uses it to filter the actual
response, so omitting it (or reusing the wrong model) is a real data-exposure risk, not
just a style issue.

## Declare `response_model` explicitly, always

Even when the return type hint would let FastAPI infer a shape, set `response_model=`
on the decorator. It's what drives output filtering and the `/docs` schema — relying on
inference is fragile the moment someone changes the return type hint without touching
the decorator.

## Reject or intentionally allow unexpected fields

```python
class UserCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr
    password: str
```

Pydantic v2's default (`extra="ignore"`) silently drops fields the client sent that
don't match the model — a typo'd field name (`emial` instead of `email`) fails silently
instead of surfacing as a client-visible 422. Use `extra="forbid"` unless the endpoint
has a real reason to accept a superset of fields.

## Cross-field validation belongs in the model, not the handler

```python
class DateRange(BaseModel):
    date_from: date
    date_to: date

    @model_validator(mode="after")
    def check_order(self) -> "DateRange":
        if self.date_from > self.date_to:
            raise ValueError("date_from must be before date_to")
        return self
```

Keeps the check next to the fields it validates and makes it reusable anywhere the model
is used, instead of duplicated `if` logic in every handler that accepts a date range.

## Partial updates (PATCH) need "was this field provided" semantics

```python
class UserUpdate(BaseModel):
    email: EmailStr | None = None
    full_name: str | None = None

@router.patch("/users/{user_id}", response_model=UserOut)
async def update_user(user_id: int, payload: UserUpdate, db: Session = Depends(get_db)):
    updates = payload.model_dump(exclude_unset=True)
    ...
```

Without `exclude_unset=True`, there's no way to distinguish "client explicitly set
`full_name` to null" from "client didn't send `full_name` at all" — both look like
`None` on the model unless you check what was actually provided in the payload.
