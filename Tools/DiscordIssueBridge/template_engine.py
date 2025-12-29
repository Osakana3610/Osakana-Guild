from __future__ import annotations

import re
from typing import Dict

_PLACEHOLDER = re.compile(r"{{\s*([a-zA-Z0-9_]+)\s*}}")


def render(template: str, context: Dict[str, str]) -> str:
    def _replace(match: re.Match[str]) -> str:
        key = match.group(1)
        if key not in context:
            raise KeyError(f"テンプレートに未定義のプレースホルダーがあります: {key}")
        return context[key]

    return _PLACEHOLDER.sub(_replace, template)
