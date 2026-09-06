"""Input validation utilities for Pydantic schemas.

Provides validators and types for common input validation patterns.
"""
import re
from typing import Optional

from pydantic import BaseModel, field_validator


# Common patterns
PHONE_PATTERN = re.compile(r"^\+?[1-9]\d{1,14}$")  # E.164
EMAIL_PATTERN = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
SLUG_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
BARCODE_PATTERN = re.compile(r"^\d{8,14}$")  # EAN-8, EAN-13, UPC-A
SAFE_STRING_PATTERN = re.compile(r"^[\w\s\-.,!?()[\]{}'\":;/@#$%&*+=~`|\\<>]*$")

# Length constraints
MAX_NAME_LENGTH = 255
MAX_DESCRIPTION_LENGTH = 5000
MAX_TEXT_LENGTH = 10000
MAX_QUERY_LENGTH = 200


def validate_phone(cls, v: Optional[str]) -> Optional[str]:
    """Validate phone number format (E.164)."""
    if v is None:
        return v
    
    # Remove spaces and dashes
    cleaned = re.sub(r"[\s\-]", "", v)
    
    if not PHONE_PATTERN.match(cleaned):
        raise ValueError("Invalid phone number format")
    
    return cleaned


def validate_email(cls, v: Optional[str]) -> Optional[str]:
    """Validate email format."""
    if v is None:
        return v
    
    v = v.strip().lower()
    
    if not EMAIL_PATTERN.match(v):
        raise ValueError("Invalid email format")
    
    return v


def validate_safe_string(cls, v: Optional[str]) -> Optional[str]:
    """Validate that a string doesn't contain dangerous characters."""
    if v is None:
        return v
    
    # Remove null bytes
    v = v.replace("\x00", "")
    
    # Remove control characters except newlines and tabs
    v = "".join(
        char for char in v
        if char == "\n" or char == "\r" or char == "\t" or (ord(char) >= 32)
    )
    
    return v.strip()


def validate_slug(cls, v: Optional[str]) -> Optional[str]:
    """Validate slug format."""
    if v is None:
        return v
    
    v = v.strip().lower()
    
    if not SLUG_PATTERN.match(v):
        raise ValueError("Invalid slug format (use lowercase letters, numbers, and hyphens)")
    
    return v


def validate_barcode(cls, v: Optional[str]) -> Optional[str]:
    """Validate barcode format."""
    if v is None:
        return v
    
    v = v.strip()
    
    if not BARCODE_PATTERN.match(v):
        raise ValueError("Invalid barcode format")
    
    return v


def validate_search_query(cls, v: Optional[str]) -> Optional[str]:
    """Validate and sanitize a search query."""
    if v is None:
        return v
    
    v = v.strip()
    
    if len(v) > MAX_QUERY_LENGTH:
        raise ValueError(f"Search query too long (max {MAX_QUERY_LENGTH} characters)")
    
    # Remove dangerous characters
    v = re.sub(r"[;{}()\[\]<>]", "", v)
    
    return v if v else None


class SafeStringMixin:
    """Mixin for Pydantic models with safe string validation."""
    
    @field_validator("*", mode="before")
    @classmethod
    def sanitize_strings(cls, v):
        """Sanitize all string fields."""
        if isinstance(v, str):
            # Remove null bytes
            v = v.replace("\x00", "")
            # Remove control characters except newlines and tabs
            v = "".join(
                char for char in v
                if char == "\n" or char == "\r" or char == "\t" or (ord(char) >= 32)
            )
            return v.strip()
        return v


class SearchQuery(BaseModel):
    """Validated search query."""
    
    q: Optional[str] = None
    
    @field_validator("q")
    @classmethod
    def validate_query(cls, v):
        return validate_search_query(cls, v)


class PhoneNumber(BaseModel):
    """Validated phone number."""
    
    phone: str
    
    @field_validator("phone")
    @classmethod
    def validate_phone_field(cls, v):
        return validate_phone(cls, v)


class EmailAddress(BaseModel):
    """Validated email address."""
    
    email: str
    
    @field_validator("email")
    @classmethod
    def validate_email_field(cls, v):
        return validate_email(cls, v)
