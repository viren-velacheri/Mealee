"""The single permitted model call: name a food region the segmenter could not classify.

The model is offered the crop and the fixed class list and must answer with one label
from that list. Anything else is discarded and the caller keeps the YOLO label. The
call has a hard timeout and is skipped on expiry, because the 4 second photo budget is
the demo and one unlabelled region is not.
"""

import base64
import logging

import httpx

from app.config import (IFM_API_KEY, IFM_BASE_URL, IFM_MODEL, IFM_VISION_ENABLED,
                        VISION_TIMEOUT_S)

log = logging.getLogger("mealee.vision")


def enabled() -> bool:
    return bool(IFM_API_KEY) and IFM_VISION_ENABLED


def label_crop(jpeg_bytes: bytes, class_labels: list[str]) -> str | None:
    if not enabled():
        return None
    options = ", ".join(class_labels)
    prompt = (f"Which one of these foods is in the photo? Answer with exactly one item from "
              f"the list and nothing else: {options}")
    body = {
        "model": IFM_MODEL,
        "max_tokens": 8,
        "temperature": 0,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {
                    "url": "data:image/jpeg;base64," + base64.b64encode(jpeg_bytes).decode()}},
            ],
        }],
    }
    try:
        response = httpx.post(f"{IFM_BASE_URL}/chat/completions", json=body,
                              headers={"Authorization": f"Bearer {IFM_API_KEY}"},
                              timeout=VISION_TIMEOUT_S)
        response.raise_for_status()
        answer = response.json()["choices"][0]["message"]["content"].strip().lower().rstrip(".")
    except (httpx.HTTPError, KeyError, IndexError, ValueError) as error:
        log.info("vision fallback skipped: %s", error)
        return None
    if answer in class_labels:
        return answer
    log.info("vision fallback answered outside the class list: %r", answer)
    return None
