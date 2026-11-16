#!/usr/bin/env python3
"""Writes the App Store Connect API key from the ASC_KEY_P8 secret to a file.

The secret is accepted in any of the shapes people end up pasting: the .p8
text itself, that text base64-encoded (including Windows `certutil -encode`
output), a file saved as UTF-16, or only the key body without the BEGIN/END
lines. The result is checked with openssl before it is used. Nothing secret is
printed; only sizes and which shape was recognised.
"""
import base64
import binascii
import os
import re
import subprocess
import sys

HEADER = "-----BEGIN PRIVATE KEY-----"
FOOTER = "-----END PRIVATE KEY-----"


def decode_text(data: bytes) -> str:
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    if b"\x00" in data:
        return data.decode("utf-16-le", errors="ignore")
    return data.decode("utf-8", errors="ignore")


def normalise(text: str):
    """Returns clean PEM text, or None when no key is found in `text`."""
    text = text.replace("\\n", "\n")
    match = re.search(re.escape(HEADER) + r"(.*?)" + re.escape(FOOTER), text, re.S)
    if not match:
        return None
    body = re.sub(r"[^A-Za-z0-9+/=]", "", match.group(1))
    if len(body) < 100:
        return None
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "\n".join([HEADER, *lines, FOOTER]) + "\n"


def candidates(secret: str):
    yield "the .p8 text", secret
    stripped = "\n".join(line for line in secret.splitlines() if not line.startswith("-----"))
    compact = re.sub(r"\s+", "", stripped)
    try:
        decoded = base64.b64decode(compact + "=" * (-len(compact) % 4))
        yield "base64 of the .p8 file", decode_text(decoded)
    except (binascii.Error, ValueError):
        pass
    yield "the key body without BEGIN/END lines", f"{HEADER}\n{compact}\n{FOOTER}"


def is_valid(path: str) -> bool:
    return subprocess.run(
        ["openssl", "pkey", "-in", path, "-noout"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0


def main() -> int:
    secret = os.environ.get("ASC_KEY_P8", "")
    out_path = sys.argv[1]
    print(f"ASC_KEY_P8 is {len(secret)} characters on {len(secret.splitlines())} line(s).")
    for label, text in candidates(secret):
        pem = normalise(text)
        if pem is None:
            continue
        with open(out_path, "w") as handle:
            handle.write(pem)
        os.chmod(out_path, 0o600)
        if is_valid(out_path):
            print(f"Recognised the secret as {label}. Key file is valid.")
            return 0
    if os.path.exists(out_path):
        os.remove(out_path)
    print(
        "::error::ASC_KEY_P8 does not contain a valid App Store Connect key. "
        "Open the AuthKey_XXXX.p8 file in a text editor and paste its whole text, "
        "including the BEGIN and END lines, as the secret."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
