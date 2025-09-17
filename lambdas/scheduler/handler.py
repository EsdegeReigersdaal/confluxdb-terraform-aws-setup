import json
import logging
import os
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

ECS_CLUSTER = os.environ["ECS_CLUSTER"]
ECS_SERVICE = os.environ["ECS_SERVICE"]
ECS_DESIRED_COUNT = int(os.environ["ECS_DESIRED_COUNT"])
RDS_INSTANCE_ID = os.environ["RDS_INSTANCE_ID"]

ECS_CLIENT = boto3.client("ecs")
RDS_CLIENT = boto3.client("rds")


def _update_ecs_desired_count(desired_count: int) -> None:
    try:
        ECS_CLIENT.update_service(
            cluster=ECS_CLUSTER,
            service=ECS_SERVICE,
            desiredCount=desired_count,
            forceNewDeployment=False,
        )
        LOGGER.info("Set ECS service %s desired count to %s", ECS_SERVICE, desired_count)
    except ClientError:
        LOGGER.exception("Failed to update ECS service desired count")
        raise


def _stop_db_instance() -> None:
    try:
        RDS_CLIENT.stop_db_instance(DBInstanceIdentifier=RDS_INSTANCE_ID)
        LOGGER.info("Stopping RDS instance %s", RDS_INSTANCE_ID)
    except ClientError as exc:
        if exc.response["Error"].get("Code") in {"InvalidDBInstanceState", "DBInstanceNotFound"}:
            LOGGER.warning("Stop DB instance skipped: %s", exc)
            return
        LOGGER.exception("Failed to stop RDS instance")
        raise


def _start_db_instance() -> None:
    try:
        RDS_CLIENT.start_db_instance(DBInstanceIdentifier=RDS_INSTANCE_ID)
        LOGGER.info("Starting RDS instance %s", RDS_INSTANCE_ID)
    except ClientError as exc:
        if exc.response["Error"].get("Code") in {"InvalidDBInstanceState", "DBInstanceNotFound"}:
            LOGGER.warning("Start DB instance skipped: %s", exc)
            return
        LOGGER.exception("Failed to start RDS instance")
        raise


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    LOGGER.info("Received event: %s", json.dumps(event))
    action = event.get("action")
    if action not in {"start", "stop"}:
        raise ValueError(f"Unsupported action: {action}")

    if action == "stop":
        _update_ecs_desired_count(0)
        _stop_db_instance()
    else:
        _update_ecs_desired_count(ECS_DESIRED_COUNT)
        _start_db_instance()

    return {"status": "ok", "action": action}
