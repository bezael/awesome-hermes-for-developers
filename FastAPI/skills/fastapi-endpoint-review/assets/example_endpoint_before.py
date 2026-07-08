"""Illustrative "before" endpoint — intentionally written with the anti-patterns
this skill's checklist and scripts/check_endpoint.py are meant to catch. Not a
real production file; used only as a worked example in SKILL.md and to exercise
the static checker.
"""

import time
import requests
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()


class OrderCreate(BaseModel):
    sku: str
    quantity: int


@router.post("/orders")
async def create_order(payload: OrderCreate):
    # No response_model, no summary/docstring, blocking calls in async def,
    # and a bare except that swallows the real error.
    try:
        time.sleep(0.1)  # simulates a blocking pre-check
        rates = requests.get("https://api.example.com/rates").json()
        return {"sku": payload.sku, "quantity": payload.quantity, "rate": rates}
    except Exception:
        return {"status": "unknown"}
