#!/usr/bin/env python3

from __future__ import annotations

import getpass
import os
import sys
import tempfile
from pathlib import Path

import instaloader


def main() -> int:
    if not sys.stdin.isatty():
        print("Run this script in an interactive SSH terminal.", file=sys.stderr)
        return 1

    session_id = getpass.getpass("Instagram sessionid (hidden): ").strip()
    csrf_token = getpass.getpass("Instagram csrftoken (hidden): ").strip()
    if not session_id or not csrf_token:
        print("Both cookie values are required.", file=sys.stderr)
        return 1

    loader = instaloader.Instaloader(
        quiet=True, max_connection_attempts=1, request_timeout=20,
        iphone_support=False,
    )
    loader.context.update_cookies({"sessionid": session_id, "csrftoken": csrf_token})
    try:
        username = loader.test_login()
        if not username:
            print("Session validation failed. No session file was changed.", file=sys.stderr)
            return 1
        loader.context.username = username

        session_file = Path.home() / ".config" / "instaloader" / "session-menu"
        session_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, name = tempfile.mkstemp(prefix=".session-menu-", dir=session_file.parent)
        os.close(fd)
        temporary = Path(name)
        try:
            loader.save_session_to_file(str(temporary))
            temporary.chmod(0o600)
            temporary.replace(session_file)
        finally:
            temporary.unlink(missing_ok=True)
    except Exception as error:
        print(f"Session import failed ({type(error).__name__}).", file=sys.stderr)
        return 1
    print(f"Logged in as {username}.")
    print(f"Session ready: {session_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
