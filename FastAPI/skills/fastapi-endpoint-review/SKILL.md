---
name: fastapi-endpoint-review
description: Reviews a new or modified FastAPI endpoint against production practices in four areas — Pydantic request/response validation, HTTP error handling, dependency injection, and OpenAPI documentation. Use when a user adds or changes a route (`@app.get`, `@router.post`, etc.) and asks for a review, a second opinion, or "is this endpoint ready to merge", or before approving a PR that touches a FastAPI `routers/`, `api/`, or `endpoints/` folder. Not for Flask/Django views — trigger only on `fastapi`/`APIRouter`/`Depends` imports.
version: 1.0.0
metadata:
  hermes:
    tags: [fastapi, python, pydantic, api, code-review]
    category: backend
---

# FastAPI Endpoint Review

Original skill by Dominicode. Not affiliated with, endorsed by, or tested against a
production Hermes deployment — see the honesty note in the category `README.md` before
treating this as anything more than a first version.

## When to Use

- A user just wrote or changed a FastAPI route and asks "does this look right?", "review
  this endpoint", or "is this ready to merge?".
- You are asked to review a pull request / diff that touches a router file, and the diff
  adds or modifies a function decorated with `@app.get/post/put/patch/delete` or the
  `APIRouter` equivalent.
- Do **not** trigger this for Flask (`@app.route`) or Django (class-based views,
  `urls.py`) — check for a `fastapi` import or `APIRouter`/`Depends` usage first. If the
  file doesn't import FastAPI, stop and say so instead of forcing the checklist.

## Procedure

1. **Locate the endpoint(s).** Find the route decorator and the handler function body.
   If reviewing a PR/diff, scope the review to the changed function(s) only — don't
   re-review unrelated routes in the same file.

2. **Check Pydantic validation.** Read `references/pydantic-validation.md`. In short:
   request body is an explicit `BaseModel` (never raw `dict`/`Any`), field constraints
   live in `Field(...)`/specialized types instead of manual `if` checks in the handler
   body, and `response_model` is declared explicitly and never reuses a model that
   carries secrets (password hashes, internal flags).

3. **Check HTTP error handling.** Read `references/error-handling.md`. In short:
   expected failures raise `HTTPException` with a `status.*` constant, no bare
   `except Exception` swallows an error and returns 200, domain exceptions are handled
   by a registered `@app.exception_handler` rather than per-route try/except, and 5xx
   `detail` never leaks stack traces or internal identifiers.

4. **Check dependency injection.** Read `references/dependencies.md`. In short: DB
   sessions/clients arrive via `Depends(...)` (never instantiated inline in the handler),
   anything needing cleanup uses a `yield` dependency, auth/role checks are composed via
   dependency chaining, and there's no blocking I/O inside an `async def` route without
   offloading it.

5. **Check OpenAPI documentation.** Read `references/openapi-docs.md`. In short:
   `summary`/docstring present, `tags` set consistently, non-2xx responses documented via
   `responses={...}`, and `status_code` set explicitly when it isn't the default 200.

6. **Optional fast pass:** run the static checker for a mechanical first pass before the
   semantic read above:

   ```bash
   python scripts/check_endpoint.py path/to/router.py
   ```

   This only catches syntactic patterns (missing `response_model`, bare `except`,
   blocking calls inside `async def`, missing summary/docstring) — it is not a
   replacement for steps 2-5, only a way to not miss the obvious ones. See
   `assets/example_endpoint_before.py` / `assets/example_endpoint_after.py` for a
   worked before/after the checker flags and clears.

7. **Report findings** using `templates/review-checklist.md` — one checklist per
   endpoint, grouped by the four areas above, with a final verdict (ready to merge /
   needs changes) and findings split into blockers / should-fix / nits. Don't just say
   "looks good" — either fill in the checklist or explicitly state which sections you
   skipped and why (e.g., "no auth on this route by design, skipping dependency
   auth-chaining checks").

## Pitfalls

- **Don't flag FastAPI's automatic 422 as a bug.** Pydantic validation failures already
  return `422 Unprocessable Entity` with a structured `{"detail": [...]}` body for free —
  never suggest wrapping the body in a manual `try/except ValidationError` to "handle"
  this, that's duplicating what FastAPI already does correctly.
- **`def` vs `async def` changes the blocking-I/O rule.** A route declared as plain `def`
  runs in FastAPI's threadpool, so a blocking call (`requests.get`, sync DB driver) there
  is fine. The same call inside `async def` blocks the single event loop for every
  concurrent request. Check the function signature before flagging blocking calls.
- **Don't demand `response_model` on responses that intentionally bypass it** —
  `StreamingResponse`, `FileResponse`, `RedirectResponse`, and raw `Response` subclasses
  are legitimate exceptions; `response_model` doesn't apply to them.
- **`Depends(get_db)` is the correct pattern, not an anti-pattern.** Don't recommend
  "simplifying" it to a direct call (`db = get_db()`) — that removes the ability to
  override it in tests and breaks cleanup ordering on `yield` dependencies.
- **Query/body defaults aren't the classic Python mutable-default trap.**
  `Query(default=[])` or `Body(default={})` are FastAPI descriptor objects, not the
  literal default stored on the function — don't flag them the way you would flag
  `def f(x=[])` in plain Python.
- **A missing `tags=` or `summary=` is a nit, not a blocker.** Don't let documentation
  gaps outrank an actual data-leak or missing-auth finding in the verdict.

## Verification

- If tests exist for the endpoint, run them (`pytest path/to/test_file.py`) after any
  suggested fix — a "fix" that breaks the existing test suite isn't a fix.
- Start the app locally (or use the existing dev server) and hit `/openapi.json` (or
  `/docs`) to confirm the schema actually reflects the new `response_model` / status
  codes / documented error responses — the source diff and the generated schema can
  drift if a decorator argument was misspelled.
- For a validation fix, send a deliberately invalid payload (missing field, wrong type)
  with `curl`/`httpie` and confirm a `422` with the expected field path comes back —
  not a `500` (which would mean the model isn't actually being used) and not a `200`
  (which would mean validation was accidentally bypassed).
- For an error-handling fix, trigger the failure path on purpose (nonexistent ID,
  duplicate key, etc.) and confirm the status code and `detail` shape match what the
  review recommended — don't take the diff's intent as proof it behaves that way.
- Re-run `scripts/check_endpoint.py` on the file — it should no longer flag the issues
  that were fixed. If it still flags something, the fix is incomplete or the checker has
  a false positive worth noting in the checklist's notes field.
