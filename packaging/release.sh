#!/usr/bin/env bash
# Cut a release: tag it, then fill the formula's url and sha256 from the tarball
# GitHub generates for that tag.
#
#   bash packaging/release.sh 0.8.0
#
# Separate from the formula because a checksum is a fact about a file that
# exists. Writing one by hand before the tag is written is how a formula ends up
# claiming a hash that matches nothing, and Homebrew's error for that names the
# hash rather than the mistake.
set -euo pipefail

VER="${1:?用法: bash packaging/release.sh <version>   例如 0.8.0}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OWNER=jackiectl
NAME=tailbell
URL="https://github.com/$OWNER/$NAME/archive/refs/tags/v$VER.tar.gz"

cd "$REPO"

echo "==> 1/4 版本号对齐"
/usr/bin/python3 - "$VER" <<'PYEOF'
import json, sys, io
ver = sys.argv[1]
for path, key in ((".claude-plugin/plugin.json", "version"),
                  ("package.json", "version")):
    try:
        with io.open(path, encoding="utf-8") as f:
            d = json.load(f)
    except IOError:
        continue
    d[key] = ver
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print("    %s -> %s" % (path, ver))
PYEOF

echo "==> 2/4 全部测试必须通过 —— 没测过的东西不发版"
bash tests/run-tests.sh > /dev/null
echo "    通过"

echo "==> 3/4 打标签 v$VER"
git add -A
git commit -m "release: v$VER" || true
git tag -a "v$VER" -m "tailbell v$VER"
echo "    已打标签。推送后 GitHub 才会生成 tarball:"
echo "        git push && git push --tags"

echo "==> 4/4 等 tarball 出现后,回填 formula"
cat <<NEXT

    curl -fsSL "$URL" | shasum -a 256

  把得到的 hash 和下面两行填进 Formula/tailbell.rb 的 head 之上:

    url "$URL"
    sha256 "<上面那个 hash>"

  在此之前 formula 只支持 brew install --HEAD,这是刻意的:
  校验和是关于一个已经存在的文件的事实,不是可以预先写下的东西。
NEXT
