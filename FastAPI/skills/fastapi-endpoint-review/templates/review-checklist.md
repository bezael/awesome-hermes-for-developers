# Endpoint Review — `<METHOD> <path>`

**File:** `path/to/router.py`
**Function:** `<handler_name>`
**Reviewed:** `<date>`

## 1. Pydantic validation

- [ ] Request body is an explicit `BaseModel` (not raw `dict`/`Any`)
- [ ] Field-level constraints used where applicable (`Field`, `EmailStr`, `conint`, `constr`, etc.)
- [ ] `response_model` declared explicitly and excludes internal-only fields (no password hashes, no internal flags)
- [ ] `extra="forbid"` set deliberately, or `extra="allow"`/default is a conscious choice, not an oversight
- [ ] Cross-field validation (if any) lives in a `@model_validator`, not ad hoc in the handler

Notes:

## 2. Error handling

- [ ] Client-facing failures raise `HTTPException` with a `status.*` constant (not a magic number, not a 200-with-error-body)
- [ ] No bare `except`/`except Exception` swallowing an error and returning success
- [ ] Domain exceptions are handled by a registered `@app.exception_handler`, not per-route try/except
- [ ] 5xx `detail` doesn't leak stack traces, SQL text, or internal identifiers

Notes:

## 3. Dependencies

- [ ] DB session / external clients arrive via `Depends(...)`, never instantiated inline in the handler
- [ ] Cleanup-requiring resources use a `yield` dependency
- [ ] Auth/role checks are composed via dependency chaining, not repeated `if` per route
- [ ] No blocking I/O inside `async def` without offloading it (or the route is plain `def`)

Notes:

## 4. OpenAPI documentation

- [ ] `summary`/description or docstring present
- [ ] `tags` set and consistent with the rest of the router
- [ ] Non-2xx responses documented via `responses={...}`
- [ ] `status_code` set explicitly if not the default `200`

Notes:

## Verdict

- [ ] Ready to merge
- [ ] Needs changes (see notes above)

**Blockers:**

**Should-fix (non-blocking):**

**Nits:**
