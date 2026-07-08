# HTTP Error Handling

## Expected failures raise `HTTPException`, not a 200 with an error body

```python
# Bad — client has to check `success` instead of relying on the status code
@router.get("/orders/{order_id}")
async def get_order(order_id: int, db: Session = Depends(get_db)):
    order = db.get(Order, order_id)
    if not order:
        return {"success": False, "error": "not found"}
    return order

# Good
@router.get("/orders/{order_id}", response_model=OrderOut)
async def get_order(order_id: int, db: Session = Depends(get_db)) -> OrderOut:
    order = db.get(Order, order_id)
    if not order:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Order {order_id} not found",
        )
    return order
```

A `200` with `{"success": false}` breaks every generic HTTP client, cache layer, and
monitoring tool that keys off the status code — the status code *is* the contract.

## Use `status.*` constants, not magic numbers

`status.HTTP_404_NOT_FOUND` instead of `404` — greppable, self-documenting, and a typo
(`4004`) fails at import time via `IDE`/mypy noticing an unknown attribute rather than
silently shipping the wrong code.

## Don't swallow errors with a broad `except`

```python
# Bad — genuinely broken requests look like a success to the client
@router.post("/payments")
async def charge(payload: ChargeRequest):
    try:
        result = payment_gateway.charge(payload)
        return result
    except Exception:
        return {"status": "unknown"}   # actual error is now invisible

# Good — let it propagate, or handle the specific exception you expect
@router.post("/payments", response_model=ChargeResult)
async def charge(payload: ChargeRequest) -> ChargeResult:
    try:
        return payment_gateway.charge(payload)
    except PaymentGatewayTimeout as exc:
        raise HTTPException(status_code=status.HTTP_504_GATEWAY_TIMEOUT, detail=str(exc))
```

A bare `except Exception` (or worse, bare `except:`) that returns something other than
re-raising hides the failure from logs, metrics, and the client alike. If you don't know
what exception you're catching, you probably shouldn't be catching it at that layer —
let it hit FastAPI's default 500 handler (or a registered one) so it's actually visible.

## Domain exceptions get a registered handler, not per-route try/except

```python
class OutOfStockError(Exception):
    def __init__(self, sku: str):
        self.sku = sku

@app.exception_handler(OutOfStockError)
async def out_of_stock_handler(request: Request, exc: OutOfStockError):
    return JSONResponse(
        status_code=status.HTTP_409_CONFLICT,
        content={"detail": f"{exc.sku} is out of stock"},
    )
```

The service layer just raises `OutOfStockError(sku)`. No route needs its own
try/except for it — one handler covers every place that error can surface, and it's
easy to unit-test in isolation from any specific route.

## Never leak internal detail in a 5xx `detail`

```python
# Bad
raise HTTPException(status_code=500, detail=str(db_exc))  # may include SQL, table names

# Good
logger.exception("order_creation_failed", order_id=order_id)
raise HTTPException(status_code=500, detail="Internal error creating order")
```

Log the real exception server-side (with enough context to debug it) and return a
generic message to the client for anything in the 5xx range. 4xx `detail` can and should
be specific (it's client-actionable); 5xx `detail` should not describe internals.

## Prefer raising over returning `None` and hoping the caller checks

A service function that returns `None` on "not found" pushes the check onto every
caller, and it's easy for one route to forget the check and return `200` with a `null`
body. Raising a specific exception (or having the route explicitly check and raise
`HTTPException`) makes the failure impossible to silently skip.
