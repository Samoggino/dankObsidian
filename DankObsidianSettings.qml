import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "dankObsidian"

    // Header
    StyledText {
        width: parent.width
        text: "Obsidian Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    // Enable/Disable (automatically handled by DMS via the "enabled" key)
    ToggleSetting {
        settingKey: "enabled"
        label: "Enable Plugin"
        description: "Show Obsidian vaults in the launcher"
        defaultValue: true
    }

    // Flatpak Toggle (adds "isFlatpak": true/false to the JSON)
    ToggleSetting {
        id: flatpakToggle
        settingKey: "isFlatpak"
        label: "Obsidian as Flatpak"
        description: "Enable if Obsidian is installed via Flatpak"
        defaultValue: true
    }

    // Trigger Toggle (adds "noTrigger": true/false to the JSON and conditionally shows the StringSetting)
    ToggleSetting {
        id: noTriggerToggle
        settingKey: "noTrigger"
        label: "Always Active (No Trigger)"
        description: value ? "Vaults will always appear in the launcher." : "Use a trigger to filter vaults."
        defaultValue: false
        onValueChanged: {
            if (value) {
                root.saveValue("trigger", ""); // Disable trigger if active
            } else {
                root.saveValue("trigger", triggerSetting.value || "\\obs"); // Restore StringSetting value
            }
        }
    }

    // Trigger String (adds "trigger": "value" to the JSON)
    StringSetting {
        id: triggerSetting
        visible: !noTriggerToggle.value
        settingKey: "trigger"
        label: "Search Trigger"
        description: "Example: '\\obs' or 'ob'"
        defaultValue: "\\obs"
    }

    // ---- Vault visibility ----
    property var foundVaults: []
    property var hiddenVaults: []
    property var vaultIcons: ({})

    // Hidden vaults and icons are kept in the plugin state (see DankObsidian.qml); the legacy
    // settings values are only read as a fallback until the launcher has migrated them.
    function loadHidden() {
        const ps = root.pluginService;
        if (!ps)
            return;
        const h = ps.loadPluginState("dankObsidian", "hiddenVaults", null) ?? root.loadValue("hiddenVaults", []);
        root.hiddenVaults = (h && h.length !== undefined) ? Array.from(h) : [];
        const icons = ps.loadPluginState("dankObsidian", "vaultIcons", null) ?? root.loadValue("vaultIcons", {});
        root.vaultIcons = (icons && typeof icons === "object") ? icons : {};
    }

    // Normalizes user input: a bare emoji/symbol (non-ASCII, no prefix) becomes "unicode:<char>"
    function normalizeIcon(icon) {
        const value = (icon || "").trim();
        if (value && !/^[a-z+]+:/i.test(value) && /[^\x00-\x7F]/.test(value))
            return "unicode:" + value;
        return value;
    }

    function setIcon(path, icon) {
        const value = root.normalizeIcon(icon);
        if ((root.vaultIcons[path] || "") === value)
            return;
        let map = Object.assign({}, root.vaultIcons);
        if (value)
            map[path] = value;
        else
            delete map[path];
        root.vaultIcons = map;
        root.pluginService?.savePluginState("dankObsidian", "vaultIcons", map);
    }

    function setHidden(path, hidden) {
        let list = root.hiddenVaults.filter(p => p !== path);
        if (hidden)
            list.push(path);
        root.hiddenVaults = list;
        root.pluginService?.savePluginState("dankObsidian", "hiddenVaults", list);
    }

    property var vaultsFile: FileView {
        path: (Quickshell.env("HOME") || "/home") + (flatpakToggle.value ? "/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json" : "/.config/obsidian/obsidian.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                let vaults = [];
                for (const key in (data?.vaults || {})) {
                    const entry = data.vaults[key];
                    if (entry?.path)
                        vaults.push({ name: entry.path.split('/').pop(), path: entry.path });
                }
                vaults.sort((a, b) => a.name.localeCompare(b.name));
                root.foundVaults = vaults;
            } catch (e) {
                console.warn("DankObsidian Settings: cannot parse obsidian.json:", e);
                root.foundVaults = [];
            }
        }
        onLoadFailed: root.foundVaults = []
    }

    property var hiddenListener: Connections {
        target: root.pluginService
        function onPluginStateChanged(pluginId) {
            if (pluginId === "dankObsidian")
                root.loadHidden();
        }
    }

    // DMS assigns pluginService after the page is created
    onPluginServiceChanged: if (root.pluginService) Qt.callLater(root.loadHidden)
    Component.onCompleted: Qt.callLater(root.loadHidden)

    Column {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            width: parent.width
            text: "Vaults"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: root.foundVaults.length === 0 ? "No vaults found in obsidian.json (check the Flatpak setting)." : "Turn off a vault to hide it from the launcher (also possible from the launcher's context menu). Click a vault's icon to change it."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.foundVaults

            Column {
                id: vaultRow
                required property var modelData
                readonly property string rawIcon: (root.vaultIcons[modelData.path] || "").trim()
                readonly property string iconValue: rawIcon || "obsidian"
                property bool editing: false

                function confirmIcon() {
                    iconField.text = root.normalizeIcon(iconField.text);
                    root.setIcon(vaultRow.modelData.path, iconField.text);
                    iconField.focus = false;
                    vaultRow.editing = false;
                }
                width: parent.width
                spacing: Theme.spacingS

                Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    // Clickable icon with a pencil badge: opens the icon editor
                    Rectangle {
                        id: iconButton
                        width: 44
                        height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.cornerRadius
                        color: iconArea.containsMouse || vaultRow.editing ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        border.width: vaultRow.editing ? 2 : 0
                        border.color: Theme.primary

                        AppIconRenderer {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            iconSize: 28
                            iconValue: vaultRow.iconValue
                            fallbackText: vaultRow.modelData.name.charAt(0).toUpperCase()
                        }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: -4
                            anchors.bottomMargin: -4
                            color: Theme.primary
                            opacity: iconArea.containsMouse || vaultRow.editing ? 1.0 : 0.85

                            DIcon {
                                anchors.centerIn: parent
                                name: vaultRow.editing ? "check" : "edit"
                                size: 12
                                color: Theme.primaryText
                            }
                        }

                        MouseArea {
                            id: iconArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (vaultRow.editing)
                                    vaultRow.confirmIcon();
                                else
                                    vaultRow.editing = true;
                            }
                        }
                    }

                    Column {
                        width: parent.width - iconButton.width - vaultToggle.width - 2 * Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            width: parent.width
                            text: vaultRow.modelData.name
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: vaultRow.modelData.path
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideMiddle
                        }
                    }

                    DToggle {
                        id: vaultToggle
                        anchors.verticalCenter: parent.verticalCenter
                        checked: !root.hiddenVaults.includes(vaultRow.modelData.path)
                        onToggled: isChecked => root.setHidden(vaultRow.modelData.path, !isChecked)
                    }
                }

                // Icon editor, shown only while editing
                Row {
                    visible: vaultRow.editing
                    width: parent.width
                    spacing: Theme.spacingS

                    DIconPicker {
                        id: iconPicker
                        anchors.verticalCenter: parent.verticalCenter
                        currentIcon: vaultRow.rawIcon.startsWith("material:") ? vaultRow.rawIcon.substring(9) : ""
                        onIconSelected: iconName => {
                            iconField.text = "material:" + iconName;
                            root.setIcon(vaultRow.modelData.path, iconField.text);
                        }
                    }

                    DTextField {
                        id: iconField
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - iconPicker.width - resetButton.width - confirmButton.width - 3 * Theme.spacingS
                        placeholderText: "Emoji (📓) or theme icon name"
                        text: vaultRow.rawIcon
                        onAccepted: vaultRow.confirmIcon()
                    }

                    DIconButton {
                        id: resetButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "restart_alt"
                        tooltipText: "Reset to Obsidian icon"
                        enabled: vaultRow.rawIcon !== ""
                        onClicked: {
                            iconField.text = "";
                            root.setIcon(vaultRow.modelData.path, "");
                        }
                    }

                    DIconButton {
                        id: confirmButton
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "filled"
                        iconName: "check"
                        tooltipText: "Apply icon"
                        onClicked: vaultRow.confirmIcon()
                    }
                }
            }
        }
    }
}
