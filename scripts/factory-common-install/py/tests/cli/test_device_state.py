import nsf_factory_common_install.file_device_state
import os 
import pathlib
import pytest
import yaml

from pathlib import Path
from _pytest.logging import LogCaptureFixture

from nsf_factory_common_install.cli.device_state import cli
from test_lib.click import invoke_cli

from shutil import copyfile
from src.nsf_factory_common_install.types_device_state import DeviceState
from src.nsf_factory_common_install.file_device_state import DeviceStateFile


def yaml_as_dict(file):
    dict = {}
    with open(file, 'r') as fp:
        docs = yaml.safe_load_all(fp)
        for doc in docs:
            for key, value in doc.items():
                dict[key] = value
    return dict


def yaml_file_is_equal(file1, file2) -> bool:
    first_file = yaml_as_dict(file1)
    seconde_file = yaml_as_dict(file2)
    for a in first_file:
        if a not in seconde_file:
            return False
        elif first_file[a] != seconde_file[a]:
            return False
    return True

@pytest.fixture()
def workspace_dir_with_empty_current_device_state_file(empty_device_state, workspace_dir):
    target_file = DeviceStateFile(tmp_dir)
    target_file.dump_plain(empty_device_state)

@pytest.fixture(autouse=True)
def factory_common_install_checkout_repo_with_one_device(workspace_dir, device_state_to_checkout):
    env_var_name = "PKG_NSF_FACTORY_COMMON_INSTALL_DEVICE_OS_CONFIG_REPO_DIR"
    os.environ[env_var_name] = workspace_dir.dirname
    target_file = DeviceStateFile(workspace_dir / device / device_state_to_checkout.id / '.device.json')
    target_file.dump_plain(device_state_to_checkout)
    

@pytest.fixture(autouse=True)
def factory_common_install_workspace_tmp_dir_with_(workspace_dir):
    env_var_name = "PKG_NSF_FACTORY_COMMON_INSTALL_WORKSPACE_DIR"
    os.environ[env_var_name] = workspace_dir.dirname
    target_file = DeviceStateFile(workspace_dir / '.current_device.yaml')
    target_file.dump_plain(empty_device_state)

@pytest.fixture()
def empty_device_state()-> DeviceState:
    return DeviceState('','','','','','',[''])

@pytest.fixture()
def device_state_to_checkout()->DeviceState:
    return DeviceState('qc-zilia-test-a11aa', 'teguar-tp-5040-16w', '0001','192.168.1.110','22', '',[''] )

@pytest.fixture()
def tmp_path_file_reference() -> str:
    return os.path.dirname(os.path.realpath(__file__)) + '/.current-device-REF.yaml'

@pytest.fixture()
def workspace_dir(tmp_path_factory) -> Path:
    toto = tmp_path_factory.mktemp("data")
    return toto

""" @pytest.fixture()
def tmp_dir(tmpdir_factory) -> str:
    env_var_name = "PKG_NSF_FACTORY_COMMON_INSTALL_WORKSPACE_DIR"
    tmp_path = tmpdir_factory.mktemp("data")
    tmp_dir_path_str = tmp_path.strpath
    os.environ[env_var_name] = tmp_dir_path_str
    return tmp_dir_path_str """


@pytest.fixture()
def tmp_path_file(tmp_dir) -> str:   
    tmp_path_device_str = tmp_dir + '/.current-device.yaml'
    #local_path = os.path.dirname(os.path.realpath(__file__)) + '/.current-device-INIT.yaml'
    #copyfile(local_path, tmp_path_device_str)
    return tmp_path_device_str

@pytest.fixture()
def callable_current_device(workspace_dir):
    def current_device() -> DeviceState:
            devicestatefile = DeviceStateFile(workspace_dir)
            device = devicestatefile.load_plain()
            return device
    return current_device 

    
def test_help(caplog: LogCaptureFixture) -> None:
    result = invoke_cli(caplog, cli, ['--help'])
    assert 0 == result.exit_code


def test_info(caplog: LogCaptureFixture) -> None:
    result = invoke_cli(caplog, cli, ['info'])
    assert 0 == result.exit_code


""" def test_device_state_checkout_with_device_identifier(callable_current_device:Device, device_to_checkout:Device
        caplog: LogCaptureFixture) -> None: 
    result = invoke_cli(caplog, cli, ['checkout', 'qc-zilia-test-a11aa'], input='y\n')
    assert 0 == result.exit_code
    current_device = callable_current_device() """
    # assert yaml_file_is_equal(tmp_path_file, tmp_path_file_reference)


def test_device_state_checkout_with_sn(callable_current_device, device_state_to_checkout:DeviceState,
        caplog: LogCaptureFixture) -> None:
    result = invoke_cli(caplog, cli, ['checkout', '--serial-number', device_state_to_checkout.serial_number], input='y\n')
    assert 0 == result.exit_code
    resulting_current_device = callable_current_device()
    assert resulting_current_device == device_state_to_checkout