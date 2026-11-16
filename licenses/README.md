# License texts

Verbatim license texts for every third-party component listed in
[`../COMPONENTS.md`](../COMPONENTS.md). Nothing here is edited; the sha256 of each
file is recorded so the copies can be checked against the origin.

| File | Size | License | Taken from |
|---|---|---|---|
| `LGPL-2.1.txt` | 26 001 B | LGPL-2.1 | https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt (retrieved via the SPDX verbatim mirror, `text/LGPL-2.1-only.txt`) |
| `GPL-2.0.txt` | 17 337 B | GPL-2.0 | https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt (SPDX mirror, `text/GPL-2.0-only.txt`) |
| `LGPL-3.0.txt` | 42 098 B | LGPL-3.0 | https://www.gnu.org/licenses/lgpl-3.0.txt (SPDX mirror, `text/LGPL-3.0-only.txt`) |
| `MIT.txt` | 1 078 B | MIT | https://opensource.org/license/mit (SPDX mirror, `text/MIT.txt`) |
| `BSD-3-Clause.txt` | 1 460 B | BSD-3-Clause | https://opensource.org/license/bsd-3-clause (SPDX mirror, `text/BSD-3-Clause.txt`) |
| `Zlib.txt` | 838 B | Zlib | https://opensource.org/license/zlib (SPDX mirror, `text/Zlib.txt`) |
| `AFL-2.1.txt` | 10 602 B | AFL-2.1 | https://opensource.org/licenses/AFL-2.1 (SPDX mirror, `text/AFL-2.1.txt`) |
| `FTL.txt` | 5 979 B | FTL (FreeType) | https://opensource.org/licenses/FTL (SPDX mirror, `text/FTL.txt`) |

gnu.org and some opensource.org endpoints were not reachable over HTTPS from the build
host (TLS reset / timeout), so the texts were pulled from the SPDX license-list
repository, which republishes the same files byte-for-byte. Check a copy with:

```bash
sha256sum LGPL-2.1.txt GPL-2.0.txt LGPL-3.0.txt MIT.txt BSD-3-Clause.txt Zlib.txt AFL-2.1.txt FTL.txt
```

```
5749785c8bdefafcb5d798270ed0a967036fe2ca63dcedade1627565dfef81d2  LGPL-2.1.txt
aaf135472f81c5b4a0dca9367e5bb5e9750032b5bebe5442b36e4c0a47430df3  GPL-2.0.txt
996af0513df21f7496288951c41428a03c174e9e4a9d63665c57d670f845ccb1  LGPL-3.0.txt
b05785f9f18e6716bab63424b11454513b9943a222595b70411009202fc592b5  MIT.txt
5a93d5831e1297ab10fe643e1a631e83be392896da14ee2951285a79012df69d  BSD-3-Clause.txt
bfb1112d49db5b1daecdfef24bd7e2f3ea0bafb33aa67aa0ab51e2bf8407c03d  Zlib.txt
fbedf33db9a433cf87c6f0974f7e488599ee0c9446ed543235c99785ce7d22e6  AFL-2.1.txt
ced6622122ce451cb1ea0c3c3f507a640e2a44c075c04900ddd9fae8acb5369f  FTL.txt
```

Our own patches and scripts in this repository are provided under the same license as
the component they modify (Wine patches: LGPL-2.1; box64 patches and the build
scripts: MIT).
