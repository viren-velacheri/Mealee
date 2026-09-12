"""Photo to labelled regions with gram estimates. The CV core.

1. Find the scale reference: a credit card by contour geometry, or a fork from the
   segmenter. px_per_mm comes from the reference's longest side.
2. Segment food regions with YOLO. Keep confident masks above 1% of the image, merge
   overlapping masks of the same class, simplify to polygons under 40 points.
3. Label: YOLO class if it maps to foods.yaml, else one constrained vision call.
4. grams = area_mm2 * height_prior_mm / 1000 * density, with a +/-30% band.
"""

import io
import logging
import time
from dataclasses import dataclass, field

import cv2
import numpy as np
from PIL import Image

from app import vision
from app.config import YOLO_WEIGHTS
from app.foods import class_labels, food_classes, grams_from_area

log = logging.getLogger("mealee.portions")

CARD_LONG_MM = 85.6
CARD_ASPECT = 85.6 / 54.0
CARD_ASPECT_TOLERANCE = 0.12
FORK_LONG_MM = 190.0

MIN_MASK_CONFIDENCE = 0.35
MIN_REGION_SHARE_OF_IMAGE = 0.01
MAX_POLYGON_POINTS = 40

# Regions with no class in foods.yaml still get a size, so the player can correct the
# label and the grams are already there.
GENERIC_HEIGHT_MM = 15.0
GENERIC_DENSITY = 0.8

# Elapsed budget after which the vision fallback is skipped entirely.
VISION_START_DEADLINE_S = 2.4

COCO_TO_FOOD = {
    "banana": "banana",
    "apple": "apple",
    "sandwich": "sandwich",
    "orange": "orange",
    "broccoli": "broccoli",
    "carrot": "carrots",
    "pizza": "pizza slice",
    "cake": "cake",
    "cup": "coffee",
}
COCO_IGNORED = {"person", "dining table", "bottle", "knife", "spoon", "chair", "wine glass",
                "cell phone", "laptop", "book", "vase", "potted plant", "handbag", "backpack"}


class ScaleReferenceNotFound(Exception):
    pass


@dataclass
class Region:
    label: str
    confidence: float
    mask: np.ndarray
    known_class: bool
    area_px: int = 0
    polygon: list[list[int]] = field(default_factory=list)
    grams: float = 0.0
    grams_low: float = 0.0
    grams_high: float = 0.0


@dataclass
class Analysis:
    image_w: int
    image_h: int
    scale_type: str
    px_per_mm: float
    regions: list[Region]
    elapsed_s: float


_model = None


def _yolo():
    global _model
    if _model is None:
        from ultralytics import YOLO
        _model = YOLO(YOLO_WEIGHTS)
    return _model


def decode_image(jpeg_bytes: bytes) -> np.ndarray:
    pil = Image.open(io.BytesIO(jpeg_bytes)).convert("RGB")
    return cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)


def find_card_px_per_mm(image_bgr: np.ndarray) -> float | None:
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 50, 150)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

    image_area = image_bgr.shape[0] * image_bgr.shape[1]
    best_long_side = 0.0
    for contour in contours:
        area = cv2.contourArea(contour)
        if area < image_area * 0.004 or area > image_area * 0.25:
            continue
        approx = cv2.approxPolyDP(contour, 0.02 * cv2.arcLength(contour, True), True)
        if len(approx) != 4 or not cv2.isContourConvex(approx):
            continue
        (_, _), (w, h), _ = cv2.minAreaRect(approx)
        if min(w, h) == 0:
            continue
        aspect = max(w, h) / min(w, h)
        if abs(aspect - CARD_ASPECT) > CARD_ASPECT_TOLERANCE:
            continue
        if cv2.contourArea(approx) < 0.85 * w * h:
            continue
        best_long_side = max(best_long_side, max(w, h))

    if best_long_side == 0.0:
        return None
    return best_long_side / CARD_LONG_MM


def segment(image_bgr: np.ndarray) -> list[tuple[str, float, np.ndarray]]:
    """Returns (coco_class_name, confidence, boolean mask at image resolution)."""
    result = _yolo().predict(image_bgr, conf=MIN_MASK_CONFIDENCE, retina_masks=True,
                             verbose=False)[0]
    if result.masks is None:
        return []
    names = result.names
    masks = result.masks.data.cpu().numpy() > 0.5
    classes = result.boxes.cls.cpu().numpy().astype(int)
    confidences = result.boxes.conf.cpu().numpy()
    return [(names[cls], float(conf), mask) for cls, conf, mask in zip(classes, confidences, masks)]


def fork_px_per_mm(detections: list[tuple[str, float, np.ndarray]]) -> float | None:
    forks = [mask for name, _, mask in detections if name == "fork"]
    if not forks:
        return None
    largest = max(forks, key=lambda mask: int(mask.sum()))
    points = cv2.findNonZero(largest.astype(np.uint8))
    (_, _), (w, h), _ = cv2.minAreaRect(points)
    return max(w, h) / FORK_LONG_MM


def polygon_from_mask(mask: np.ndarray) -> list[list[int]]:
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return []
    outline = max(contours, key=cv2.contourArea)
    perimeter = cv2.arcLength(outline, True)
    epsilon = 0.004 * perimeter
    approx = cv2.approxPolyDP(outline, epsilon, True)
    while len(approx) > MAX_POLYGON_POINTS:
        epsilon *= 1.5
        approx = cv2.approxPolyDP(outline, epsilon, True)
    return [[int(x), int(y)] for [[x, y]] in approx]


def merge_same_label(regions: list[Region]) -> list[Region]:
    merged: dict[str, Region] = {}
    for region in regions:
        existing = merged.get(region.label)
        if existing is None:
            merged[region.label] = region
            continue
        existing.mask = existing.mask | region.mask
        existing.confidence = max(existing.confidence, region.confidence)
    return list(merged.values())


def crop_jpeg(image_bgr: np.ndarray, mask: np.ndarray) -> bytes:
    ys, xs = np.where(mask)
    crop = image_bgr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    ok, encoded = cv2.imencode(".jpg", crop, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return encoded.tobytes()


def analyze(jpeg_bytes: bytes) -> Analysis:
    started = time.perf_counter()
    image = decode_image(jpeg_bytes)
    image_h, image_w = image.shape[:2]
    image_area = image_h * image_w

    detections = segment(image)

    scale_type, px_per_mm = "card", find_card_px_per_mm(image)
    if px_per_mm is None:
        scale_type, px_per_mm = "fork", fork_px_per_mm(detections)
    if px_per_mm is None:
        raise ScaleReferenceNotFound()

    regions: list[Region] = []
    for coco_name, confidence, mask in detections:
        if coco_name in COCO_IGNORED or coco_name == "fork":
            continue
        if int(mask.sum()) < image_area * MIN_REGION_SHARE_OF_IMAGE:
            continue
        food_label = COCO_TO_FOOD.get(coco_name)
        regions.append(Region(
            label=food_label or coco_name,
            confidence=confidence if food_label else confidence * 0.5,
            mask=mask,
            known_class=food_label is not None,
        ))

    regions = merge_same_label(regions)

    for region in regions:
        if region.known_class:
            continue
        if time.perf_counter() - started > VISION_START_DEADLINE_S:
            log.info("skipping vision for %s, out of time", region.label)
            continue
        answer = vision.label_crop(crop_jpeg(image, region.mask), class_labels())
        if answer is not None:
            region.label = answer
            region.known_class = True
            region.confidence = 0.6

    regions = merge_same_label(regions)

    for region in regions:
        region.area_px = int(region.mask.sum())
        region.polygon = polygon_from_mask(region.mask)
        if region.known_class:
            region.grams, region.grams_low, region.grams_high = grams_from_area(
                region.label, region.area_px, px_per_mm)
        else:
            area_mm2 = region.area_px / (px_per_mm * px_per_mm)
            region.grams = area_mm2 * GENERIC_HEIGHT_MM / 1000.0 * GENERIC_DENSITY
            region.grams_low, region.grams_high = region.grams * 0.7, region.grams * 1.3

    return Analysis(image_w, image_h, scale_type, px_per_mm, regions,
                    time.perf_counter() - started)


def regrams(label: str, area_px: int, px_per_mm: float) -> tuple[float, float, float]:
    """Used when the player corrects a label. Same geometry, new prior."""
    if label in food_classes():
        return grams_from_area(label, area_px, px_per_mm)
    area_mm2 = area_px / (px_per_mm * px_per_mm)
    grams = area_mm2 * GENERIC_HEIGHT_MM / 1000.0 * GENERIC_DENSITY
    return grams, grams * 0.7, grams * 1.3
