# OpenAPI Documentation

FastAPI generates `/docs`, `/redoc`, and `/openapi.json` from the code itself — the
gap between "the code works" and "the generated docs are actually useful" is entirely
about the metadata below. This matters as much for a human reading `/docs` as for an
LLM agent consuming the OpenAPI schema to call the API on someone's behalf.

## `summary`/description, always

```python
@router.post(
    "/orders",
    summary="Create an order",
    description="Creates an order for the authenticated user and reserves stock.",
    response_model=OrderOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_order(payload: OrderCreate, user: User = Depends(get_current_user)):
    """Creates an order for the authenticated user and reserves stock."""
    ...
```

A docstring on the handler is picked up as the description automatically if
`description=` isn't set explicitly — either is fine, but at least one of them should
exist. A route with neither shows up in `/docs` with no explanation beyond its path.

## Consistent `tags` per resource

```python
router = APIRouter(prefix="/orders", tags=["orders"])
```

Setting `tags` once on the `APIRouter` (rather than repeating it per route, or omitting
it) keeps the generated docs grouped by resource instead of one flat alphabetical list.

## Document the non-2xx responses the endpoint can actually return

```python
@router.get(
    "/orders/{order_id}",
    response_model=OrderOut,
    responses={
        404: {"description": "Order not found"},
        403: {"description": "Order belongs to a different user"},
    },
)
async def get_order(order_id: int, user: User = Depends(get_current_user)):
    ...
```

Without `responses={...}`, `/docs` only advertises the 200 case — a consumer (human or
agent) building against the happy path finds out about the error shapes by hitting them
in production instead of reading them in the schema.

## Set `status_code` explicitly for anything that isn't 200

```python
@router.post("/orders", status_code=status.HTTP_201_CREATED)
@router.delete("/orders/{order_id}", status_code=status.HTTP_204_NO_CONTENT)
```

Creation endpoints returning `200` instead of `201`, or deletion endpoints returning a
body with `200` instead of an empty `204`, are common enough that a reviewer should
check this explicitly rather than assume the default is fine.

## Realistic examples on request/response models

```python
class OrderCreate(BaseModel):
    sku: str = Field(examples=["SKU-1234"])
    quantity: int = Field(gt=0, examples=[2])
```

The "Try it out" panel in `/docs` and any generated client SDK use these as the default
payload — a placeholder like `"string"` / `0` (Pydantic's zero-value default when no
example is given) is a worse starting point than a realistic value.

## Mark superseded routes `deprecated=True`

```python
@router.get("/v1/orders/{order_id}", deprecated=True)
```

Rather than leaving an old and new version of an endpoint undocumented side by side,
`deprecated=True` visibly strikes it through in `/docs` and signals intent without
requiring the route to actually be removed yet.

## Keep `operation_id` stable if generated client SDKs matter

If the project generates a TypeScript/Python client from the OpenAPI schema
(`openapi-typescript`, `openapi-generator`, etc.), be aware that the default
`operation_id` is derived from the function name — renaming the handler silently
renames every generated client method. Set `operation_id=` explicitly if that stability
matters to consumers of the generated client.
