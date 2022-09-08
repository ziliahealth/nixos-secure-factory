"""A set of common parameterizable options to be
    used throughout the various nsf cli applications.
"""

from __future__ import annotations

from typing import Any, Optional

import click

from nsf_factory_common_install.click.error import CliError
from nsf_factory_common_install.repo_project import (
    DeviceCfgRepoInstance,
    DeviceInstanceUnspecifiedError,
    ProjectRepo,
    ProjectRepoDevice,
)
from nsf_factory_common_install.types_factory import FactoryMissingFieldsError

from ._auto_complete import list_ac_available_device_ids


def cli_default_user_option() -> Any:
    """An option to specify a user id.

    See companion `ensure_user_id_or_user_factory_user_id`
    to get a final value.
    """
    return click.option(
        "--user",
        "-u",
        "user_id",
        type=str,
        default=None,
        help=("The id of the default user operation will " "fallback to if not provided otherwise."),
        envvar="NSF_CLI_DEFAULT_USER_ID",
        # shell_complete=list_ac_available_user_id
    )


def cli_default_device_option() -> Any:
    return click.option(
        "--device",
        "-d",
        "device_id",
        type=str,
        default=None,
        help=(
            "The id of the default device to be used by this cli's "
            "commands as a fallback when not provided otherwise."
        ),
        envvar="NSF_CLI_DEFAULT_DEVICE_ID",
        shell_complete=list_ac_available_device_ids,
    )


def ensure_user_id_or_user_factory_user_id(user_id: Optional[str], project: ProjectRepo) -> str:
    """Companion to `cli_default_user_option`.

    Raises:
        CliError: When couldn't retrieve the fallback
        user id.
    """
    if user_id is not None:
        return user_id

    try:
        return project.factory.user_id
    except FactoryMissingFieldsError as e:
        raise CliError(f"Cannot retrieve user id because: {str(e)}")


def ensure_project_repo_device_by_id_or_current(device_id: Optional[str], project: ProjectRepo) -> ProjectRepoDevice:
    """Companion to `cli_default_device_option`.

    Raises:
        CliError: When couldn't retrieve the device for
            some reason.
    """
    if device_id is None:
        return project.current_device

    return project.get_device_by_id(device_id)


def ensure_device_cfg_repo_device_by_id_or_current(
    device_id: Optional[str], project: ProjectRepo
) -> DeviceCfgRepoInstance:
    """Companion to `cli_default_device_option`.

    Raises:
        CliError: When couldn't retrieve the device
            for some reason.
    """
    device = ensure_project_repo_device_by_id_or_current(device_id, project)

    try:
        return device.get_instance_from_default_repo()
    except DeviceInstanceUnspecifiedError as e:
        raise CliError(str(e)) from e
