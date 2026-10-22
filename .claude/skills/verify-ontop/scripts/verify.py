#!/usr/bin/env python3
"""Drive ontop on this Mac the way a user would and record evidence.

    verify.py doctor                 read-only: is this Mac ready for a run?
    verify.py run [FEATURE ...]      build, launch, drive the features (default: all), clean up
    verify.py run --keep FEATURE     same, but leave the app, targets and cover up afterwards
    verify.py cleanup RUN_DIR        tear down what a run started (after --keep or a crash)

Features: launch-quit, pin-hotkey, pin-menu, mirror-visibility, click-through,
double-press, desktops. Evidence lands in build/verify/runs/<timestamp>/ and survives cleanup.
Exit status 0 when every check passed, 1 when any failed, 2 when the run could not start.
"""

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent
REPO = SKILL.parents[2]
PROBE = SKILL / "scripts" / "probe"
APP = REPO / "build" / "ontop.app"
APP_BIN = APP / "Contents" / "MacOS" / "ontop"
INSTALLED = Path("/Applications/ontop.app")
RUNS = REPO / "build" / "verify" / "runs"
BUNDLE = "io.github.eladefrati.ontop"
FEATURES = ["launch-quit", "pin-hotkey", "pin-menu", "mirror-visibility", "click-through", "double-press", "desktops"]

# Where the throwaway windows go, in global top-left coordinates on the main display.
TARGET_FRAME = (160, 140, 640, 420)
TARGET_B_FRAME = (240, 220, 560, 360)
COVER_FRAME = (100, 100, 900, 560)
FLOATING_LAYER = 3  # NSWindow.Level.floating: ontop's mirrors and nothing else of ontop's
CONTEXT_MENU_LAYER = 101  # NSWindow.Level.popUpMenu
ESCAPE = 53  # kVK_Escape


class Abort(Exception):
    """The run cannot go on; cleanup still runs."""


# ---------------------------------------------------------------- plumbing

def sh(*args, check=True, timeout=600):
    r = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise Abort(f"{' '.join(map(str, args))} failed ({r.returncode}): {r.stderr.strip() or r.stdout.strip()}")
    return r


def probe(*args):
    r = sh(PROBE, *args, check=False)
    if r.returncode != 0:
        raise Abort(f"probe {' '.join(map(str, args))}: {r.stderr.strip()}")
    return json.loads(r.stdout)


def wait_until(fn, timeout=5.0, interval=0.1):
    """Polls fn until it returns something truthy; returns the last value either way."""
    deadline = time.time() + timeout
    value = fn()
    while not value and time.time() < deadline:
        time.sleep(interval)
        value = fn()
    return value


def ontop_processes():
    """Every running ontop, with the bundle it was launched from."""
    r = sh("pgrep", "-x", "ontop", check=False)
    out = []
    for pid in r.stdout.split():
        path = sh("ps", "-o", "comm=", "-p", pid, check=False).stdout.strip()
        out.append({"pid": int(pid), "path": path})
    return out


def mirrors(pid):
    return [w for w in probe("windows", "--pid", pid, "--all") if w["layer"] == FLOATING_LAYER]


def follow_setting():
    r = sh("defaults", "read", BUNDLE, "followsDesktops", check=False)
    return r.stdout.strip() == "1"


def target_line(name, i):
    return f"line {i:02d}  ontop verification target {name}, a throwaway document.\n"


def pid_of(name):
    r = sh("pgrep", "-x", name, check=False)
    pids = r.stdout.split()
    return int(pids[0]) if pids else None


# ---------------------------------------------------------------- doctor

def doctor(quiet=False):
    """Returns a list of problems; empty means the Mac is ready to drive."""
    problems, notes = [], []
    version = sh("sw_vers", "-productVersion").stdout.strip()
    if not version.startswith("26."):
        problems.append(f"macOS {version}; ontop needs 26")
    trusted = probe("trusted")
    if not trusted["accessibility"]:
        problems.append("the terminal has no Accessibility access; the probe cannot press keys or read menus")
    if not trusted["screenRecording"]:
        problems.append("the terminal has no Screen Recording access; screencapture -l and window titles fail")
    if APP.exists():
        sig = sh("codesign", "-dvv", APP, check=False).stderr
        if "Authority=Apple Development" not in sig:
            problems.append("build/ontop.app is not signed with an Apple Development certificate; "
                            "its permission grants would not match and onboarding would block the run")
    else:
        notes.append("build/ontop.app does not exist yet; run builds it")
    for proc in ontop_processes():
        pins = len(mirrors(proc["pid"]))
        if proc["path"].startswith(str(APP)):
            problems.append(f"a test-build ontop is already running (pid {proc['pid']}); another run may own it, "
                            f"or a crashed run left it: verify.py cleanup <run dir>")
        elif pins:
            problems.append(f"ontop pid {proc['pid']} ({proc['path']}) holds {pins} pin(s); it is in use, do not quit it")
        else:
            notes.append(f"ontop pid {proc['pid']} ({proc['path']}) runs with no pins; a run quits it and reopens it")
    chord = sh("defaults", "read", BUNDLE, "chord", check=False)
    if chord.returncode == 0:
        problems.append("a custom shortcut is set; the probe presses only the default Ctrl+Option+P")
    desk = probe("desktops")
    notes.append(f"desktop {desk['active'].get('desktop')} of {len(desk['all'])} is active; "
                 f"Follow Across Desktops is {'on' if follow_setting() else 'off'}")
    if len(desk["all"]) < 2:
        problems.append("only one desktop exists; the desktops feature needs two")
    if not quiet:
        for p in problems:
            print(f"PROBLEM  {p}")
        for n in notes:
            print(f"ok       {n}")
        print("READY" if not problems else "NOT READY")
    return problems


# ---------------------------------------------------------------- a run

class Run:
    def __init__(self, keep=False):
        self.keep = keep
        self.dir = RUNS / datetime.now().strftime("%Y-%m-%dT%H%M%S")
        self.dir.mkdir(parents=True)
        self.state = {"keep": keep}
        self.results = []
        self.step_no = 0
        self.log_proc = None
        self.cover_proc = None

    # state survives in state.json so `verify.py cleanup` can finish a crashed run
    def save(self, **kw):
        self.state.update(kw)
        (self.dir / "state.json").write_text(json.dumps(self.state, indent=2))

    def step(self, feature, action, **data):
        self.step_no += 1
        rec = {"n": self.step_no, "t": round(time.time(), 3), "feature": feature, "action": action, **data}
        with open(self.dir / "steps.jsonl", "a") as f:
            f.write(json.dumps(rec) + "\n")
        return rec

    def check(self, feature, name, ok, detail=""):
        self.results.append({"feature": feature, "check": name, "ok": bool(ok), "detail": detail})
        self.step(feature, "check", check=name, ok=bool(ok), detail=detail)
        print(f"{'PASS' if ok else 'FAIL'}  {feature}: {name}" + (f"  ({detail})" if detail else ""), flush=True)
        return bool(ok)

    def capture(self, feature, wid, label):
        """screencapture -l of one window, plus how much of it is not transparent."""
        path = self.dir / f"{self.step_no + 1:03d}-{feature}-{label}.png"
        r = sh("screencapture", "-l", wid, "-o", "-x", path, check=False)
        opaque = probe("opaque", path)["opaque"] if r.returncode == 0 and path.exists() else None
        self.step(feature, "screencapture", window=wid, file=path.name, opaque=opaque,
                  error=None if r.returncode == 0 else r.stderr.strip())
        return opaque

    # ------------------------------------------------ log

    def start_log(self):
        out = open(self.dir / "ontop.log", "w")
        self.log_proc = subprocess.Popen(
            ["/usr/bin/log", "stream", "--level", "info", "--style", "compact",
             "--predicate", f'subsystem == "{BUNDLE}"'], stdout=out, stderr=subprocess.STDOUT)
        self.save(log_pid=self.log_proc.pid)
        time.sleep(1.0)  # log stream takes a moment before it delivers anything

    def log_lines(self):
        pid = self.state.get("ontop_pid")
        lines = (self.dir / "ontop.log").read_text(errors="replace").splitlines()
        return [l for l in lines if pid and f"ontop[{pid}:" in l]

    def log_count(self, pattern):
        return sum(1 for l in self.log_lines() if re.search(pattern, l))

    def wait_log(self, pattern, at_least, timeout=5.0):
        return wait_until(lambda: self.log_count(pattern) >= at_least, timeout)

    # ------------------------------------------------ app

    def launch(self, feature):
        before = {p["pid"] for p in ontop_processes()}
        sh("open", APP)
        proc = wait_until(lambda: [p for p in ontop_processes() if p["pid"] not in before and p["path"].startswith(str(APP))], 10)
        if not proc:
            raise Abort("build/ontop.app did not start")
        pid = proc[0]["pid"]
        self.save(ontop_pid=pid)
        ready = self.wait_log(r"hotkey registered", 1, timeout=10)
        unavailable = self.log_count(r"hotkey .* unavailable")
        self.step(feature, "launch", pid=pid, ready=bool(ready))
        if not ready:
            wins = probe("windows", "--pid", pid, "--all")
            raise Abort(f"ontop pid {pid} never logged 'hotkey registered' "
                        f"(unavailable: {unavailable}; its windows: {[w['name'] for w in wins]}). "
                        "A pin.slash icon ('ontop needs … access' in its menu) means the build's permissions are not granted; ask the user.")
        return pid

    def menu(self, feature, *args):
        rec = probe("menu", *args)
        self.step(feature, "menu " + " ".join(map(str, args)), result=rec)
        return rec

    def menu_items(self, feature):
        return self.menu(feature, "list", self.state["ontop_pid"])

    def menu_state(self, feature, title):
        return next((i for i in self.menu_items(feature) if i["title"] == title), None)

    def quit_app(self, feature):
        pid = self.state["ontop_pid"]
        self.menu(feature, "click", pid, "Quit ontop")
        gone = wait_until(lambda: pid not in {p["pid"] for p in ontop_processes()}, 5)
        self.step(feature, "quit", pid=pid, exited=bool(gone))
        if gone:
            self.save(ontop_pid=None)
        return gone

    def my_mirrors(self):
        return mirrors(self.state["ontop_pid"])

    def mirror(self):
        ms = self.my_mirrors()
        return ms[0] if len(ms) == 1 else None

    # ------------------------------------------------ throwaway windows

    def open_target(self, name, frame):
        """A new TextEdit document from a scratch file in the run dir. Returns its window."""
        targets = self.dir / "targets"
        targets.mkdir(exist_ok=True)
        path = targets / f"{name}.txt"
        path.write_text("".join(target_line(name, i) for i in range(40)))
        was_running = pid_of("TextEdit") is not None
        if not was_running:
            self.save(textedit_launched=True)
        sh("open", "-a", "TextEdit", path)
        te = wait_until(lambda: pid_of("TextEdit"), 10)
        win = wait_until(lambda: next((w for w in probe("ax-windows", te) if w["title"].startswith(name)), None), 10)
        if not win:
            raise Abort(f"TextEdit did not open {path.name}")
        self.save(targets=self.state.get("targets", []) + [{"title": win["title"], "file": str(path)}])
        probe("ax-place", te, win["title"], *frame)
        cg = wait_until(lambda: next((w for w in probe("windows", "--pid", te) if w["name"] == win["title"]), None), 5)
        if not cg:
            raise Abort(f"no on-screen window for {win['title']}")
        t = {"pid": te, "title": win["title"], "id": cg["id"], "bounds": cg["bounds"], "desktops": cg["desktops"]}
        self.step("setup", "open target", target=t)
        return t

    def start_cover(self):
        self.cover_proc = subprocess.Popen([str(PROBE), "cover", *map(str, COVER_FRAME), "--title", "ontop-verify cover"],
                                           stdout=subprocess.PIPE, text=True)
        info = json.loads(self.cover_proc.stdout.readline())
        self.save(cover_pid=info["pid"])
        self.cover = info
        self.step("setup", "start cover", cover=info)
        return info

    def front(self):
        return probe("front")["pid"]

    def raise_target(self, feature, t):
        probe("ax-raise", t["pid"], t["title"])
        ok = wait_until(lambda: self.front() == t["pid"], 3)
        self.step(feature, "raise target", target=t["title"], front=self.front())
        return ok

    def raise_cover(self, feature):
        probe("activate", self.cover["pid"])
        ok = wait_until(lambda: self.front() == self.cover["pid"], 3)
        self.step(feature, "raise cover", front=self.front())
        return ok

    def hotkey(self, feature, count=1, gap_ms=0):
        rec = probe("hotkey", "--count", count, "--gap-ms", gap_ms)
        self.step(feature, "hotkey", **rec)

    def unpin_all(self, feature):
        item = self.menu_state(feature, "Unpin All")
        if item and item["enabled"]:
            self.menu(feature, "click", self.state["ontop_pid"], "Unpin All")
            wait_until(lambda: not self.my_mirrors(), 3)

    def shown(self, m):
        return m and m["alpha"] == 1 and m["onscreen"]

    def hidden(self, m):
        return m and m["alpha"] == 0


# ---------------------------------------------------------------- features

def f_launch_quit(run, t):
    F = "launch-quit"
    items = run.menu_items(F)
    titles = [i["title"] for i in items]
    run.check(F, "menu bar item opens the ontop menu", "Quit ontop" in titles and "Pin Frontmost Window" in titles)
    version = next((x for x in titles if x.startswith("ontop ")), "")
    plist = sh("defaults", "read", APP / "Contents" / "Info.plist", "CFBundleShortVersionString").stdout.strip()
    run.check(F, "menu shows the built version", version == f"ontop {plist}", version)
    run.check(F, "Quit ontop ends the process", run.quit_app(F))
    pid = run.launch(F)
    run.check(F, "relaunch reaches ready", bool(pid), f"pid {pid}")


def f_pin_hotkey(run, t):
    F = "pin-hotkey"
    run.check(F, "target is frontmost", run.raise_target(F, t))
    pinned = run.log_count(rf"pinned .*\({t['id']}\)")
    run.hotkey(F)
    run.check(F, "hotkey logs the pin", run.wait_log(rf"pinned .*\({t['id']}\)", pinned + 1))
    m = wait_until(run.mirror, 3)
    run.check(F, "one mirror window exists, over the target", m and m["bounds"] == t["bounds"],
              m and f"mirror {m['id']} at {m['bounds']}, target at {t['bounds']}")
    item = run.menu_state(F, t["title"])
    run.check(F, "menu shows the target checked", item and item["checked"])
    run.raise_target(F, t)
    unpinned = run.log_count(rf"unpinned {t['id']}\b")
    run.hotkey(F)
    run.check(F, "second hotkey press logs the unpin", run.wait_log(rf"unpinned {t['id']}\b", unpinned + 1))
    run.check(F, "mirror is gone", wait_until(lambda: not any(w["onscreen"] for w in run.my_mirrors()), 3))
    item = run.menu_state(F, t["title"])
    run.check(F, "menu shows the target unchecked", item and not item["checked"])


def f_pin_menu(run, t):
    F = "pin-menu"
    pid = run.state["ontop_pid"]
    pinned = run.log_count(rf"pinned .*\({t['id']}\)")
    run.menu(F, "click", pid, t["title"], "--section", "TextEdit")
    run.check(F, "choosing the window in the menu pins it", run.wait_log(rf"pinned .*\({t['id']}\)", pinned + 1))
    run.check(F, "a mirror exists", wait_until(run.mirror, 3))
    item = run.menu_state(F, t["title"])
    run.check(F, "menu shows it checked", item and item["checked"])
    unpinned = run.log_count(rf"unpinned {t['id']}\b")
    run.menu(F, "click", pid, t["title"], "--section", "TextEdit")
    run.check(F, "choosing it again unpins it", run.wait_log(rf"unpinned {t['id']}\b", unpinned + 1))
    run.check(F, "mirror is gone", wait_until(lambda: not any(w["onscreen"] for w in run.my_mirrors()), 3))

    run.raise_target(F, t)
    run.menu(F, "click", pid, "Pin Frontmost Window")
    run.check(F, "Pin Frontmost Window pins the window that was in front",
              run.wait_log(rf"pinned .*\({t['id']}\)", pinned + 2))
    unpin_all = run.menu_state(F, "Unpin All")
    run.check(F, "Unpin All is enabled with a pin", unpin_all and unpin_all["enabled"])
    run.menu(F, "click", pid, "Unpin All")
    run.check(F, "Unpin All unpins it", run.wait_log(rf"unpinned {t['id']}\b", unpinned + 2))
    unpin_all = run.menu_state(F, "Unpin All")
    run.check(F, "Unpin All is disabled with no pins", unpin_all and not unpin_all["enabled"])


def f_mirror_visibility(run, t):
    F = "mirror-visibility"
    run.raise_target(F, t)
    run.hotkey(F)
    m = wait_until(run.mirror, 3)
    if not run.check(F, "target pinned", m):
        return
    m = wait_until(lambda: (lambda x: x if run.hidden(x) else None)(run.mirror()), 2) or run.mirror()
    run.check(F, "mirror hidden while the pinned window is frontmost", run.hidden(m), f"alpha {m['alpha']}")
    run.capture(F, m["id"], "hidden-target-front")
    shown = run.log_count(r"\[.*:mirror\] shown")
    run.check(F, "cover app is frontmost", run.raise_cover(F))
    m = wait_until(lambda: (lambda x: x if run.shown(x) else None)(run.mirror()), 3) or run.mirror()
    run.check(F, "mirror shown while another app is frontmost", run.shown(m), f"alpha {m['alpha']}, onscreen {m['onscreen']}")
    run.check(F, "log says shown", run.wait_log(r"\[.*:mirror\] shown", shown + 1))
    time.sleep(0.5)  # first frames
    opaque = run.capture(F, m["id"], "shown-cover-front")
    run.capture(F, run.cover["window"], "cover")
    run.check(F, "captured mirror carries the window's content", opaque is not None and opaque > 0.9, f"opaque {opaque}")
    hidden = run.log_count(r"\[.*:mirror\] hidden")
    run.raise_target(F, t)
    m = wait_until(lambda: (lambda x: x if run.hidden(x) else None)(run.mirror()), 3) or run.mirror()
    run.check(F, "mirror hidden again once the pinned window is frontmost", run.hidden(m), f"alpha {m['alpha']}")
    run.check(F, "log says hidden", run.wait_log(r"\[.*:mirror\] hidden", hidden + 1))
    run.unpin_all(F)


def f_click_through(run, t):
    F = "click-through"
    run.raise_target(F, t)
    run.hotkey(F)
    if not run.check(F, "target pinned", wait_until(run.mirror, 3)):
        return
    run.raise_cover(F)
    m = wait_until(lambda: (lambda x: x if run.shown(x) else None)(run.mirror()), 3)
    if not run.check(F, "mirror shown over the cover", m):
        run.unpin_all(F)
        return
    time.sleep(0.5)
    before = probe("ax-caret", t["pid"], t["title"])
    run.step(F, "caret before", **before)
    run.capture(F, m["id"], "mirror-before-click")
    # A point in the text, well below the title bar: about line 8 of the document.
    x, y = m["bounds"][0] + 120, m["bounds"][1] + 150
    clicks = run.log_count(r"click at .*forwarding")
    rec = probe("click", x, y)
    run.step(F, "click mirror", **rec)
    run.check(F, "the click landed on the mirror", rec["topWindowBeforeClick"].get("id") == m["id"],
              f"top window {rec['topWindowBeforeClick'].get('id')} ({rec['topWindowBeforeClick'].get('owner')})")
    run.check(F, "log says the click was forwarded", run.wait_log(r"click at .*forwarding", clicks + 1))
    run.check(F, "the real window is frontmost", wait_until(lambda: run.front() == t["pid"], 3))
    after = wait_until(lambda: (lambda c: c if c["location"] != before["location"] else None)(probe("ax-caret", t["pid"], t["title"])), 2) \
        or probe("ax-caret", t["pid"], t["title"])
    run.step(F, "caret after", **after)
    # Every line of the target has the same length, so the caret's offset names the line clicked.
    line = after["location"] // len(target_line(t["title"].removesuffix(".txt"), 0))
    run.check(F, "the click moved the insertion point to the clicked line of the real window",
              after["location"] != before["location"] and 3 <= line <= 8,
              f"offset {before['location']} -> {after['location']}, line {line}; the click was about line 5")
    m = run.mirror()
    run.check(F, "mirror hidden after the click", run.hidden(m), m and f"alpha {m['alpha']}")

    line_len = len(target_line(t["title"].removesuffix(".txt"), 0))
    caret = after

    # A shift-click extends the selection from the insertion point to the clicked line.
    m = show_mirror_again(run, F)
    if m:
        rec = probe("click", m["bounds"][0] + 120, m["bounds"][1] + 250, "--flags", "shift")
        run.step(F, "shift-click mirror", **rec)
        sel = wait_selection(run, F, t, lambda c: c["length"] > 0)
        end_line = (sel["location"] + sel["length"]) // line_len
        run.check(F, "a shift-click extends the selection from the insertion point to the clicked line",
                  sel["location"] == caret["location"] and end_line >= caret["location"] // line_len + 4,
                  f"selection {sel['location']}+{sel['length']}, from line {sel['location'] // line_len} to {end_line}; "
                  f"the click was 100 pt below the first one")

    # A double-click selects the word under the point.
    m = show_mirror_again(run, F)
    if m:
        rec = probe("click", m["bounds"][0] + 150, m["bounds"][1] + 150, "--count", 2)
        run.step(F, "double-click mirror", **rec)
        sel = wait_selection(run, F, t, lambda c: c["length"] > 0 and c["location"] // line_len <= 7)
        text = target_line(t["title"].removesuffix(".txt"), sel["location"] // line_len)
        col = sel["location"] % line_len
        word = text[col:col + sel["length"]]
        whole = word.isalpha() and (col == 0 or not text[col - 1].isalpha()) and not text[col + len(word)].isalpha()
        run.check(F, "a double-click selects the clicked word", whole and 3 <= sel["location"] // line_len <= 7,
                  f"selected {word!r} on line {sel['location'] // line_len}")

    # A right-click opens the window's context menu at the point.
    m = show_mirror_again(run, F)
    if m:
        def context_menus():
            return [w for w in probe("windows", "--pid", t["pid"]) if w["layer"] == CONTEXT_MENU_LAYER]
        x, y = m["bounds"][0] + 150, m["bounds"][1] + 200
        rec = probe("click", x, y, "--right")
        run.step(F, "right-click mirror", **rec)
        menus = wait_until(context_menus, 3)
        run.step(F, "context menus", menus=menus)
        run.check(F, "a right-click opens the window's context menu at the point",
                  menus and abs(menus[0]["bounds"][0] - x) < 40,
                  menus and f"menu at {menus[0]['bounds']}, click at {[x, y]}")
        probe("key", ESCAPE)
        run.check(F, "Escape closes the context menu", wait_until(lambda: not context_menus(), 3))

    # A drag selects the dragged lines once the button is released.
    m = show_mirror_again(run, F)
    if m:
        x, y = m["bounds"][0], m["bounds"][1]
        rec = probe("drag", x + 40, y + 150, x + 300, y + 250)
        run.step(F, "drag on mirror", **rec)
        run.check(F, "the drag started on the mirror", rec["topWindowBeforeDrag"].get("id") == m["id"])
        sel = wait_selection(run, F, t, lambda c: c["length"] > line_len)
        start_line, end_line = sel["location"] // line_len, (sel["location"] + sel["length"]) // line_len
        run.check(F, "a drag selects the dragged lines",
                  start_line == caret["location"] // line_len and end_line >= start_line + 4,
                  f"selection {sel['location']}+{sel['length']}, lines {start_line} to {end_line}; "
                  f"the drag ran from the first click's line to 100 pt below it")
    run.unpin_all(F)


def show_mirror_again(run, F):
    """The cover in front, so the pinned target's mirror shows again with a frame."""
    run.raise_cover(F)
    m = wait_until(lambda: (lambda x: x if run.shown(x) else None)(run.mirror()), 3)
    if run.check(F, "mirror shown over the cover again", m):
        time.sleep(0.5)
    return m


def wait_selection(run, F, t, done):
    """The target's selection once `done` holds for it, or after 3 s."""
    sel = wait_until(lambda: (lambda c: c if done(c) else None)(probe("ax-caret", t["pid"], t["title"])), 3) \
        or probe("ax-caret", t["pid"], t["title"])
    run.step(F, "selection", **sel)
    return sel


def f_double_press(run, t):
    F = "double-press"
    # 40 to 150 ms covers a person's quick double press. 0 ms is a stress case faster than any
    # person, kept because it lands inside the pin's async round trip to ScreenCaptureKit.
    for gap in (0, 40, 80, 150):
        run.unpin_all(F)
        run.raise_target(F, t)
        pinned = run.log_count(rf"pinned .*\({t['id']}\)")
        unpinned = run.log_count(rf"unpinned {t['id']}\b")
        presses = run.log_count(r"hotkey pressed")
        run.hotkey(F, count=2, gap_ms=gap)
        time.sleep(2.0)
        p = run.log_count(rf"pinned .*\({t['id']}\)") - pinned
        u = run.log_count(rf"unpinned {t['id']}\b") - unpinned
        k = run.log_count(r"hotkey pressed") - presses
        ms = run.my_mirrors()
        run.step(F, "after double press", gap_ms=gap, presses=k, pinned_logs=p, unpinned_logs=u, mirrors=ms)
        item = run.menu_state(F, t["title"])
        F = "double-press" if gap else "double-press-stress"
        run.check(F, f"{gap} ms gap: ontop received both presses", k == 2, f"{k} logged")
        run.check(F, f"{gap} ms gap: menu shows the window unpinned", item and not item["checked"],
                  item and f"checked {item['checked']}")
        run.check(F, f"{gap} ms gap: no mirror window is left ordered in", not any(w["onscreen"] for w in ms),
                  f"{sum(w['onscreen'] for w in ms)} on screen")
        run.check(F, f"{gap} ms gap: log has as many unpins as pins", p == u, f"pinned {p}, unpinned {u}")
        run.unpin_all(F)
        left = [w for w in run.my_mirrors() if w["onscreen"]]
        run.check(F, f"{gap} ms gap: Unpin All leaves no mirror behind", not left, f"{len(left)} orphan mirror(s)")
        if left:
            # Mirrors ontop no longer tracks survive Unpin All; only quitting removes them.
            # Relaunch so the next gap starts clean.
            run.step(F, "orphan mirrors after Unpin All", gap_ms=gap, mirrors=left)
            run.quit_app(F)
            run.launch(F)


def desktop_of(w):
    return [d["desktop"] for d in w["desktops"]] if w else None


def report_mirrors(run, F, label):
    rows = run.my_mirrors()
    active = probe("desktops")["active"]["desktop"]
    run.step(F, "mirror desktops", label=label, active=active,
             mirrors=[{"id": w["id"], "bounds": w["bounds"], "desktops": desktop_of(w), "alpha": w["alpha"],
                       "onscreen": w["onscreen"]} for w in rows])
    print(f"      {label}: active desktop {active}; " +
          ", ".join(f"mirror {w['id']} on {desktop_of(w)} (alpha {w['alpha']}, onscreen {w['onscreen']})" for w in rows), flush=True)
    return {w["id"]: w for w in rows}


def switch(run, F, direction):
    rec = probe("space", direction)
    run.step(F, f"space {direction}", **rec)
    return rec["switched"]


def f_desktops(run, t):
    F = "desktops"
    pid = run.state["ontop_pid"]
    desk = probe("desktops")
    home = desk["active"]["desktop"]
    away_dir = "right" if home < len([d for d in desk["all"] if d["display"] == desk["active"]["display"]]) else "left"
    back_dir = "left" if away_dir == "right" else "right"
    run.unpin_all(F)
    if follow_setting():
        run.menu(F, "click", pid, "Follow Across Desktops")

    # Pin A on the home desktop.
    run.raise_target(F, t)
    run.hotkey(F)
    if not run.check(F, "target A pinned on the home desktop", wait_until(run.mirror, 3)):
        return
    a = run.mirror()["id"]
    run.raise_cover(F)
    ms = report_mirrors(run, F, "A pinned, home")
    run.check(F, "mirror A is on the home desktop", desktop_of(ms[a]) == [home], f"{desktop_of(ms[a])} vs {home}")

    # Away: A's mirror stays home; pin B there.
    if not run.check(F, f"switched {away_dir} to another desktop", switch(run, F, away_dir)):
        return
    away = probe("desktops")["active"]["desktop"]
    ms = report_mirrors(run, F, "follow off, away")
    run.check(F, "mirror A is not on screen away from home", not ms[a]["onscreen"])
    b_target = run.open_target("ontop-verify-b", TARGET_B_FRAME)
    run.check(F, "target B opened on the away desktop", desktop_of(b_target) == [away], f"{desktop_of(b_target)}")
    run.raise_target(F, b_target)
    run.hotkey(F)
    wait_until(lambda: len(run.my_mirrors()) == 2, 3)
    ms = report_mirrors(run, F, "B pinned, away")
    b = next((i for i in ms if i != a), None)
    run.check(F, "mirror B is on the away desktop", b and desktop_of(ms[b]) == [away], b and f"{desktop_of(ms[b])}")
    if b:
        run.capture(F, b, "mirror-b-away")

    # Home again: A shows, B stays away.
    switch(run, F, back_dir)
    run.raise_cover(F)
    time.sleep(0.5)
    ms = report_mirrors(run, F, "follow off, home")
    run.check(F, "mirror A is shown at home", run.shown(ms[a]))
    run.check(F, "mirror B is not on screen at home", b and not ms[b]["onscreen"])
    run.capture(F, a, "mirror-a-home")

    # Follow Across Desktops on: A appears away too.
    run.menu(F, "click", pid, "Follow Across Desktops")
    item = run.menu_state(F, "Follow Across Desktops")
    run.check(F, "Follow Across Desktops shows checked", item and item["checked"])
    ms = report_mirrors(run, F, "follow on, home")
    switch(run, F, away_dir)
    time.sleep(0.5)
    ms = report_mirrors(run, F, "follow on, away")
    run.check(F, "mirror A is on screen on the away desktop", ms[a]["onscreen"], f"alpha {ms[a]['alpha']}")
    run.check(F, "mirror A is shown there (another window is in front)", run.shown(ms[a]))
    run.capture(F, a, "mirror-a-away-following")

    # Follow off again, from the away desktop: each mirror should return to its own desktop.
    # The window server keeps reporting an ordered-out window's last desktop, so A's
    # placement is judged by on-screen state: off screen here, on screen and shown at home.
    run.menu(F, "click", pid, "Follow Across Desktops")
    time.sleep(0.5)
    ms = report_mirrors(run, F, "follow off again, away")
    run.check(F, "after Follow off, mirror A is not on screen on the away desktop", a in ms and not ms[a]["onscreen"],
              a in ms and f"on {desktop_of(ms[a])}, onscreen {ms[a]['onscreen']}")
    run.check(F, "after Follow off, mirror B is on the away desktop only", b and desktop_of(ms[b]) == [away],
              b and f"{desktop_of(ms[b])}")
    switch(run, F, back_dir)
    run.raise_cover(F)
    time.sleep(0.5)
    ms = report_mirrors(run, F, "follow off again, home")
    run.check(F, "back home, mirror A is shown on the home desktop", run.shown(ms.get(a)) and desktop_of(ms[a]) == [home],
              a in ms and f"on {desktop_of(ms[a])}, alpha {ms[a]['alpha']}, onscreen {ms[a]['onscreen']}")
    run.check(F, "back home, mirror B is not on screen", b and not ms[b]["onscreen"])
    run.unpin_all(F)


FEATURE_FNS = {
    "launch-quit": f_launch_quit, "pin-hotkey": f_pin_hotkey, "pin-menu": f_pin_menu,
    "mirror-visibility": f_mirror_visibility, "click-through": f_click_through,
    "double-press": f_double_press, "desktops": f_desktops,
}


# ---------------------------------------------------------------- run / cleanup

def run_features(names, keep):
    problems = doctor(quiet=True)
    if problems:
        doctor()
        return 2
    run = Run(keep)
    print(f"run dir: {run.dir}", flush=True)
    run.save(started=datetime.now().isoformat(timespec="seconds"),
             follow_initial=follow_setting(), desktop_initial=probe("desktops")["active"]["desktop"])
    status = 0
    try:
        # Free the hotkey and the bundle id: the installed ontop is quit only when it has no pins
        # (the doctor refuses otherwise) and reopened in cleanup.
        for proc in ontop_processes():
            probe("menu", "click", proc["pid"], "Quit ontop")
            if not wait_until(lambda: proc["pid"] not in {p["pid"] for p in ontop_processes()}, 5):
                raise Abort(f"ontop pid {proc['pid']} did not quit")
            run.save(reopen=proc["path"].split("/Contents/MacOS/")[0])
            run.step("setup", "quit installed ontop", pid=proc["pid"], path=proc["path"])
        r = sh("make", "-C", REPO, "app")
        run.step("setup", "make app", tail=r.stdout.strip().splitlines()[-3:])
        run.start_log()
        run.launch("setup")
        target = run.open_target("ontop-verify-a", TARGET_FRAME)
        run.start_cover()
        for name in names:
            print(f"---- {name}", flush=True)
            try:
                FEATURE_FNS[name](run, target)
            except Abort as e:
                run.check(name, "feature ran to the end", False, str(e))
            if not run.state.get("ontop_pid"):
                break
    except Abort as e:
        print(f"ABORT  {e}", flush=True)
        run.step("run", "abort", error=str(e))
        status = 2
    finally:
        if not keep:
            cleanup(run.dir, run)
    failed = [r for r in run.results if not r["ok"]]
    summary = [f"# ontop verification {run.dir.name}", "",
               f"{len(run.results) - len(failed)} passed, {len(failed)} failed", ""]
    summary += [f"- {'PASS' if r['ok'] else 'FAIL'} {r['feature']}: {r['check']}" + (f" ({r['detail']})" if r['detail'] else "")
                for r in run.results]
    (run.dir / "summary.md").write_text("\n".join(summary) + "\n")
    print(f"{len(run.results) - len(failed)} passed, {len(failed)} failed; evidence in {run.dir}")
    return status or (1 if failed else 0)


def cleanup(run_dir, run=None):
    run_dir = Path(run_dir)
    state = json.loads((run_dir / "state.json").read_text())
    done = []
    pid = state.get("ontop_pid")
    alive = pid and pid in {p["pid"] for p in ontop_processes()}
    if alive:
        try:
            probe("menu", "click", pid, "Unpin All")
        except Abort:
            pass
        if state.get("follow_initial") is not None and follow_setting() != state["follow_initial"]:
            try:
                probe("menu", "click", pid, "Follow Across Desktops")
                done.append("Follow Across Desktops restored through the menu")
            except Abort:
                pass
        try:
            probe("menu", "click", pid, "Quit ontop")
        except Abort:
            pass
        if not wait_until(lambda: pid not in {p["pid"] for p in ontop_processes()}, 5):
            os.kill(pid, 15)  # the test build this run started, by pid
        done.append(f"quit test ontop {pid}")
    if state.get("follow_initial") is not None and follow_setting() != state["follow_initial"]:
        sh("defaults", "write", BUNDLE, "followsDesktops", "-bool", "true" if state["follow_initial"] else "false")
        done.append("Follow Across Desktops restored with defaults write")
    if state.get("cover_pid"):
        try:
            os.kill(state["cover_pid"], 15)
            done.append("cover closed")
        except ProcessLookupError:
            pass
    te = pid_of("TextEdit")
    for t in state.get("targets", []):
        if te:
            try:
                probe("ax-close", te, t["title"])
                done.append(f"closed {t['title']}")
            except Abort:
                pass
        Path(t["file"]).unlink(missing_ok=True)
    if (run_dir / "targets").is_dir() and not any((run_dir / "targets").iterdir()):
        (run_dir / "targets").rmdir()
    if te and state.get("textedit_launched"):
        time.sleep(0.5)
        probe("quit", te)
        done.append("quit TextEdit (this run launched it)")
    if state.get("desktop_initial"):
        for _ in range(10):
            cur = probe("desktops")["active"]["desktop"]
            if cur == state["desktop_initial"]:
                break
            probe("space", "left" if cur > state["desktop_initial"] else "right")
        done.append(f"back on desktop {probe('desktops')['active']['desktop']}")
    if state.get("log_pid"):
        try:
            time.sleep(0.5)
            os.kill(state["log_pid"], 15)
        except ProcessLookupError:
            pass
    if state.get("reopen"):
        sh("open", state["reopen"], check=False)
        done.append(f"reopened {state['reopen']}")
    state["cleaned"] = done
    (run_dir / "state.json").write_text(json.dumps(state, indent=2))
    print("cleanup: " + "; ".join(done), flush=True)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    if cmd == "doctor":
        return 1 if doctor() else 0
    if cmd == "run":
        keep = "--keep" in rest
        names = [a for a in rest if a != "--keep"] or FEATURES
        unknown = [n for n in names if n not in FEATURE_FNS]
        if unknown:
            print(f"unknown feature(s): {unknown}; known: {FEATURES}")
            return 2
        return run_features(names, keep)
    if cmd == "cleanup" and rest:
        cleanup(rest[0])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
