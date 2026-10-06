#!/usr/bin/env python3
"""Helpers JSON partagés par le wrapper (recherche récursive de clé)."""
def search(d, keys):
    if isinstance(d, dict):
        for k in keys:
            if k in d and d[k] not in (None, ""):
                return d[k]
        for v in d.values():
            r = search(v, keys)
            if r not in (None, ""):
                return r
    elif isinstance(d, list):
        for v in d:
            r = search(v, keys)
            if r not in (None, ""):
                return r
    return None