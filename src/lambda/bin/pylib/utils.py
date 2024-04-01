import json
import os
import re
import sys
import tomllib
import pprint

from pathlib import Path
from functools import reduce
## need to install
from dotmap import DotMap


pp = pprint.PrettyPrinter(indent=4)
flatten=lambda l: sum(map(flatten,l),[]) if isinstance(l,list) else [l]
DEFAULT_TOKEN_PATTERN = r"\{\{\s*([\w\.]+)\s*\}\}"
COMPUTE_TOKEN_PATTERN = r"\{%\s*([\w\.]+)\s*%\}"
RECURSION_LIMIT = 10
TOKEN_EXPANSION_LIMIT = 5
token_pattern_func_map = {
    DEFAULT_TOKEN_PATTERN: lambda x: r"(\{\{\s*" + x + "\s*\}\})",
    COMPUTE_TOKEN_PATTERN: lambda x: r"(\{%\s*" + x + "\s*%\})",
}


class ActiveState(object):
    def __init__(self, config_file_path: Path):
        if not config_file_path:
            raise Exception("Error argument bin_path is not set!")
        self.config_file_path = config_file_path
        if config_file_path.exists():
            with open(config_file_path, 'rb') as file:
                rawdatadict = tomllib.load(file)
                unresolved_vars = ActiveState._build_vars_list(rawdatadict)
                resolved_vars = {}
                resolved_vars = ActiveState.expand_variables(resolved=resolved_vars, unresolved=unresolved_vars)
                self.dm = DotMap(ActiveState._decompose_vars(resolved_vars), _dynamic=False)
                self.load_json_documents()
                self.refresh()

    def load_json_documents(self):
        """
        Convert json_documents section into dictionaries
        """
        if 'json_documents' in self.dm.keys():
            for key, docs in self.dm['json_documents'].items():
                if type(docs) is str:
                    self.set_refkey(f'json_documents.{key}', json.loads(docs))

    def refresh(self):
        """
        Freshens tokens from the main "dm" DotMap -> "local_dm"
        """
        unresolved_vars = ActiveState._build_vars_list(self.dm.toDict())
        resolved_vars = {}
        resolved_vars = ActiveState.expand_variables(resolved=resolved_vars, unresolved=unresolved_vars, token_pattern=COMPUTE_TOKEN_PATTERN)
        self.dm_computed = DotMap(ActiveState._decompose_vars(resolved_vars), _dynamic=False)

    @staticmethod
    def _create_new_sub_dotmap(dm_obj, key):
        """
        DotMap dynamic is off, use to set a new section, ie compute
        """
        if not key or not isinstance(key, str):
            raise Exception("Error: key must be a valid string!")
        if key not in dm_obj._map:
            dm_obj[key] = DotMap()

    def set_refkey(self, refkey: str, value: str, set_value_if_none: bool = False):
        """
        Sets computed values in "dm" -> render and return from refreshed dm_computed!
        """
        if not refkey or not isinstance(refkey, str):
            raise Exception("Error: refkey must be a valid string")
        if refkey.count('.') != 1:
            raise Exception("Error: Refkey must be of the form <section>.<subsection>")

        if value is None and not set_value_if_none:
            return

        (section, subkey) = refkey.split('.')
        self._create_new_sub_dotmap(self.dm, section)
        self.dm[section][subkey] = value
        self.refresh()

    def get_refkey(self, refkey: str, default=None):
        self.refresh()
        if not refkey or not isinstance(refkey, str):
            raise Exception("Error: refkey must be a valid string")
        if refkey.count('.') != 1:
            raise Exception("Error: Refkey must be of the form <section>.<subsection>")
        (section, subkey) = refkey.split('.')
        if section in self.dm_computed.keys() and subkey in self.dm_computed[section].keys():
            # print(f"Gettin computed from {section}.{subkey}?")
            return self.dm_computed[section][subkey]
        elif section in self.dm.keys() and subkey in self.dm[section].keys():
            # print(f"Getting stale from {section}.{subkey}")
            return self.dm[section][subkey]
        return default

    def _hasattr(self, attr_path):
        if attr_path is None:
            return False
        obj = self.dm
        try:
            attrs = attr_path.split(".")
            for attr in attrs:
                obj = getattr(obj, attr)
            return True
        except AttributeError:
            return False

    @staticmethod
    def _decompose_vars(datadict: dict):
        nested_dict = {}
        for flat_key, value in datadict.items():
            keys = flat_key.split('.')
            d = nested_dict
            for key in keys[:-1]:  # Iterate through keys except the last one
                if key not in d:
                    d[key] = {}
                d = d[key]  # Move to the next level
            d[keys[-1]] = value  # Set the value for the innermost key
        return nested_dict

    @staticmethod
    def _build_vars_list(datadict: dict):
        return {f'{outer_key}.{inner_key}': value for outer_key, inner_dict in datadict.items() for inner_key, value in inner_dict.items()}

    def build_vars_list(self):
        """
        creates a flat source for our references section: { key: value, } => section.key: value
        """
        return ActiveState._build_vars_list(self.dm.toDict())

    @staticmethod
    def expand_variables(resolved: dict = {}, unresolved: dict = {}, keycounter: dict = {}, token_pattern=DEFAULT_TOKEN_PATTERN, debug: bool = False, norecurse: bool = False, depth: int = 0) -> dict:
        if not unresolved:
            return resolved
        if debug:
            print(f"expand_variables(resolved size = {len(resolved)}, unresolved size = {len(unresolved)} token_pattern='{token_pattern}, depth={depth}')")
        if (depth >= RECURSION_LIMIT):
            raise Exception(f"Maxium depth {depth} reached for expand_variables! Probably circular reference in dictionary!")
        var_keys = list(unresolved.keys())
        for vname in var_keys:
            currentval =  unresolved[vname] if vname in unresolved else None
            newval = ActiveState.resolve_tokens(currentval, unresolved, resolved=resolved, token_pattern=token_pattern, debug=debug, tracking_key=vname)
            if(
                (not contains_token(newval, token_pattern=token_pattern)) or
                ((vname in keycounter)) and (keycounter[vname] >= TOKEN_EXPANSION_LIMIT)
            ):
                resolved[vname] = newval
                del unresolved[vname]
            else:
                keycounter[vname] = 1 if vname not in keycounter else keycounter[vname] + 1
                unresolved[vname] = newval
        return ActiveState.expand_variables(resolved=resolved, unresolved=unresolved, keycounter=keycounter, token_pattern=token_pattern, debug=debug, norecurse=norecurse, depth=depth+1)

    @staticmethod
    def resolve_tokens(element:[dict|list|str|int], unresolved: dict, resolved: dict = {}, token_pattern: str = DEFAULT_TOKEN_PATTERN, debug: bool = False, tracking_key: str = None):
        """
        """
        # breakdown dictionary into elements, reassemble and return
        if isinstance(element, dict):
            return {key: ActiveState.resolve_tokens(value, unresolved, resolved=resolved, token_pattern=token_pattern, debug=debug, tracking_key=f'{tracking_key}.{key}') for key, value in element.items()}
        # breakdown list into elements, reassemble and return
        elif isinstance(element, list):
            return [ActiveState.resolve_tokens(value, unresolved, resolved=resolved, token_pattern=token_pattern, debug=debug, tracking_key=tracking_key) for value in element]
        # breakdown tuble into elements, reassemble
        elif isinstance(element, tuple):
            return tuple([ActiveState.resolve_tokens(value, unresolved, resolved=resolved, token_pattern=token_pattern, debug=debug, tracking_key=tracking_key) for value in element])
        elif isinstance(element, int):
            return element
        elif isinstance(element, str):
            matches = re.findall(token_pattern, element)
            if not matches:
                return element
            else:
                pattern_func = token_pattern_func_map[token_pattern]
                for i, match in enumerate(matches):
                    if debug:
                        print(f"i: {i} match: {match} type: {type(match)}")
                    pattern = pattern_func(match)
                    if match in resolved:
                        if debug:
                            print("in resolved!")
                        element = re.sub(pattern, resolved[match], element, count=1)
                    elif match in unresolved:
                        if debug:
                            print("in unresolved")
                        element = re.sub(pattern, unresolved[match], element, count=1)
                    elif match in os.environ:
                        element = re.sub(pattern, os.environ[match], element, count=1)
                if debug:
                    print(f"returning this: -> {element}")
                return element
        else:
            source_element = f" from '{tracking_key}'" if tracking_key is not None else ''
            print(f"WARNING: {type(element)} type {source_element} is not yet supported!")

        return element


def has_token_recursive(item: [dict|list|str|int], token_pattern: str = DEFAULT_TOKEN_PATTERN):
    """
    Scans our data for tokens, returns a list with a True if there is one.
    """
    # print(f"has_token_recursive(item type = {type(item)})")
    # token_pattern = r"\{\{\s*(\w+)\s*\}\}"
    if isinstance(item, dict):
        str_bool_map = [bool(re.match(token_pattern, value)) for value in item.values() if isinstance(value, str)]
        dict_bool_map = list(map(lambda x: has_token_recursive(x, token_pattern=token_pattern), [ v for idict in item.values() if isinstance(idict, dict) for v in idict.values()]))
        list_bool_map = list(map(lambda x: has_token_recursive(x, token_pattern=token_pattern), [ ilist for ilist in item.values() if isinstance(ilist, list)]))
        return flatten(str_bool_map + dict_bool_map + list_bool_map)
    elif isinstance(item, list):
        str_bool_map = [bool(re.match(token_pattern, value)) for value in item if isinstance(value, str)]
        dict_bool_map = list(map(lambda x: has_token_recursive(x, token_pattern=token_pattern), [ v for idict in item if isinstance(idict, dict) for v in idict.values()]))
        list_bool_map = list(map(lambda x: has_token_recursive(x, token_pattern=token_pattern), [ ilist for ilist in item if isinstance(ilist, list)]))
        return flatten(str_bool_map + dict_bool_map + list_bool_map)
    elif isinstance(item, tuple):
        raise Exception("Unsupported type 'tuple', cannot process!")
    elif isinstance(item, str):
        return [bool(re.match(token_pattern, item))]
    else:
        return [False]


def contains_token(item: [dict|list|str|int], token_pattern=DEFAULT_TOKEN_PATTERN) -> bool:
    return any(has_token_recursive(item, token_pattern=token_pattern))


def resolve_tokens(element:[dict|list|str|int], unresolved: dict, resolved: dict = {}, token_pattern: str = DEFAULT_TOKEN_PATTERN, debug: bool = False):
    """
    """
    # breakdown dictionary into elements, reassemble and return
    if isinstance(element, dict):
        return {key: resolve_tokens(value, unresolved, resolved=resolved, token_pattern=token_pattern, debug=debug) for key, value in element.items()}
    # breakdown list into elements, reassemble and return
    elif isinstance(element, list):
        return [resolve_tokens(value, unresolved, resolved=resolved, token_pattern=token_pattern, debug=debug) for value in element]
    # breakdown tuble into elements, reassemble
    elif isinstance(element, tuple):
        return tuple([resolve_tokens(value, unresolved, resolved=resolved, token_pattern=token_pattern, debug=debug) for value in element])
    elif isinstance(element, int):
        return element
    elif isinstance(element, str):
        matches = re.findall(token_pattern, element)
        if not matches:
            return element
        else:
            pattern_func = token_pattern_func_map[token_pattern]
            for i, match in enumerate(matches):
                if debug:
                    print(f"i: {i} match: {match} type: {type(match)}")
                pattern = pattern_func(match)
                if match in resolved:
                    if debug:
                        print("in resolved!")
                    element = re.sub(pattern, resolved[match], element, count=1)
                elif match in unresolved:
                    if debug:
                        print("in unresolved")
                    element = re.sub(pattern, unresolved[match], element, count=1)
                elif match in os.environ:
                    element = re.sub(pattern, os.environ[match], element, count=1)
            if debug:
                print(f"returning this: -> {element}")
            return element
    else:
        print(f"WARNING: {type(element)} type is not yet supported!")

    return element


def expand_variables(resolved: dict = {}, unresolved: dict = {}, keycounter: dict = {}, token_pattern=DEFAULT_TOKEN_PATTERN, debug: bool = False, norecurse: bool = False, depth: int = 0) -> dict:
    """
    Input: Unresolved list of key/value pairs that contain self referencing tokens. Return fully
    resolved list of key/values.

    Walk through all key/var sets:
      prep - evalutate values and expand tokens with matched keys in
      unresolved section. Set max recursion to prevent cirular evaluation.

      Process/resolve key's
      step 1) sort key/value pairs in resolved/not resolved piles. Remove fully resolved and
              move into resolved pile, remove from deleted pile
      step 2) re-process unresolved key/value pairs.
      step 3) Repeat step 1 until unresolved pile is empty.

      resolved - all key/value objects already resolved (does not expand tokens in this set)
      unresolved - source of ke/values to resolve tokens in and move to resolved dict
    """
    if not unresolved:
        return resolved
    if debug:
        print(f"expand_variables(resolved size = {len(resolved)}, unresolved size = {len(unresolved)} token_pattern='{token_pattern}, depth={depth}')")
    if (depth >= RECURSION_LIMIT):
        raise Exception(f"Maxium depth {depth} reached for expand_variables! Probably circular reference in dictionary!")
    var_keys = list(unresolved.keys())
    for vname in var_keys:
        currentval =  unresolved[vname] if vname in unresolved else None
        newval = resolve_tokens(currentval, unresolved, resolved=resolved, token_pattern=token_pattern, debug=debug)
        if(
            (not contains_token(newval, token_pattern=token_pattern)) or
            ((vname in keycounter)) and (keycounter[vname] >= TOKEN_EXPANSION_LIMIT)
        ):
            resolved[vname] = newval
            del unresolved[vname]
        else:
            keycounter[vname] = 1 if vname not in keycounter else keycounter[vname] + 1
            unresolved[vname] = newval
    return expand_variables(resolved=resolved, unresolved=unresolved, keycounter=keycounter, token_pattern=token_pattern, debug=debug, norecurse=norecurse, depth=depth+1)


def build_vars_list(datadict: dict):
    """
    Returns an index/value for all key/vals that are to be resolved if not already

    Structured as key -> subkey -> entries (list/dict/str/int/etc...)
    """
    vars = {}
    if not datadict:
        return vars
    for key, group in datadict.items():
        if(type(group) is not dict):
            vars[key] = group
        elif (type(group) is dict):
            for subkey, value in group.items():
                vars[subkey] = value
        else:
            raise Exception(f"'{type(group)}' unexpected type on group issue..")
    return vars

if __name__=="__main__":
    print("Running a test")
    config_file_path = Path(__file__).absolute().parents[1] / 'cyawsmgr_config.ini'

    ast = ActiveState(config_file_path)
    pp.pprint(ast.dm.toDict())

    # config = load_config(bin_path=bin_path)
    # # pp.pprint(config)
    # ast = ActiveState(config)
    # ast.setvalue('computed.newval', 1)
    # ast.update()
