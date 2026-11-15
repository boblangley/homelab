# Managed in the homelab repo (role trowel).
"""to_block_yaml: like to_nice_yaml, but multi-line strings (such as JSONata transforms) become literal | blocks."""
import yaml


class _BlockDumper(yaml.SafeDumper):
    pass


def _str(dumper, value):
    style = "|" if "\n" in value else None
    return dumper.represent_scalar("tag:yaml.org,2002:str", value, style=style)


_BlockDumper.add_representer(str, _str)


def to_block_yaml(data, indent=2, width=120):
    # Plain types only: Ansible's own strings and numbers are subclasses the safe dumper refuses.
    def plain(v):
        if isinstance(v, dict):
            return {str(k): plain(x) for k, x in v.items()}
        if isinstance(v, (list, tuple)):
            return [plain(x) for x in v]
        if isinstance(v, str):
            return str(v)
        if isinstance(v, bool):
            return bool(v)
        if isinstance(v, int):
            return int(v)
        if isinstance(v, float):
            return float(v)
        return v

    return yaml.dump(plain(data), Dumper=_BlockDumper, indent=indent, width=width, sort_keys=False,
                     default_flow_style=False, allow_unicode=True)


class FilterModule:
    def filters(self):
        return {"to_block_yaml": to_block_yaml}
