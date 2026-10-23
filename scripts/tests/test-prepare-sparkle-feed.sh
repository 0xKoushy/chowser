#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
release_dir="$test_dir/release"
mkdir "$release_dir"
printf 'test archive' > "$release_dir/Chowser-1.0.0.dmg"
printf 'test notes' > "$release_dir/Chowser-1.0.0.md"

cat > "$test_dir/generate_appcast" <<'STUB'
#!/bin/bash
set -euo pipefail
prefix=''
output=''
while (($#)); do
    case "$1" in
        --download-url-prefix) prefix="$2"; shift 2 ;;
        -o) output="$2"; shift 2 ;;
        *) release_dir="$1"; shift ;;
    esac
done
cat >/dev/null
length="$(stat -f %z "$release_dir/Chowser-1.0.0.dmg")"
cat > "$output" <<XML
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>123</sparkle:version><sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
<enclosure url="${prefix}Chowser-1.0.0.dmg" length="$length" sparkle:edSignature="stub"/>
</item></channel></rss><!-- sparkle-signatures: stub -->
XML
STUB
chmod +x "$test_dir/generate_appcast"

env -u GITHUB_REPOSITORY SPARKLE_PRIVATE_KEY=stub \
    SPARKLE_GENERATE_APPCAST="$test_dir/generate_appcast" \
    "$repo_root/scripts/prepare-sparkle-feed.sh" 1.0.0 123 "$release_dir" >/dev/null
grep -Fq 'https://github.com/0xKoushy/chowser/releases/download/v1.0.0/Chowser-1.0.0.dmg' \
    "$release_dir/appcast.xml"
echo 'Fork release URL verified in generated appcast'
