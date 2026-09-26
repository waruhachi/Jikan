#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 DIRECTORY_CONTAINING_tt80_AND_ttl.mlmodelc" >&2
    exit 2
fi

source_dir=$1
for name in tt80 ttl; do
    test -f "$source_dir/$name.mlmodelc/model.espresso.net"
    test -f "$source_dir/$name.mlmodelc/model.espresso.weights"
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
destination="$project_dir/layout/Library/Tweak Support/Jikan/Models/iOS260"
staging="$destination.staging"
rm -rf "$staging"
mkdir -p "$staging"
cp -R "$source_dir/tt80.mlmodelc" "$source_dir/ttl.mlmodelc" "$staging/"

python3 - "$staging" <<'PY'
import hashlib
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
checksums = {}
for kind in ("tt80", "ttl"):
    for filename in ("model.espresso.net", "model.espresso.weights"):
        relative = f"{kind}/{filename}"
        data = (root / f"{kind}.mlmodelc" / filename).read_bytes()
        checksums[relative] = hashlib.sha256(data).hexdigest()
manifest = {
    "Revision": "iOS260",
    "TT80ModelID": "bkwqiw7f79",
    "TTLModelID": "k5wmzvi5mm",
    "FeatureSchema": 1,
    "SHA256": checksums,
}
with (root / "Manifest.plist").open("wb") as file:
    plistlib.dump(manifest, file)
PY

rm -rf "$destination"
mv "$staging" "$destination"
echo "Staged private models at $destination"
