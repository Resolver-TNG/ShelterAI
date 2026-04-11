#!/usr/bin/env python3
"""
Add new Swift files to the Xcode pbxproj for AnpiApp AI Assistant feature.

Files to add:
- Models/ChatMessage.swift
- Services/ShelterAnalytics.swift
- Views/MainTabView.swift
- Views/RegistrationHomeView.swift
- Views/SituationView.swift
- Views/AIAssistantView.swift

Approach: literal string insertion at known anchor points.
Generates stable 24-char hex UUIDs derived from path hash.
"""

import hashlib
import re
import sys
from pathlib import Path

PBXPROJ = Path("AnpiApp.xcodeproj/project.pbxproj")

NEW_FILES = [
    # (group_name, filename, relative_path)
    ("Models", "ChatMessage.swift", "Models/ChatMessage.swift"),
    ("Services", "ShelterAnalytics.swift", "Services/ShelterAnalytics.swift"),
    ("Views", "MainTabView.swift", "Views/MainTabView.swift"),
    ("Views", "RegistrationHomeView.swift", "Views/RegistrationHomeView.swift"),
    ("Views", "SituationView.swift", "Views/SituationView.swift"),
    ("Views", "AIAssistantView.swift", "Views/AIAssistantView.swift"),
]

GROUP_UUIDS = {
    "Models": "4F9180715E9CB6510D516503",
    "Services": "3121E108047AD4DE4E259AEF",
    "Views": "0E2888FDB294B9E9CA79EC66",
}


def gen_uuid(seed: str) -> str:
    """Generate a 24-char uppercase hex UUID from a seed string (Xcode style)."""
    h = hashlib.sha256(seed.encode()).hexdigest().upper()
    return h[:24]


def main():
    text = PBXPROJ.read_text()

    # Plan: for each new file, generate two UUIDs:
    #   build_uuid (PBXBuildFile entry id)
    #   ref_uuid   (PBXFileReference id)
    plans = []
    for group, fname, _rel in NEW_FILES:
        build_uuid = gen_uuid(f"build:{group}/{fname}")
        ref_uuid = gen_uuid(f"ref:{group}/{fname}")
        plans.append({
            "group": group,
            "fname": fname,
            "build_uuid": build_uuid,
            "ref_uuid": ref_uuid,
        })

    # Idempotency: skip files already present (by filename in PBXFileReference)
    plans = [p for p in plans if f"/* {p['fname']} */" not in text]
    if not plans:
        print("All files already registered. No changes.")
        return

    # 1. Insert PBXBuildFile entries (alphabetical-ish; just append before End PBXBuildFile)
    build_lines = "".join(
        f"\t\t{p['build_uuid']} /* {p['fname']} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {p['ref_uuid']} /* {p['fname']} */; }};\n"
        for p in plans
    )
    text = text.replace(
        "/* End PBXBuildFile section */",
        build_lines + "/* End PBXBuildFile section */",
        1,
    )

    # 2. Insert PBXFileReference entries before End PBXFileReference
    ref_lines = "".join(
        f"\t\t{p['ref_uuid']} /* {p['fname']} */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {p['fname']}; sourceTree = \"<group>\"; }};\n"
        for p in plans
    )
    text = text.replace(
        "/* End PBXFileReference section */",
        ref_lines + "/* End PBXFileReference section */",
        1,
    )

    # 3. Add to each group's children
    for group_name, group_uuid in GROUP_UUIDS.items():
        group_files = [p for p in plans if p["group"] == group_name]
        if not group_files:
            continue
        # Find the group block: starts with "<group_uuid> /* <group_name> */ = {"
        # Then "children = (" followed by entries until ");"
        pattern = re.compile(
            rf"({re.escape(group_uuid)} /\* {re.escape(group_name)} \*/ = \{{[^}}]*?children = \(\n)"
            rf"((?:\t\t\t\t[A-F0-9]+ /\* [^*]+\*/,\n)*)"
            rf"(\t\t\t\);)",
            re.DOTALL,
        )
        m = pattern.search(text)
        if not m:
            print(f"WARN: group {group_name} pattern not matched", file=sys.stderr)
            continue
        head, existing, tail = m.group(1), m.group(2), m.group(3)
        addition = "".join(
            f"\t\t\t\t{p['ref_uuid']} /* {p['fname']} */,\n"
            for p in group_files
        )
        text = text[:m.start()] + head + existing + addition + tail + text[m.end():]

    # 4. Add to PBXSourcesBuildPhase files=()
    # Pattern: under "/* Begin PBXSourcesBuildPhase section */" the only build phase
    # has "files = (" then file entries until ");"
    src_pattern = re.compile(
        r"(/\* Begin PBXSourcesBuildPhase section \*/.*?files = \(\n)"
        r"((?:\t\t\t\t[A-F0-9]+ /\* [^*]+ in Sources \*/,\n)+)"
        r"(\t\t\t\);)",
        re.DOTALL,
    )
    m = src_pattern.search(text)
    if not m:
        print("ERROR: PBXSourcesBuildPhase not matched", file=sys.stderr)
        sys.exit(1)
    head, existing, tail = m.group(1), m.group(2), m.group(3)
    addition = "".join(
        f"\t\t\t\t{p['build_uuid']} /* {p['fname']} in Sources */,\n"
        for p in plans
    )
    text = text[:m.start()] + head + existing + addition + tail + text[m.end():]

    PBXPROJ.write_text(text)
    print(f"✅ Added {len(plans)} files to pbxproj:")
    for p in plans:
        print(f"   - {p['group']}/{p['fname']}")


if __name__ == "__main__":
    main()
