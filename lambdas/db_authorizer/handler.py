"""HTTP API Lambda authorizer for the ConfluxDB data API.
Validates the client shared secret and source IP before requests reach the data Lambda."""

import json
import logging
import os
from typing import Any, Dict, Optional

import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

SECRETS_CLIENT = boto3.client("secretsmanager")

API_KEY_SECRET_ARN = os.environ["API_KEY_SECRET_ARN"]
ALLOWED_SOURCE_IPS = {ip.strip() for ip in os.environ.get("ALLOWED_SOURCE_IPS", "").split(",") if ip.strip()}
API_KEY_HEADER = "x-api-key"

_CACHED_SECRET: Optional[str] = None


def _get_expected_api_key() -> str:
    global _CACHED_SECRET
    if _CACHED_SECRET is None:
        try:
            response = SECRETS_CLIENT.get_secret_value(SecretId=API_KEY_SECRET_ARN)
        except ClientError:
            LOGGER.exception("Failed to read API key secret %s", API_KEY_SECRET_ARN)
            raise

        secret_string = response.get("SecretString")
        if secret_string is None:
            raise ValueError("API key secret is empty")

        _CACHED_SECRET = secret_string
    return _CACHED_SECRET


def _is_ip_allowed(source_ip: Optional[str]) -> bool:
    if not ALLOWED_SOURCE_IPS:
        return True
    if not source_ip:
        return False
    return source_ip in ALLOWED_SOURCE_IPS


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    LOGGER.debug("Authorizer event: %s", json.dumps(event))
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items() if k}
    source_ip = (event.get("requestContext", {}).get("http", {}) or {}).get("sourceIp")

    if not _is_ip_allowed(source_ip):
        LOGGER.warning("Authorizer rejection: source IP %s not allow-listed", source_ip)
        return {
            "isAuthorized": False,
            "context": {"reason": "ip_not_allowed"},
        }

    provided_key = headers.get(API_KEY_HEADER)
    expected_key = _get_expected_api_key()

    if not provided_key or provided_key != expected_key:
        LOGGER.warning("Authorizer rejection: invalid or missing API key")
        return {
            "isAuthorized": False,
            "context": {"reason": "invalid_api_key"},
        }

    return {
        "isAuthorized": True,
        "context": {
            "sourceIp": source_ip or "unknown",
        },
    }
