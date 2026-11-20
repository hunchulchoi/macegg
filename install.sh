#!/bin/zsh
# Build macegg, install it to ~/.local/bin, and register Finder Quick Actions
# ("EGG로 압축", "EGG 풀기").
set -euo pipefail
cd "${0:A:h}"

BIN_DIR="$HOME/.local/bin"
SERVICES="$HOME/Library/Services"

swift build -c release
mkdir -p "$BIN_DIR" "$SERVICES"
install -m 755 .build/release/macegg "$BIN_DIR/macegg"
echo "installed: $BIN_DIR/macegg"

command -v unegg >/dev/null || [ -x /opt/homebrew/bin/unegg ] || [ -x /usr/local/bin/unegg ] \
  || echo "warning: unegg not found — 'EGG 풀기' needs it"

MACEGG="$BIN_DIR/macegg" SERVICES="$SERVICES" python3 -I - <<'PY'
import os, plistlib, shutil, uuid

macegg = os.environ["MACEGG"]
services = os.environ["SERVICES"]

COMPRESS = r'''M="@MACEGG@"
out=$("$M" "$@" 2>&1)
if [ $? -eq 0 ]; then
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "EGG 압축 완료"' -e 'end run' "${out:t}"
else
  osascript -e 'on run argv' -e 'display alert "EGG 압축 실패" message (item 1 of argv)' -e 'end run' "$out"
fi
'''

EXTRACT = r'''M="@MACEGG@"
done_names=()
for f in "$@"; do
  case "${f:l}" in *.egg|*.alz) ;; *) continue ;; esac
  out=$("$M" -x "$f" 2>&1); rc=$?
  if [ $rc -ne 0 ] && print -r -- "$out" | grep -qiE 'password|passwd|encrypt|암호'; then
    pw=$(osascript -e 'on run argv' -e 'text returned of (display dialog ("암호를 입력하세요: " & item 1 of argv) default answer "" with hidden answer with title "EGG 풀기")' -e 'end run' "${f:t}") || continue
    out=$("$M" -x -p "$pw" "$f" 2>&1); rc=$?
  fi
  if [ $rc -eq 0 ]; then
    done_names+=("${out:t}")
  else
    osascript -e 'on run argv' -e 'display alert ("EGG 풀기 실패: " & item 1 of argv) message (item 2 of argv)' -e 'end run' "${f:t}" "$out"
  fi
done
if [ ${#done_names} -gt 0 ]; then
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "EGG 풀기 완료"' -e 'end run' "${(j:, :)done_names}"
fi
'''

U = lambda: str(uuid.uuid4()).upper()

def make_workflow(menu, script):
    script = script.replace("@MACEGG@", macegg)
    wf = os.path.join(services, menu + ".workflow")
    shutil.rmtree(wf, ignore_errors=True)
    os.makedirs(os.path.join(wf, "Contents"))
    info = {
        "NSServices": [{
            "NSMenuItem": {"default": menu},
            "NSMessage": "runWorkflowAsService",
            "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
            "NSSendFileTypes": ["public.item"],
        }]
    }
    action = {
        "action": {
            "AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.string"]},
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": {
                "COMMAND_STRING": {}, "CheckedForUserDefaultShell": {},
                "inputMethod": {}, "shell": {}, "source": {},
            },
            "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": {
                "COMMAND_STRING": script,
                "CheckedForUserDefaultShell": True,
                "inputMethod": 1,          # pass input as arguments
                "shell": "/bin/zsh",
                "source": "",
            },
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": False,
            "CanShowWhenRun": True,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": U(), "OutputUUID": U(), "UUID": U(),
            "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
            "UnlocalizedApplications": ["Automator"],
            "arguments": {},
            "isViewVisible": 1,
            "location": "300.0:300.0",
            "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib",
        },
        "isViewVisible": 1,
    }
    doc = {
        "AMApplicationBuild": "523",
        "AMApplicationVersion": "2.10",
        "AMDocumentVersion": "2",
        "actions": [action],
        "connectors": {},
        "workflowMetaData": {
            "applicationBundleIDsByPath": {},
            "applicationPaths": [],
            "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "outputTypeIdentifier": "com.apple.Automator.nothing",
            "presentationMode": 15,
            "processesInput": False,
            "serviceApplicationBundleID": "com.apple.finder",
            "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
            "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": False,
            "systemImageName": "NSActionTemplate",
            "useAutomaticInputType": False,
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        },
    }
    with open(os.path.join(wf, "Contents", "Info.plist"), "wb") as f:
        plistlib.dump(info, f)
    with open(os.path.join(wf, "Contents", "document.wflow"), "wb") as f:
        plistlib.dump(doc, f)
    print("installed:", wf)

make_workflow("EGG로 압축", COMPRESS)
make_workflow("EGG 풀기", EXTRACT)
PY

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
echo "Finder에서 우클릭 → 빠른 동작(또는 서비스) → 'EGG로 압축' / 'EGG 풀기'"
