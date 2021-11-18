import click
from typing import Optional, Type, Any, Dict
from functools import update_wrapper


def find_ctx_dict_instance(
        ctx: click.Context, at_key: str, instance_type: Type) -> Optional[Any]:
    """Return the first `ctx.obj` of type `dict` containing
        an instance of specified type at specified key.

    This is an improvement over `click.Context.find_object`.
    """
    node: Optional[click.Context] = ctx
    while node is not None:
        if isinstance(node.obj, dict) and at_key in node.obj:
            instance = node.obj[at_key]
            assert isinstance(instance, instance_type)
            return instance
        node = node.parent

    return None


def ensure_ctx_obj_is_dict(obj: Dict[str, Any]) -> Dict[str, Any]:
    if isinstance(obj, dict):
        return obj

    raise RuntimeError(
        "Expected 'obj' of 'dict' type. "
        f"Found instead: '{type(obj).__name__}'."
    )


def check_ctx_obj_is_dict(ctx: click.Context) -> Dict[str, Any]:
    ensure_ctx_obj_is_dict(ctx.obj)
    return ctx.obj


def ensure_ctx_obj_is_dict_or_unspecified(
        obj: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if obj is None:
        return {}

    if isinstance(obj, dict):
        return obj

    raise RuntimeError(
        "Expected 'obj' of 'dict' type or unspecified ('None'). "
        f"Found instead: '{type(obj).__name__}'."
    )


def check_ctx_obj_is_dict_or_unspecified(
        ctx: click.Context) -> Optional[Dict[str, Any]]:
    ensure_ctx_obj_is_dict_or_unspecified(ctx.obj)
    return ctx.obj


def mk_ctx_dict_obj(
        obj: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    return ensure_ctx_obj_is_dict_or_unspecified(obj)


def init_ctx_dict_instance(
        ctx: click.Context,
        key: str,
        value: Any
) -> None:
    check_ctx_obj_is_dict_or_unspecified(ctx)

    if not isinstance(ctx.obj, dict):
        ctx.obj = mk_ctx_dict_obj()

    existing_value = ctx.obj.get(key)
    # assert existing_value is None, (
    #     f"Unexpected pre-existing value at key '{key}' of type: "
    #     f"'{type(existing_value).__name__}'"
    # )

    ctx.obj[key] = value


def find_mandatory_ctx_dict_instance(
        ctx: click.Context, at_key: str, instance_type: Type) -> Any:
    check_ctx_obj_is_dict(ctx)

    obj = find_ctx_dict_instance(ctx, at_key, instance_type)
    if obj is None:
        raise RuntimeError(
            "Cannot find any 'ctx.obj' of type 'dict' containing "
            f"an instance of type '{instance_type.__name__}' "
            f"at key '{at_key}'"
        )

    return obj


def mk_ctx_dict_pass_decorator(at_key: str, instance_type: Type) -> Any:
    """Create a decorator similar to `click.make_pass_decorator` that will
        pass as an argument to decorated callback a context object stored
        in a `ctx.obj` of type `dict` at specified key and of specified
        type.

    This is an improvement over `click.make_pass_decorator`.
    """
    def decorator(f):
        def new_func(*args, **kwargs):
            ctx = click.get_current_context()
            obj = find_mandatory_ctx_dict_instance(ctx, at_key, instance_type)
            return ctx.invoke(f, obj, *args, **kwargs)
        return update_wrapper(new_func, f)
    return decorator
