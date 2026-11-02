"""Validate profile pictures and rewrite them, which drops location data and hidden content."""
import io
import uuid

from django.core.files.base import ContentFile
from PIL import Image, ImageOps, UnidentifiedImageError
from rest_framework.exceptions import ValidationError

MAX_PHOTO_BYTES = 5 * 1024 * 1024
MAX_PHOTO_SIDE = 1024
ALLOWED_FORMATS = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}


def save_user_photo(user, upload):
    if upload is None:
        raise ValidationError({"photo": "Choose a picture to upload."})
    if upload.size > MAX_PHOTO_BYTES:
        raise ValidationError({"photo": "Picture must be 5 MB or smaller."})
    try:
        image = Image.open(upload)
        image_format = image.format
        image.verify()
        upload.seek(0)
        image = Image.open(upload)
        image = ImageOps.exif_transpose(image)
        image.thumbnail((MAX_PHOTO_SIDE, MAX_PHOTO_SIDE))
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise ValidationError({"photo": "That file isn't a valid picture."}) from exc
    if image_format not in ALLOWED_FORMATS:
        raise ValidationError({"photo": "Use a JPEG, PNG or WebP picture."})

    if image_format == "JPEG" and image.mode != "RGB":
        image = image.convert("RGB")
    buffer = io.BytesIO()
    image.save(buffer, format=image_format)

    remove_user_photo(user)
    user.photo.save(
        f"{uuid.uuid4().hex}.{ALLOWED_FORMATS[image_format]}",
        ContentFile(buffer.getvalue()),
        save=True,
    )


def remove_user_photo(user):
    if user.photo:
        user.photo.delete(save=False)
        user.photo = None
        user.save(update_fields=["photo"])
