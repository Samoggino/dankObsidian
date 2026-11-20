import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "obs"
    signal itemsChanged

    property bool isFlatpak: true
    property var cachedVaults: []
    property string homeDir: Quickshell.env("HOME") || "/home"
    property bool enabled: true // Add this property

    property bool alwaysActive: false // New property
    property var hiddenVaults: [] // Paths of vaults hidden from the launcher
    property var vaultIcons: ({}) // path -> icon ("material:book", "unicode:📓", theme icon name)

    property string lastVaultsKey: "" // Serialized vault list, used to notify the launcher only on real changes
    property double lastReload: 0

    // Watches obsidian.json: new/removed vaults show up without reloading the shell
    property var vaultsFile: FileView {
        path: root.getStoragePath()
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseData(text())
        onLoadFailed: root.parseData("")
    }

    function getStoragePath() {
        return root.isFlatpak ? root.homeDir + "/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json" : root.homeDir + "/.config/obsidian/obsidian.json";
    }

    function refreshCache() {
        root.lastReload = Date.now();
        root.vaultsFile.reload();
    }

    function parseData(rawData) {
        let vaults = [];
        try {
            const data = rawData ? JSON.parse(rawData) : null;
            if (data && data.vaults) {
                for (var key in data.vaults) {
                    let entry = data.vaults[key];
                    if (entry && entry.path) {
                        vaults.push({
                            name: entry.path.split('/').pop(),
                            path: entry.path
                        });
                    }
                }
            }
        } catch (e) {
            console.warn("DankObsidian Error: " + e);
            return; // keep the previous list on a partial/invalid read
        }
        const vaultsKey = JSON.stringify(vaults);
        if (vaultsKey === root.lastVaultsKey)
            return;
        root.lastVaultsKey = vaultsKey;
        root.cachedVaults = vaults;
        root.notifyLauncher();
    }

    function updateSettings() {
        if (root.pluginService) {
            // Read values from JSON
            const isEnabled = root.pluginService.loadPluginData("dankObsidian", "enabled", true);
            const newIsFlatpak = root.pluginService.loadPluginData("dankObsidian", "isFlatpak", true);

            // Logic for the trigger:
            // If "Always Active" is enabled, the JSON will have "trigger": ""
            const newTrigger = root.pluginService.loadPluginData("dankObsidian", "trigger", "\\obs");

            root.enabled = isEnabled;
            root.isFlatpak = newIsFlatpak;
            root.trigger = newTrigger;

            console.log("DankObsidian Settings: Enabled =", root.enabled, "| Trigger =", root.trigger === "" ? "(Always Active)" : root.trigger);

            if (root.enabled)
                root.refreshCache();
            root.notifyLauncher(); // hidden vaults / icons may have changed
        }
    }

    // Hidden vaults and icons live in the plugin *state*, not in the settings: DMS reloads a
    // launcher plugin (and rebuilds its settings page) on every settings save, which made the
    // settings page empty itself and jump back to the top on each toggle or icon change.
    function updateState() {
        if (!root.pluginService)
            return;
        const hidden = root.pluginService.loadPluginState("dankObsidian", "hiddenVaults", []);
        root.hiddenVaults = (hidden && hidden.length !== undefined) ? Array.from(hidden) : [];
        const icons = root.pluginService.loadPluginState("dankObsidian", "vaultIcons", {});
        root.vaultIcons = (icons && typeof icons === "object") ? icons : {};
        root.notifyLauncher();
    }

    // One-time move of hiddenVaults / vaultIcons from the settings (v2.0.0) to the state
    function migrateToState() {
        const ps = root.pluginService;
        if (!ps)
            return;
        const legacyHidden = ps.loadPluginData("dankObsidian", "hiddenVaults", null);
        const legacyIcons = ps.loadPluginData("dankObsidian", "vaultIcons", null);
        const hasHidden = legacyHidden && legacyHidden.length > 0;
        const hasIcons = legacyIcons && typeof legacyIcons === "object" && Object.keys(legacyIcons).length > 0;
        if (hasHidden) {
            const current = Array.from(ps.loadPluginState("dankObsidian", "hiddenVaults", []) || []);
            ps.savePluginState("dankObsidian", "hiddenVaults", Array.from(new Set(current.concat(Array.from(legacyHidden)))));
        }
        if (hasIcons) {
            const current = ps.loadPluginState("dankObsidian", "vaultIcons", {}) || {};
            ps.savePluginState("dankObsidian", "vaultIcons", Object.assign({}, legacyIcons, current));
        }
        if (hasHidden)
            ps.savePluginData("dankObsidian", "hiddenVaults", []);
        if (hasIcons)
            ps.savePluginData("dankObsidian", "vaultIcons", {});
    }

    function init() {
        root.migrateToState();
        root.updateState();
        root.updateSettings();
    }

    onPluginServiceChanged: root.init()
    Component.onCompleted: root.init()

    property var settingsListener: Connections {
        target: root.pluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === "dankObsidian") {
                root.updateSettings();
            }
        }
        function onPluginStateChanged(pluginId) {
            if (pluginId === "dankObsidian")
                root.updateState();
        }
    }

    property var initTimer: Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: root.refreshCache()
    }

    function getItems(query) {
        if (!root.enabled)
            return []; // If the plugin is disabled, return nothing

        // Fallback in case a file change notification was missed: re-read at most every 2s
        if (Date.now() - root.lastReload > 2000)
            Qt.callLater(root.refreshCache);

        const q = query ? query.trim().toLowerCase() : "";
        return root.cachedVaults.filter(v => !root.hiddenVaults.includes(v.path) && (q === "" || v.name.toLowerCase().includes(q))).map(v => ({
                    name: v.name,
                    icon: (root.vaultIcons[v.path] || "").trim() || "obsidian",
                    comment: v.path,
                    action: "open:" + v.path,
                    vaultPath: v.path
                }));
    }

    function notifyLauncher() {
        root.itemsChanged();
        if (root.pluginService && root.pluginService.requestLauncherUpdate)
            root.pluginService.requestLauncherUpdate("dankObsidian");
    }

    function setVaultHidden(path, hidden) {
        if (!path)
            return;
        let list = root.hiddenVaults.filter(p => p !== path);
        if (hidden)
            list.push(path);
        root.hiddenVaults = list;
        if (root.pluginService)
            root.pluginService.savePluginState("dankObsidian", "hiddenVaults", list); // triggers updateState -> launcher refresh
        else
            root.notifyLauncher();
    }

    // Context menu shown in the launcher (right click / menu key on an item)
    function getContextMenuActions(item) {
        const path = item?.vaultPath || (item?.action || "").replace("open:", "");
        if (!path)
            return [];
        return [
            {
                icon: "visibility_off",
                text: "Hide vault",
                action: () => root.setVaultHidden(path, true)
            },
            {
                icon: "folder_open",
                text: "Open folder",
                closeLauncher: true,
                action: () => Quickshell.execDetached(["xdg-open", path])
            }
        ];
    }

    function executeItem(item) {
        if (!item?.action)
            return;
        const vPath = item.action.replace("open:", "");
        const uri = "obsidian://open?path=" + encodeURIComponent(vPath);

        // Using execDetached for execution as it is universal
        if (root.isFlatpak) {
            Quickshell.execDetached(["flatpak", "run", "md.obsidian.Obsidian", uri]);
        } else {
            Quickshell.execDetached(["xdg-open", uri]);
        }
    }
}