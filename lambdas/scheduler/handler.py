import json
import logging
import os
from typing import Any, Dict, Iterable, List

import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

ECS_CLUSTER = os.environ["ECS_CLUSTER"]
ECS_AGENT_SERVICE = os.environ["ECS_AGENT_SERVICE"]
ECS_AGENT_DESIRED_COUNT = int(os.environ["ECS_AGENT_DESIRED_COUNT"])
ECS_CODE_SERVICE_PREFIX = os.environ.get("ECS_CODE_SERVICE_PREFIX", "")
ECS_CODE_SERVICE_DESIRED_COUNT = int(os.environ.get("ECS_CODE_SERVICE_DESIRED_COUNT", "1"))
RDS_INSTANCE_ID = os.environ["RDS_INSTANCE_ID"]

ECS_CLIENT = boto3.client("ecs")
RDS_CLIENT = boto3.client("rds")


def _update_service(service_name: str, desired_count: int) -> None:
    try:
        ECS_CLIENT.update_service(
            cluster=ECS_CLUSTER,
            service=service_name,
            desiredCount=desired_count,
            forceNewDeployment=False,
        )
        LOGGER.info("Set ECS service %s desired count to %s", service_name, desired_count)
    except ClientError:
        LOGGER.exception("Failed to update ECS service %s", service_name)
        raise


def _list_candidate_code_services() -> Iterable[str]:
    paginator = ECS_CLIENT.get_paginator("list_services")
    service_arns: List[str] = []
    for page in paginator.paginate(cluster=ECS_CLUSTER):
        service_arns.extend(page.get("serviceArns", []))

    if not service_arns:
        return []

    def _service_matches(name: str) -> bool:
        if name == ECS_AGENT_SERVICE:
            return False
        if ECS_CODE_SERVICE_PREFIX and not name.startswith(ECS_CODE_SERVICE_PREFIX):
            return False
        return True

    candidates: List[str] = []
    for i in range(0, len(service_arns), 10):
        batch = service_arns[i : i + 10]
        response = ECS_CLIENT.describe_services(cluster=ECS_CLUSTER, services=batch)
        for service in response.get("services", []):
            name = service.get("serviceName")
            if name and _service_matches(name):
                candidates.append(name)
    return candidates


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
        _update_service(ECS_AGENT_SERVICE, 0)
        for service_name in _list_candidate_code_services():
            _update_service(service_name, 0)
        _stop_db_instance()
    else:
        _update_service(ECS_AGENT_SERVICE, ECS_AGENT_DESIRED_COUNT)
        for service_name in _list_candidate_code_services():
            _update_service(service_name, ECS_CODE_SERVICE_DESIRED_COUNT)
        _start_db_instance()

    return {"status": "ok", "action": action}
