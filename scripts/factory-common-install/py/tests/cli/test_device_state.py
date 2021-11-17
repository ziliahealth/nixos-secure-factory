import os 
import pytest
import tempfile
from typing import Generator

from pathlib import Path
from _pytest.logging import LogCaptureFixture

from nsf_factory_common_install.cli.device_state import cli
from test_lib.click import invoke_cli

from src.nsf_factory_common_install.types_device_state import DeviceState
from src.nsf_factory_common_install.file_device_state import DeviceStateFile


@pytest.fixture()
def empty_device_state()-> DeviceState:
    return DeviceState('','','','','','',[''])

@pytest.fixture()
def device_state_to_checkout()->DeviceState:
    return DeviceState('qc-zilia-test-a11aa', 'teguar-tp-5040-16w', '0001','192.168.1.110','22', '',[''] )

@pytest.fixture()
def current_device_file_dir(device_state_to_checkout, empty_device_state) -> Generator[str, None, None]:
    with tempfile.TemporaryDirectory() as dirpath:
        os.environ["PKG_NSF_FACTORY_COMMON_INSTALL_WORKSPACE_DIR"] = dirpath
        current_device_file_dir = Path(dirpath + '/.current-device.yaml')
        target_file = DeviceStateFile(current_device_file_dir)
        target_file.dump_plain(empty_device_state.to_dict())

        os.environ["PKG_NSF_FACTORY_COMMON_INSTALL_DEVICE_OS_CONFIG_REPO_DIR"] = dirpath
        checkout_tmp_dir = dirpath +f'/device/{device_state_to_checkout.id}'
        os.makedirs(checkout_tmp_dir)
        device_state_checkout_file = DeviceStateFile(Path(checkout_tmp_dir + '/device.json'))
        device_state_checkout_file.dump_plain(device_state_to_checkout.to_dict())
        yield current_device_file_dir

@pytest.fixture()
def callable_current_device(current_device_file_dir):
    def current_device() -> DeviceState:
            devicestatefile = DeviceStateFile(current_device_file_dir)
            device = devicestatefile.load_plain()
            return device
    return current_device 

    
def test_help(caplog: LogCaptureFixture) -> None:
    result = invoke_cli(caplog, cli, ['--help'])
    assert 0 == result.exit_code


def test_info(caplog: LogCaptureFixture) -> None:
    result = invoke_cli(caplog, cli, ['info'])
    assert 0 == result.exit_code


def test_device_state_checkout_with_device_identifier(callable_current_device, device_state_to_checkout:DeviceState,
        caplog: LogCaptureFixture) -> None: 
    result = invoke_cli(caplog, cli, ['checkout', device_state_to_checkout.id], input='y\n')
    assert 0 == result.exit_code
    resulting_current_device = callable_current_device()
    assert resulting_current_device == device_state_to_checkout.to_dict()


def test_device_state_checkout_with_sn(callable_current_device, device_state_to_checkout:DeviceState,
        caplog: LogCaptureFixture) -> None:
    result = invoke_cli(caplog, cli, ['checkout', '--serial-number', device_state_to_checkout.serial_number], input='y\n')
    assert 0 == result.exit_code
    resulting_current_device = callable_current_device()
    assert resulting_current_device == device_state_to_checkout.to_dict()