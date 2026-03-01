import QtQuick
import qs.Common
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
                root.saveValue("trigger", triggerSetting.value || "\obs"); // Restore StringSetting value
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
        defaultValue: "\obs"
    }
}
