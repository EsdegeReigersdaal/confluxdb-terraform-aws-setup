"""Lambda handler for the ConfluxDB data API.
Fetches database credentials from Secrets Manager so application code can
establish secure connections to the private RDS instance through the proxy
and serve filtered results to API Gateway callers."""

from __future__ import annotations

import json
import logging
import os
import re
import ssl
from datetime import date, datetime, time
from typing import Any, Dict, Iterable, List, Optional

import boto3
import pg8000
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

SECRETS_CLIENT = boto3.client("secretsmanager")

DB_SECRET_ARN = os.environ["DB_SECRET_ARN"]
API_KEY_SECRET_ARN = os.environ["API_KEY_SECRET_ARN"]
DB_HOST = os.environ["DB_HOST"]
DB_NAME = os.environ["DB_NAME"]
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
RESOURCE_PREFIX = os.environ.get("RESOURCE_PREFIX", "public/diensten").strip("/")
ALLOWED_SOURCE_IPS = {ip.strip() for ip in os.environ.get("ALLOWED_SOURCE_IPS", "").split(",") if ip.strip()}
RESOURCE_HEADER = "x-resource-path"
API_KEY_HEADER = "x-api-key"

_PREFIX_PARTS = RESOURCE_PREFIX.split("/", 1)
if len(_PREFIX_PARTS) != 2:
    raise ValueError("RESOURCE_PREFIX must include schema and table segments separated by '/'")
RESOURCE_SCHEMA, RESOURCE_TABLE = _PREFIX_PARTS

_SSL_CONTEXT = ssl.create_default_context()
_DB_CREDENTIALS: Optional[Dict[str, Any]] = None
_API_KEY_VALUE: Optional[str] = None

_VALID_IDENTIFIER = re.compile(r"^[A-Za-z0-9_-]+$")
_VALID_OBJECT = re.compile(r"^[A-Za-z0-9_]+$")


def _normalise_headers(headers: Dict[str, Any]) -> Dict[str, str]:
    return {str(k).lower(): v for k, v in headers.items() if k}


def _get_secret_payload(secret_arn: str) -> Any:
    try:
        response = SECRETS_CLIENT.get_secret_value(SecretId=secret_arn)
    except ClientError:
        LOGGER.exception("Unable to read secret %s", secret_arn)
        raise

    secret_string = response.get("SecretString")
    if secret_string is None:
        raise ValueError(f"SecretString missing from secret {secret_arn}")

    try:
        return json.loads(secret_string)
    except json.JSONDecodeError:
        return secret_string


def _get_db_credentials() -> Dict[str, Any]:
    global _DB_CREDENTIALS
    if _DB_CREDENTIALS is None:
        payload = _get_secret_payload(DB_SECRET_ARN)
        if not isinstance(payload, dict):
            raise ValueError("Database secret payload must be a JSON object")
        _DB_CREDENTIALS = payload
    return _DB_CREDENTIALS


def _get_expected_api_key() -> str:
    global _API_KEY_VALUE
    if _API_KEY_VALUE is None:
        payload = _get_secret_payload(API_KEY_SECRET_ARN)
        if isinstance(payload, dict):
            candidate = payload.get("api_key") or payload.get("value")
        else:
            candidate = str(payload) if payload else None
        if not candidate:
            raise ValueError("API key secret is empty or missing 'api_key' field")
        _API_KEY_VALUE = str(candidate)
    return _API_KEY_VALUE


def _serialise_value(value: Any) -> Any:
    if isinstance(value, (datetime, date, time)):
        return value.isoformat()
    return value


def _run_query(identifier: Optional[str]) -> List[Dict[str, Any]]:
    creds = _get_db_credentials()
    conn = pg8000.connect(
        user=creds.get("username"),
        password=creds.get("password"),
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        ssl_context=_SSL_CONTEXT,
    )
    cursor = conn.cursor()
    try:
        query = f"SELECT employee, date, starttime, endtime, company FROM {RESOURCE_SCHEMA}.{RESOURCE_TABLE}"
        params: Iterable[Any] = ()
        if identifier and identifier != "*":
            query += " WHERE company = %s"
            params = (identifier,)
        query += " ORDER BY date, starttime"
        cursor.execute(query, params)
        columns = [desc[0] for desc in cursor.description]
        return [dict(zip(columns, (_serialise_value(v) for v in row))) for row in cursor.fetchall()]
    finally:
        cursor.close()
        conn.close()


def _is_ip_allowed(source_ip: Optional[str]) -> bool:
    if not ALLOWED_SOURCE_IPS:
        return True
    if not source_ip:
        return False
    return source_ip in ALLOWED_SOURCE_IPS


def _resolve_resource_path(raw_header: Optional[str]) -> Optional[str]:
    if raw_header is None:
        raise ValueError("Missing required resource header")
    candidate = raw_header.strip().strip("/")
    if not candidate:
        raise ValueError("Empty resource path")
    if not candidate.startswith(RESOURCE_PREFIX):
        candidate = f"{RESOURCE_PREFIX}/{candidate}".strip("/")
    parts = candidate.split("/")
    if len(parts) < 2:
        raise ValueError("Resource path must include schema and table")
    schema, table, *rest = parts
    if schema != RESOURCE_SCHEMA or table != RESOURCE_TABLE:
        raise ValueError("Resource path targets an unsupported schema/table")
    if rest:
        if len(rest) > 1:
            raise ValueError("Resource path may include at most one identifier segment")
        identifier = rest[0]
        if identifier != "*" and not _VALID_IDENTIFIER.fullmatch(identifier):
            raise ValueError("Identifier contains invalid characters")
        return identifier
    return None


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    try:
        headers = _normalise_headers(event.get("headers", {}))
        source_ip = (event.get("requestContext", {}).get("http", {}) or {}).get("sourceIp")

        if not _is_ip_allowed(source_ip):
            LOGGER.warning("Rejected request from IP %s", source_ip)
            return {"statusCode": 403, "body": json.dumps({"message": "Forbidden"})}

        provided_api_key = headers.get(API_KEY_HEADER)
        expected_api_key = _get_expected_api_key()
        if not provided_api_key or provided_api_key != expected_api_key:
            LOGGER.warning("Rejected request due to invalid API key")
            return {"statusCode": 401, "body": json.dumps({"message": "Unauthorized"})}

        identifier = _resolve_resource_path(headers.get(RESOURCE_HEADER))
        rows = _run_query(identifier)

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"results": rows, "count": len(rows)}),
        }
    except ValueError as exc:
        LOGGER.warning("Bad request: %s", exc)
        return {"statusCode": 400, "body": json.dumps({"message": str(exc)})}
    except Exception:
        LOGGER.exception("Unhandled error in data API")
        return {
            "statusCode": 500,
            "body": json.dumps({"message": "Internal server error"}),
        }
