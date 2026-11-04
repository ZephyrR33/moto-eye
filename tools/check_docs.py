#!/usr/bin/env python3
"""Offline check of relative Markdown links and accidental large binaries.

No third-party modules or network requests. Suitable for GitHub Actions.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
MD_LINK = re.compile(r'(?<!!)\[[^\]]+\]\((?:<([^>]+)>|([^\s)]+))(?:\s+"[^"]+")?\)')
HTML_ATTR = re.compile(r'(?:href|src)=["\']([^"\']+)["\']', re.IGNORECASE)
BANNED = {'.img', '.bin', '.rar', '.7z', '.exe', '.msi', '.apk', '.fw'}


def is_external(url: str) -> bool:
    return url.startswith(('http://', 'https://', 'mailto:', 'data:', '#', '//'))


def check_url(md_file: Path, raw: str) -> str | None:
    link = unquote(raw.strip())
    if is_external(link) or link.startswith(('sandbox:', 'javascript:')):
        return None
    path = link.split('#', 1)[0].split('?', 1)[0]
    if not path:
        return None
    if path.startswith('/'):
        return f'{md_file.relative_to(ROOT)}: absolute file path in link: {link}'
    resolved = (md_file.parent / path).resolve()
    try:
        resolved.relative_to(ROOT)
    except ValueError:
        return f'{md_file.relative_to(ROOT)}: link leaves repository: {link}'
    if not resolved.exists():
        return f'{md_file.relative_to(ROOT)}: broken relative link: {link}'
    return None


def main() -> int:
    errors: list[str] = []
    markdowns = sorted(ROOT.rglob('*.md'))
    for item in markdowns:
        source = item.read_text(encoding='utf-8')
        # strip fenced code blocks; example links in code are not navigational
        source = re.sub(r'^\s*```.*?^\s*```', '', source, flags=re.MULTILINE | re.DOTALL)
        for match in MD_LINK.finditer(source):
            issue = check_url(item, match.group(1) or match.group(2))
            if issue:
                errors.append(issue)
        for match in HTML_ATTR.finditer(source):
            issue = check_url(item, match.group(1))
            if issue:
                errors.append(issue)
    for item in ROOT.rglob('*'):
        if item.is_file() and '.git' not in item.parts:
            if item.suffix.lower() in BANNED:
                errors.append(f'Unexpected binary/proprietary artifact: {item.relative_to(ROOT)}')
    if errors:
        for error in errors:
            print('ERROR:', error)
        return 1
    print(f'PASS: {len(markdowns)} Markdown files, relative links and repository artifact policy OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
