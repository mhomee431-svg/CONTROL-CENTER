"""Image processing and validation utilities.

Provides:
- Image dimension validation
- Image optimization/compression
- Thumbnail generation
- Metadata extraction
- Image integrity verification
"""
import io
import logging
from typing import Optional, Tuple

from app.core.config import settings

logger = logging.getLogger("app.core.image_processing")

# Image size limits
MAX_IMAGE_WIDTH = 4096
MAX_IMAGE_HEIGHT = 4096
MIN_IMAGE_WIDTH = 100
MIN_IMAGE_HEIGHT = 100

# Thumbnail sizes
THUMBNAIL_SIZES = {
    "small": (150, 150),
    "medium": (300, 300),
    "large": (600, 600),
}

# Quality settings
JPEG_QUALITY = 85
WEBP_QUALITY = 80


class ImageValidationError(ValueError):
    """Raised when an image fails validation."""


def validate_image_dimensions(
    width: int,
    height: int,
    *,
    max_width: int = MAX_IMAGE_WIDTH,
    max_height: int = MAX_IMAGE_HEIGHT,
    min_width: int = MIN_IMAGE_WIDTH,
    min_height: int = MIN_IMAGE_HEIGHT,
) -> None:
    """Validate image dimensions are within acceptable bounds.
    
    Raises:
        ImageValidationError: If dimensions are invalid
    """
    if width < min_width or height < min_height:
        raise ImageValidationError(
            f"Image too small: {width}x{height} (minimum {min_width}x{min_height})"
        )
    
    if width > max_width or height > max_height:
        raise ImageValidationError(
            f"Image too large: {width}x{height} (maximum {max_width}x{max_height})"
        )


def get_image_info(content: bytes) -> Optional[dict]:
    """Extract basic image information from bytes.
    
    Returns:
        dict with width, height, format, size or None if not a valid image
    """
    try:
        from PIL import Image
        
        img = Image.open(io.BytesIO(content))
        width, height = img.size
        
        return {
            "width": width,
            "height": height,
            "format": img.format,
            "mode": img.mode,
            "size_bytes": len(content),
        }
    except Exception as exc:
        logger.debug("Could not extract image info: %s", exc)
        return None


def verify_image_integrity(content: bytes, content_type: str) -> bool:
    """Verify that image bytes are a valid, complete image.
    
    Args:
        content: Raw image bytes
        content_type: Expected MIME type
    
    Returns:
        True if image is valid
    """
    try:
        from PIL import Image
        
        img = Image.open(io.BytesIO(content))
        img.verify()
        
        img = Image.open(io.BytesIO(content))
        img.load()
        
        return True
        
    except Exception as exc:
        logger.warning("Image integrity check failed: %s", exc)
        return False


def optimize_image(
    content: bytes,
    content_type: str,
    *,
    max_width: int = 1920,
    max_height: int = 1920,
    quality: int = JPEG_QUALITY,
) -> Tuple[bytes, str]:
    """Optimize an image by resizing and compressing.
    
    Args:
        content: Raw image bytes
        content_type: MIME type of the image
        max_width: Maximum width (aspect ratio preserved)
        max_height: Maximum height (aspect ratio preserved)
        quality: Compression quality (1-100)
    
    Returns:
        Tuple of (optimized_bytes, content_type)
    """
    try:
        from PIL import Image
        
        img = Image.open(io.BytesIO(content))
        original_size = img.size
        
        # Convert RGBA to RGB for JPEG
        if content_type == "image/jpeg" and img.mode in ("RGBA", "P"):
            img = img.convert("RGB")
        
        # Resize if needed (preserving aspect ratio)
        if img.width > max_width or img.height > max_height:
            img.thumbnail((max_width, max_height), Image.Resampling.LANCZOS)
            logger.info("Resized image from %s to %s", original_size, img.size)
        
        # Save optimized image
        output = io.BytesIO()
        
        if content_type == "image/jpeg":
            img.save(output, format="JPEG", quality=quality, optimize=True)
        elif content_type == "image/png":
            img.save(output, format="PNG", optimize=True)
        elif content_type == "image/webp":
            img.save(output, format="WEBP", quality=WEBP_QUALITY, method=6)
        else:
            return content, content_type
        
        optimized = output.getvalue()
        
        # Only use optimized if it's actually smaller
        if len(optimized) < len(content):
            logger.info(
                "Optimized image: %d bytes -> %d bytes (%.1f%% reduction)",
                len(content), len(optimized),
                (1 - len(optimized) / len(content)) * 100
            )
            return optimized, content_type
        
        return content, content_type
        
    except ImportError:
        logger.warning("Pillow not installed, skipping image optimization")
        return content, content_type
    except Exception as exc:
        logger.error("Image optimization failed: %s", exc)
        return content, content_type


def generate_thumbnail(
    content: bytes,
    content_type: str,
    size: str = "medium",
) -> Optional[Tuple[bytes, str]]:
    """Generate a thumbnail from an image.
    
    Args:
        content: Raw image bytes
        content_type: MIME type
        size: Thumbnail size key ("small", "medium", "large")
    
    Returns:
        Tuple of (thumbnail_bytes, content_type) or None on failure
    """
    try:
        from PIL import Image
        
        if size not in THUMBNAIL_SIZES:
            logger.warning("Unknown thumbnail size: %s", size)
            return None
        
        target_width, target_height = THUMBNAIL_SIZES[size]
        
        img = Image.open(io.BytesIO(content))
        
        if content_type == "image/jpeg" and img.mode in ("RGBA", "P"):
            img = img.convert("RGB")
        
        img.thumbnail((target_width, target_height), Image.Resampling.LANCZOS)
        
        output = io.BytesIO()
        
        if content_type == "image/jpeg":
            img.save(output, format="JPEG", quality=75, optimize=True)
        elif content_type == "image/png":
            img.save(output, format="PNG", optimize=True)
        elif content_type == "image/webp":
            img.save(output, format="WEBP", quality=70)
        else:
            return None
        
        return output.getvalue(), content_type
        
    except ImportError:
        logger.warning("Pillow not installed, cannot generate thumbnail")
        return None
    except Exception as exc:
        logger.error("Thumbnail generation failed: %s", exc)
        return None


def strip_metadata(content: bytes, content_type: str) -> Tuple[bytes, str]:
    """Strip EXIF and other metadata from images for privacy.
    
    Args:
        content: Raw image bytes
        content_type: MIME type
    
    Returns:
        Tuple of (clean_bytes, content_type)
    """
    try:
        from PIL import Image
        
        img = Image.open(io.BytesIO(content))
        
        data = list(img.getdata())
        clean_img = Image.new(img.mode, img.size)
        clean_img.putdata(data)
        
        output = io.BytesIO()
        
        if content_type == "image/jpeg":
            clean_img.save(output, format="JPEG", quality=JPEG_QUALITY)
        elif content_type == "image/png":
            clean_img.save(output, format="PNG")
        elif content_type == "image/webp":
            clean_img.save(output, format="WEBP", quality=WEBP_QUALITY)
        else:
            return content, content_type
        
        return output.getvalue(), content_type
        
    except ImportError:
        return content, content_type
    except Exception as exc:
        logger.error("Metadata stripping failed: %s", exc)
        return content, content_type