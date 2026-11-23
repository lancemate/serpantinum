pragma Singleton
import QtQuick
import Quickshell.Io
import "../../"

Item {
    id: root

    // Persisted list of every app window ever seen, in first-seen order: [{class, label, enabled}].
    // New apps are appended with enabled=false -- nothing inhibits sleep until explicitly turned on
    // in the tray popup, matching the Tray Icons section's "show everything, you decide" model.
    readonly property var knownApps: {
        let v = Config.getSetting("idle.inhibitApps", []);
        return Array.isArray(v) ? v : [];
    }

    // [{class, title}] for currently open windows, refreshed every poll.
    property var runningClients: []

    // What the popup actually shows: enabled entries stay visible even when not running (so you
    // can turn one off without relaunching the app), but a disabled entry that isn't currently
    // open drops out of view -- otherwise every one-off window ever opened would sit in this list
    // forever. Nothing is lost: knownApps above still remembers it, so if it runs again later it
    // reappears with whatever state it had, instead of being re-added as a fresh duplicate.
    readonly property var visibleApps: {
        return root.knownApps.filter(a => a.enabled || root.runningClients.some(r => r.class === a.class));
    }

    readonly property bool anyEnabledAppRunning: {
        for (let i = 0; i < root.runningClients.length; i++) {
            let cls = root.runningClients[i].class;
            let known = root.knownApps.find(a => a.class === cls);
            if (known && known.enabled) return true;
        }
        return false;
    }

    function setEnabled(cls, enabled) {
        if (!cls) return;
        let next = root.knownApps.slice();
        let idx = next.findIndex(a => a.class === cls);
        if (idx === -1) return;
        next[idx] = Object.assign({}, next[idx], { enabled: enabled });
        Config.setSetting("idle.inhibitApps", next);
    }

    function registerSeen(cls, label) {
        if (!cls) return;
        let idx = root.knownApps.findIndex(a => a.class === cls);
        if (idx !== -1) {
            if (root.knownApps[idx].label !== label) {
                let next = root.knownApps.slice();
                next[idx] = Object.assign({}, next[idx], { label: label });
                Config.setSetting("idle.inhibitApps", next);
            }
            return;
        }
        let next = root.knownApps.slice();
        next.push({ class: cls, label: label, enabled: false });
        Config.setSetting("idle.inhibitApps", next);
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clientsProc.running = true
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let list = JSON.parse(text);
                    let seen = {};
                    let out = [];
                    for (let i = 0; i < list.length; i++) {
                        let c = list[i];
                        let cls = (c.class || "").toString().trim();
                        if (!cls || seen[cls]) continue;
                        seen[cls] = true;
                        let title = (c.title || cls).toString().trim();
                        out.push({ class: cls, title: title });
                        root.registerSeen(cls, title);
                    }
                    root.runningClients = out;
                } catch (e) {}
            }
        }
    }
}
