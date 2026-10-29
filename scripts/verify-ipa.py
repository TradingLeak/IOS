#!/usr/bin/env python3
"""Inspect a device IPA without extracting it or needing Xcode/ESign.

Checks import structure and Mach-O metadata, not certificates, UDID or ESign itself.
Never outputs the full Info.plist (which could contain build-time API configuration).
"""
import argparse
import hashlib
import json
import plistlib
import re
import struct
import sys
import zipfile
from pathlib import Path, PurePosixPath


class IPAError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise IPAError(message)


def thin_macho(data):
    require(len(data) >= 32, "Executable is too short for a Mach-O header")
    require(data[:4] == b"\xcf\xfa\xed\xfe", "Expected a little-endian 64-bit Mach-O executable")
    _, cpu, _, filetype, count, command_bytes, _, _ = struct.unpack_from("<8I", data)
    require(filetype == 2, "Main executable is not MH_EXECUTE")
    require(command_bytes <= len(data) - 32 and count <= command_bytes // 8, "Invalid Mach-O load-command table")
    platform, minimum_os, cryptids, signature = None, None, [], False
    offset = 32
    for _ in range(count):
        require(offset + 8 <= 32 + command_bytes, "Truncated load command")
        cmd, size = struct.unpack_from("<II", data, offset)
        require(size >= 8 and offset + size <= 32 + command_bytes, "Invalid load-command size")
        if cmd == 0x32:  # LC_BUILD_VERSION
            require(size >= 24, "Truncated LC_BUILD_VERSION")
            platform, version = struct.unpack_from("<II", data, offset + 8)
            minimum_os = f"{version >> 16}.{(version >> 8) & 255}.{version & 255}"
        if cmd in (0x21, 0x2C):  # LC_ENCRYPTION_INFO / LC_ENCRYPTION_INFO_64
            require(size >= 20, "Truncated encryption command")
            cryptids.append(struct.unpack_from("<I", data, offset + 16)[0])
        if cmd == 0x1D:  # LC_CODE_SIGNATURE
            signature = True
        offset += size
    require(offset == 32 + command_bytes, "Load commands do not match sizeofcmds")
    require(cpu == 0x0100000C, "Executable slice is not arm64")
    require(platform == 2, "Executable platform is not iOS device (LC_BUILD_VERSION must be IOS=2)")
    require(not any(cryptids), "Executable is FairPlay-encrypted; cannot simply re-sign it")
    return {"architecture": "arm64", "platform": "IOS", "minimum_os_macho": minimum_os,
            "encrypted": False, "has_code_signature_command": signature}


def inspect_macho(data):
    if data[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        require(len(data) >= 8, "Truncated FAT header")
        count = struct.unpack_from(">I", data, 4)[0]
        entry_size = 32 if data[:4] == b"\xca\xfe\xba\xbf" else 20
        require(0 < count <= 64 and 8 + count * entry_size <= len(data), "Invalid FAT architecture table")
        for i in range(count):
            offset = 8 + i * entry_size
            cpu = struct.unpack_from(">I", data, offset)[0]
            if cpu != 0x0100000C:
                continue
            start, size = struct.unpack_from(">QQ" if entry_size == 32 else ">II", data, offset + 8)
            require(start + size <= len(data), "FAT slice exceeds executable size")
            return thin_macho(data[start:start + size])
        raise IPAError("No arm64 slice in FAT executable")
    return thin_macho(data)


def inspect(path, expected_sha=None):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    sha = digest.hexdigest()
    if expected_sha:
        require(re.fullmatch(r"[0-9a-fA-F]{64}", expected_sha) is not None, "Invalid expected SHA-256")
        require(sha == expected_sha.lower(), "IPA SHA-256 differs from the published build")
    require(zipfile.is_zipfile(path), "Not a ZIP/IPA file; may be an HTML download page, checksum file or incomplete download")
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP entries")
        for entry in archive.infolist():
            parts = PurePosixPath(entry.filename).parts
            require(not entry.filename.startswith(("/", "\\")) and ".." not in parts and "\\" not in entry.filename,
                    "Unsafe archive path")
            require(entry.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), "Nonstandard ZIP compression for IPA")
            require(not entry.flag_bits & 1, "IPA ZIP must not be password-encrypted")
        require(archive.testzip() is None, "ZIP CRC integrity check failed")
        plist_paths = [name for name in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        require(len(plist_paths) == 1, "Expected exactly one Payload/App.app/Info.plist at the archive root")
        app = plist_paths[0].rsplit("/", 1)[0]
        raw = archive.read(plist_paths[0])
        try:
            info = plistlib.loads(raw)
        except Exception as exc:
            raise IPAError("Cannot parse the app Info.plist") from exc
        require(isinstance(info, dict), "Info.plist root is not a dictionary")
        for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleName", "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion"):
            require(isinstance(info.get(key), str) and info[key].strip(), f"Missing or invalid {key}")
        require(info.get("CFBundlePackageType") == "APPL", "Bundle package type is not APPL")
        require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "App is not an iPhoneOS device bundle")
        executable = info["CFBundleExecutable"]
        require("/" not in executable and "\\" not in executable and executable not in (".", ".."), "Invalid CFBundleExecutable path")
        binary_path = app + "/" + executable
        require(binary_path in names, "CFBundleExecutable is missing from the IPA")
        entry = archive.getinfo(binary_path)
        mode = entry.external_attr >> 16
        require(mode & 0o111, "ZIP executable permissions are missing")
        macho = inspect_macho(archive.read(binary_path))
        require(macho["minimum_os_macho"].split(".")[:2] == info["MinimumOSVersion"].split(".")[:2],
                "MinimumOSVersion differs from the Mach-O deployment target")
        warnings = []
        profiles = [name for name in names if name.endswith("/embedded.mobileprovision")]
        signatures = [name for name in names if "/_CodeSignature/" in name]
        if not profiles:
            warnings.append("No provisioning profile: expected for unsigned IPA; a valid profile/certificate is needed to install")
        if not macho["has_code_signature_command"]:
            warnings.append("Mach-O has no LC_CODE_SIGNATURE; some signers may require adding a signature command")
        return {"result": "PASS", "file": path.name, "bytes": path.stat().st_size, "sha256": sha,
                "app_path": app, "bundle_id": info["CFBundleIdentifier"], "executable": executable,
                "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                "minimum_os": info["MinimumOSVersion"], "plist_format": "binary" if raw.startswith(b"bplist") else "xml",
                "executable_mode": oct(mode), "zip_crc": "PASS", "zip_entries": len(names),
                "embedded_profiles": len(profiles), "signature_resource_entries": len(signatures),
                **macho, "warnings": warnings,
                "scope": "Archive and executable checks only; not tested with ESign or an actual iPhone"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--github", action="store_true")
    args = parser.parse_args()
    try:
        report = inspect(args.ipa, args.expected_sha256)
    except (OSError, ValueError, zipfile.BadZipFile, KeyError, struct.error) as exc:
        report = {"result": "FAIL", "error": str(exc)}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.github:
        text = json.dumps(report, ensure_ascii=False).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::{'notice' if report['result'] == 'PASS' else 'error'} title=IPA import audit::{text}")
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
