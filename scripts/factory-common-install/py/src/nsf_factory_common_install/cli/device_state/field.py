from __future__ import annotations

from pathlib import Path
from typing import List

import click
import yaml

from nsf_factory_common_install.click.error import CliError
from nsf_factory_common_install.file_device_state import DeviceStateFileAccessError, DeviceStatePlainT

from ._ctx import CliCtx, pass_cli_ctx
from ._field_ac import (
    list_ac_editable_field_names,
    list_ac_field_values,
    list_ac_readable_field_names,
    list_ac_removable_field_names,
)
from ._fields_schema import FieldValueInvalidError, get_field_schema


@click.group()
def field() -> None:
    pass


@field.command(name="ls")
@pass_cli_ctx
def _ls(ctx: CliCtx) -> None:
    try:
        state_d = ctx.rw_target_file.load_plain()
    except DeviceStateFileAccessError as e:
        raise CliError(str(e)) from e

    for k in state_d.keys():
        click.echo(k)


def _confirm_create_missing_state_file(filename: Path) -> bool:
    return click.confirm(
        (f"State file '{filename}' does not exit.\n" "Do you want to create it?"), err=True, abort=True
    )


@field.command(name="set")
@click.option(
    "-y", "--yes", "prompt_auto_yes", is_flag=True, default=False, help="Systematically answer yes when prompted."
)
@click.option(
    "--yes-field",
    "prompt_auto_yes_create_field",
    is_flag=True,
    default=False,
    help=("Systematically answer yes when " "prompted to create missing fields."),
)
@click.argument("field-name", shell_complete=list_ac_editable_field_names)  # type: ignore
@click.argument("field-value", nargs=-1, shell_complete=list_ac_field_values)  # type: ignore
@pass_cli_ctx
def _set(
    ctx: CliCtx, field_name: str, field_value: List[str], prompt_auto_yes: bool, prompt_auto_yes_create_field: bool
) -> None:
    """Set the value of a the field of the target device state file.

    By default, you will be prompted for
    """
    prompt_auto_yes_create_file = prompt_auto_yes
    prompt_auto_yes_create_field = prompt_auto_yes or prompt_auto_yes_create_field

    state_d: DeviceStatePlainT = {}

    target_file = ctx.rw_target_file

    try:
        state_d = target_file.load_plain()
    except DeviceStateFileAccessError as e:
        if not prompt_auto_yes_create_file and not _confirm_create_missing_state_file(target_file.filename):
            raise CliError(str(e)) from e

        target_file.filename.parent.mkdir(exist_ok=True, parents=True)
        target_file.filename.touch()

    try:
        sanitized_value = get_field_schema(field_name).sanitize(ctx.db, field_value)
    except FieldValueInvalidError as e:
        raise CliError("Invalid value specified for field " f"'{field_name}': {str(e)}") from e

    try:
        state_d[field_name] = sanitized_value
    except KeyError as e:
        raise CliError(f"Cannot find field '{field_name}'") from e

    try:
        ctx.rw_target_file.dump_plain(state_d)
    except DeviceStateFileAccessError as e:
        raise CliError(str(e)) from e


@field.command(name="get")
@click.argument("field-name", shell_complete=list_ac_readable_field_names)  # type: ignore
@pass_cli_ctx
def _get(ctx: CliCtx, field_name: str) -> None:
    try:
        out_field = ctx.rw_target_file.load_plain()[field_name]
    except KeyError:
        # click.echo("null")
        raise CliError(f"Cannot find field '{field_name}'")
    except DeviceStateFileAccessError as e:
        raise CliError(str(e)) from e

    out_lines = []

    if out_field is None:
        out_lines = ["null"]
    elif isinstance(out_field, list):
        out_lines = out_field
    elif isinstance(out_field, str):
        out_lines = [out_field]
    else:
        raise CliError("Not a field. Please be more specific:\n" f"{yaml.safe_dump(out_field, sort_keys=False)}")

    for out_ln in out_lines:
        if not isinstance(out_ln, str):
            raise CliError("Not a field. Please be more specific:\n" f"{yaml.safe_dump(out_ln, sort_keys=False)}")

        click.echo(out_ln)


# TODO: Consider allowing rm multiple fields at a time.
@field.command(name="rm")
@click.argument("field-name", shell_complete=list_ac_removable_field_names)  # type: ignore
@pass_cli_ctx
def _rm(ctx: CliCtx, field_name: str) -> None:
    try:
        state_d = ctx.rw_target_file.load_plain()
    except DeviceStateFileAccessError as e:
        raise CliError(str(e)) from e

    # TODO: Consider preventing the removal of some mandatory
    # fields.

    try:
        del state_d[field_name]
    except KeyError:
        raise CliError(f"Cannot find field '{field_name}'")

    try:
        ctx.rw_target_file.dump_plain(state_d)
    except DeviceStateFileAccessError as e:
        raise CliError(str(e)) from e
