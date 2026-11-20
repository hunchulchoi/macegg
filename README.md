# macegg

macOS command-line tool and Finder Quick Actions for EGG archives (ESTsoft ALZip format).

- **Compress**: native Swift EGG writer (Deflate, falls back to Store per 4 MB block; UTF-8/NFC filenames).
- **Extract**: delegates to `unegg` (supports AZO, LZMA, bzip2, encryption, `.alz`).

## Install

```sh
./install.sh
```

Installs `~/.local/bin/macegg` and two Finder Quick Actions: **EGG로 압축**, **EGG 풀기**
(Finder right-click → Quick Actions / Services). Extraction requires `unegg` on PATH,
`/opt/homebrew/bin`, or `/usr/local/bin`.

## Usage

```sh
macegg folder                      # -> folder.egg
macegg -o bundle.egg a.txt dir/    # multiple items
macegg -v folder                   # verbose

macegg -x archive.egg              # extract next to the archive
macegg -x -C dest a.egg b.alz      # extract into dest/
macegg -x -p PASSWORD archive.egg  # encrypted archive
```

Existing files are never overwritten; a numbered name (`name 2`) is used instead.
