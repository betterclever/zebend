#!/usr/bin/env python3
"""hook.py, unchanged, but running ../../tv.new instead of ../../tv (for testing the swap
without touching hook.py or tv).  python3 hook_new.py LIST"""
import importlib.util, pathlib
T = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("hook", T / "hook.py")
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
hook.TV = T / "tv.new"
hook.main()
