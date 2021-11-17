from dataclasses import dataclass, field
from typing import Dict, Any, Optional, List, NamedTuple

DeviceStatePlainT = Dict[str, Any]


class DeviceIdWType(NamedTuple):
    id: str
    type: str


@dataclass
class DeviceState:
    id: str
    type: str
    serial_number: str
    hostname: str
    ssh_port: str
    gpg_id: Optional[str]
    factory_installed_by: Optional[List[str]]

    def to_dict(self):
        return {
            'identifier': self.id,
            'type': self.type,
            'serial-number': self.serial_number,
            'hostname': self.hostname,
            'ssh-port': self.ssh_port,
            'gpg-id': self.gpg_id,
            'factory-installed-by': self.factory_installed_by
        }
