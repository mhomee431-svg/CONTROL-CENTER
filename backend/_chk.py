import io, pathlib, re

base = pathlib.Path(r"c:\Users\akash\OneDrive\Documents\hyperlocal_app")
dart = sorted(
    p for p in (base / "apps").rglob("*.dart")
    if "/test/" not in p.as_posix()
    and not p.name.endswith("_test.dart")
    and ".dart_tool" not in p.as_posix()
)
out = []
for f in dart:
    stem = f.stem
    # A file is "used" if some OTHER file imports it or references its name.
    hits = [
        o for o in dart
        if o != f
        and (
            stem in o.read_text(encoding="utf-8", errors="ignore")
            or f"import '{f.name}';" in o.read_text(encoding="utf-8", errors="ignore")
        )
    ]
    if not hits and "main.dart" not in f.name:
        out.append("ORPHAN?: " + str(f.relative_to(base)))
    if len(out) >= 25:
        break
out.append("(done, scanned %d)" % len(dart))
print("\n".join(out))