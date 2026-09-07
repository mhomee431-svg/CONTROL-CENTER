"""AWS Secrets Manager hydration helper.

Loads a single JSON secret from AWS Secrets Manager and exports its keys as
environment variables using the container's IAM role (default credential
chain — no static keys in source, images, or git).

Primary use is the container entrypoint:

    USE_AWS_SECRETS=true
    AWS_REGION=ap-south-1
    AWS_SECRETS_SECRET_ID=hyperlocal/production

Command::

    python -m app.core.aws_secrets --export   # shell-safe `export K='v'` lines
    python -m app.core.aws_secrets --list      # only key names (for audit)

The module never logs secret values and always shell-quotes exports so special
characters (`$`, backticks, quotes, newlines) cannot break out.

Programmatic use::

    from app.core.aws_secrets import hydrate_os_environ
    hydrate_os_environ()          # mutates os.environ in place
"""
from __future__ import annotations

import os
import shlex
import sys

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.aws_secrets")


def _boto3_client():
    import boto3

    return boto3.client(
        "secretsmanager",
        region_name=(
            settings.AWS_SECRETS_REGION
            or os.getenv("AWS_REGION")
            or settings.AWS_REGION
        ),
    )


def resolve_secret_id() -> str:
    """Return the Secrets Manager secret name/id to load.

    Resolution order:
        1. AWS_SECRETS_SECRET_ID            — exact secret name/ARN
        2. AWS_SECRETS_PREFIX/<ENVIRONMENT>  — e.g. `hyperlocal/production`
        Raises if none configured.
    """
    secret_id = (
        os.getenv("AWS_SECRETS_SECRET_ID")
        or os.getenv("AWS_SECRETS_ID")
        or settings.AWS_SECRETS_SECRET_ID
    )
    if secret_id:
        return secret_id

    prefix = os.getenv("AWS_SECRETS_PREFIX") or settings.AWS_SECRETS_PREFIX
    environment = os.getenv("ENVIRONMENT") or os.getenv("HYPERLOCAL_ENV") or settings.ENVIRONMENT
    if prefix:
        return f"{prefix.rstrip('/')}/{environment}"

    raise RuntimeError(
        "AWS Secrets hydration requested but no secret is configured. "
        "Set AWS_SECRETS_SECRET_ID or AWS_SECRETS_PREFIX."
    )


def fetch_secret(secret_id: str) -> dict:
    """Fetch a secret, decrypt it via KMS, and parse the JSON blob."""
    client = _boto3_client()
    try:
        response = client.get_secret_value(SecretId=secret_id)
    except Exception as exc:  # noqa: BLE001
        logger.error("AWS Secrets Manager get failed for '%s'", secret_id)
        raise RuntimeError(f"Failed to read AWS secret '{secret_id}'") from exc

    raw = response.get("SecretString")
    if raw is None:
        raise RuntimeError(
            f"AWS secret '{secret_id}' has no SecretString (binary secrets are unsupported)."
        )

    import json

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:  # noqa: BLE001
        raise RuntimeError(
            f"AWS secret '{secret_id}' is not a valid JSON object."
        ) from exc

    if not isinstance(payload, dict):
        raise RuntimeError(f"AWS secret '{secret_id}' must be a flat JSON object.")
    return payload


def hydrate_os_environ(secret_id: str | None = None) -> dict:
    """Fetch a secret and copy every key into ``os.environ``.

    Only keys that are currently NOT set are overwritten, so explicit
    environment variables (e.g. injected by ECS as non-secret config) always
    win over the secret bundle. Returns the resolved secret id.
    """
    resolved = secret_id or resolve_secret_id()
    payload = fetch_secret(resolved)

    applied = []
    for key, value in payload.items():
        key_ = str(key).strip().upper()
        if not key_:
            continue
        if os.environ.get(key_):
            logger.debug("Env key '%s' already set — kept", key_)
            continue
        os.environ[key_] = str(value)
        applied.append(key_)

    logger.info(
        "Hydrated %d env var(s) from AWS secret '%s' (names: %s)",
        len(applied),
        resolved,
        ", ".join(sorted(applied)) or "none",
    )
    return resolved


def export_as_shell(secret_id: str | None = None) -> str:
    """Return Shell-portable ``export KEY='value'`` lines for the entrypoint."""
    resolved = secret_id or resolve_secret_id()
    payload = fetch_secret(resolved)

    lines = []
    for key, value in payload.items():
        key_ = str(key).strip().upper()
        if not key_:
            continue
        # shlex.quote yields a single-quoted value safe for `eval` in POSIX sh.
        lines.append(f"export {key_}={shlex.quote(str(value))}")
    return "\n".join(lines) + ("\n" if lines else "")


def main(argv: list[str] | None = None) -> int:
    argv = list(argv if argv is not None else sys.argv[1:])

    if "--export" in argv:
        sys.stdout.write(export_as_shell())
        return 0

    if "--export-programmatic" in argv:
        # In-process hydration (sets os.environ) + prints applied key names only.
        hydrate_os_environ()
        return 0

    if "--list" in argv:
        secret_id = resolve_secret_id()
        payload = fetch_secret(secret_id)
        sys.stdout.write("\n".join(sorted(payload.keys())) + "\n")
        return 0

    sys.stderr.write(
        "usage: python -m app.core.aws_secrets {--export|--list|--export-programmatic}\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())