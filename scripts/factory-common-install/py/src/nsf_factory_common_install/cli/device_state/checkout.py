from __future__ import annotations

import sys
import textwrap
from functools import update_wrapper
from typing import Optional

import click

from nsf_factory_common_install.click.error import CliError, CliUsageError, echo_warning
from nsf_factory_common_install.file_device_state import format_plain_device_state_as_yaml_str
from nsf_factory_common_install.prompt import prompt_for_user_approval

from .._auto_complete import list_ac_available_device_ids
from .._device_set import MatchNotUniqueError, match_unique_device_by_id, match_unique_device_by_serial_number
from ._ctx import CliCtx, pass_cli_ctx


def find_device_id_from_sn(checkout_fn):
    def checkout_device_from_id(*args, **kwargs):
        device_serial_number = kwargs["device_sn"]
        if device_serial_number is not None:
            ctx = args[0]
            device_repos = ctx.checkout_device_repo
            device = match_unique_device_by_serial_number(device_serial_number, device_repos.iter_instances())
            kwargs["device_id"] = device.id
        return checkout_fn(*args, **kwargs)

    return update_wrapper(checkout_device_from_id, checkout_fn)


@click.command()
@click.argument(  # type: ignore
    "device-id",
    shell_complete=list_ac_available_device_ids,
    required=False,
    default=None,
)
@click.option("--serial-number", "-sn", "device_sn", help="Checkout device per Serial number")
@pass_cli_ctx
@find_device_id_from_sn
def checkout(ctx: CliCtx, device_id: Optional[str], device_sn: Optional[str]) -> None:
    """Checkout a particular device state.

    DEVICE_ID: The device id when not already specified via the
    a top level '-d'/'--device-id' option.

    When checking out a a device state, the checked-out device
    becomes the default device and it becomes possible to
    perform non permanent / local operation on its state file
    which won't be version controlled.
    """
    if ctx.checkout_target_file is None or ctx.checkout_device_repo is None:
        raise CliError("Operation not allowed in the current context.")

    if device_id is None:
        if ctx.explicit_device_id is None:
            raise CliUsageError('Missing argument "DEVICE_ID".')

        device_id = ctx.explicit_device_id

    if device_id != ctx.device.id:
        echo_warning(
            f"Mismatching / ambiguous device specifiers: '{device_id}', "
            f"'{ctx.device.id}'.\n"
            'Fix by removing either the "DEVICE_ID" argument or the '
            "top level '-d'/'--device-id' option.\n"
            f"Using the \"DEVICE_ID\" argument: '{device_id}'."
        )
        click.echo("")  # Add space before following title.

    assert device_id is not None and isinstance(device_id, str)

    device_repo = ctx.checkout_device_repo

    try:
        matched_device = match_unique_device_by_id(device_id, device_repo.iter_instances())
    except MatchNotUniqueError as e:
        raise CliError(str(e)) from e

    click.echo(("Checking out device state\n" "=========================\n").format())

    device_state = matched_device.state_file.load_plain()

    device_state_yaml_str = "".join(format_plain_device_state_as_yaml_str(device_state))
    click.echo(
        textwrap.dedent(
            """\
        Device info
        -----------

        {}\
    """
        ).format(device_state_yaml_str)
    )

    if not prompt_for_user_approval():
        sys.exit(1)

    target_file = ctx.checkout_target_file
    assert target_file is not None
    click.echo("Writing device configuration to '{}'.".format(target_file.filename))
    target_file.dump_plain(device_state)
    click.echo("Current device is now set to '{}'.".format(matched_device.id))
