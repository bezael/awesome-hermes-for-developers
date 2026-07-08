"""Illustrative "after" endpoint — the same route from example_endpoint_before.py
with the findings from this skill's checklist applied. Not a real production
file; used only as a worked example in SKILL.md and to exercise the static
checker (should report OK).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
import httpx

router = APIRouter(prefix="/orders", tags=["orders"])


class OrderCreate(BaseModel):
    sku: str = Field(examples=["SKU-1234"])
    quantity: int = Field(gt=0, examples=[2])


class OrderOut(BaseModel):
    sku: str
    quantity: int
    rate: float


async def get_http_client() -> httpx.AsyncClient:
    # In real code this reads a client created once in the app's lifespan
    # (see references/dependencies.md) instead of being created here.
    async with httpx.AsyncClient() as client:
        yield client


@router.post(
    "/",
    response_model=OrderOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create an order",
    responses={502: {"description": "Rate provider unavailable"}},
)
async def create_order(
    payload: OrderCreate,
    client: httpx.AsyncClient = Depends(get_http_client),
) -> OrderOut:
    """Creates an order and attaches the current exchange rate for its SKU."""
    try:
        resp = await client.get("https://api.example.com/rates")
        resp.raise_for_status()
        rate = resp.json()["rate"]
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Rate provider unavailable",
        ) from exc

    return OrderOut(sku=payload.sku, quantity=payload.quantity, rate=rate)
