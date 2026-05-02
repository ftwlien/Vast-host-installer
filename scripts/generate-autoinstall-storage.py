#!/usr/bin/env python3
from __future__ import annotations

import argparse


def emit_direct_layout_yaml() -> str:
    return """
storage:
  layout:
    name: direct
""".strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['single-disk', 'two-disk', 'auto'], default='auto')
    parser.parse_args()
    print(emit_direct_layout_yaml())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
