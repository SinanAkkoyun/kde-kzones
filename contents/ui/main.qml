import QtGraphicalEffects 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.2
import org.kde.kirigami 2.5 as Kirigami
import org.kde.kwin 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.core 2.0 as PlasmaCore

import "components" as Components

PlasmaCore.Dialog {

    id: mainDialog
    location: PlasmaCore.Types.Floating // https://api.kde.org/frameworks/plasma-framework/html/classPlasma_1_1Types.html
    type: PlasmaCore.Dialog.OnScreenDisplay // https://api.kde.org/frameworks/plasma-framework/html/classPlasmaQuick_1_1Dialog.html
    backgroundHints: PlasmaCore.Types.NoBackground
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    x: clientArea.x
    y: clientArea.y
    width: clientArea.width
    height: clientArea.height
    visible: false
    outputOnly: true
    opacity: 1    

    // properties
    property var config: {}
    property bool shown: false
    property bool moving: false
    property bool resizing: false
    property var clientArea: {}
    property var cachedClientArea: {}
    property int currentLayout: 0
    property int highlightedZone: -1
    property int activeScreen: 0
    property bool doAnimations: true

    // colors
    property string color_zone_border: "transparent"
    property string color_zone_border_active: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.9)
    property string color_zone_background: "transparent"
    property string color_zone_background_active: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
    property string color_indicator: Qt.rgba(Kirigami.Theme.alternateBackgroundColor.r, Kirigami.Theme.alternateBackgroundColor.g, Kirigami.Theme.alternateBackgroundColor.b, 1)
    property string color_indicator_accent: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 1)
    property string color_indicator_shadow: '#69000000'
    property string color_indicator_text: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 1)
    property string color_debug_handle: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.9)  

    property var correctedCursorPos: Qt.point(workspace.cursorPos.x - clientArea.x, workspace.cursorPos.y - clientArea.y)

    // enums
    property var zoneTargets: {
        "indicator": 0,
        "zone": 1
    }

    function loadConfig() {
        // load values from configuration
        console.log("KZones: Reading config...")

        config = {
            rememberWindowGeometries: KWin.readConfig("rememberWindowGeometries", true), // remember window geometries before snapping to a zone, and restore them when the window is removed from their zone
            alwaysShowLayoutName: KWin.readConfig("alwaysShowLayoutName", false), // always show layout name, or only when switching between them
            pollingRate: KWin.readConfig("pollingRate", 100), // polling rate in milliseconds
            zoneTarget: KWin.readConfig("zoneTarget", 0), // the part of the zone you need to hover over to highlight it
            enableDebugMode: KWin.readConfig("enableDebugMode", false), // enable debug mode
            filterMode: KWin.readConfig("filterMode", 0), // filter mode
            filterList: KWin.readConfig("filterList", ""), // filter list
            osdTimeout: KWin.readConfig("osdTimeout", 1000), // timeout in milliseconds for hiding the OSD after switching layouts
            layouts: JSON.parse(KWin.readConfig("layoutsJson", '[{"name": "Layout 1","padding": 0,"zones": [{"name": "1","x": 0,"y": 0,"height": 100,"width": 25},{"name": "2","x": 25,"y": 0,"height": 100,"width": 50},{"name": "3","x": 75,"y": 0,"height": 100,"width": 25}]}]')), // layouts
            alternateIndicatorStyle: KWin.readConfig("alternateIndicatorStyle", false), // alternate indicator style
            invertedMode: KWin.readConfig("invertedMode", false), // inverted mode
        }

        console.log("KZones: Config loaded: " + JSON.stringify(config))
    }

    function show() {
        // refresh client area
        refreshClientArea()
        // show OSD
        mainDialog.shown = true
        mainDialog.visible = true
    }

    function hide() {
        // hide OSD
        mainDialog.shown = false
        mainDialog.visible = false
        highlightedZone = -1
    }

    function refreshClientArea() {
        activeScreen = workspace.activeScreen
        clientArea = workspace.clientArea(KWin.FullScreenArea, activeScreen, workspace.currentDesktop)
    }

    function checkZone(x, y) {
        for (let i = 0; i < repeater_zones.model.length; i++) {
            let zone
            switch (config.zoneTarget) {
            case zoneTargets.indicator:
                zone = repeater_zones.itemAt(i).children[0]
                break
            case zoneTargets.zone:
                zone = repeater_zones.itemAt(i)
                break
            }
            let zoneItem = zone.mapToItem(null, 0, 0)
            if (isPointInside(x, y, {x: zoneItem.x, y: zoneItem.y, width: zone.width, height: zone.height})) {
                return i
            }
        }
        return -1
    }

    function isPointInside(x, y, geometry) {
        return x >= geometry.x && x <= geometry.x + geometry.width && y >= geometry.y && y <= geometry.y + geometry.height
    }

    function rectOverlapArea(component1, component2) {
        let x1 = component1.x
        let y1 = component1.y
        let x2 = component1.x + component1.width
        let y2 = component1.y + component1.height
        let x3 = component2.x
        let y3 = component2.y
        let x4 = component2.x + component2.width
        let y4 = component2.y + component2.height
        let xOverlap = Math.max(0, Math.min(x2, x4) - Math.max(x1, x3))
        let yOverlap = Math.max(0, Math.min(y2, y4) - Math.max(y1, y3))
        return xOverlap * yOverlap
    }

    function matchZone(client) {
        client.zone = -1
        // get all zones in the current layout
        let zones = config.layouts[currentLayout].zones
        // loop through zones and compare with the geometries of the client
        for (let i = 0; i < zones.length; i++) {
            let zone = zones[i]
            let zone_padding = config.layouts[currentLayout].padding || 0
            let zoneX = ((zone.x / 100) * (clientArea.width - zone_padding)) + zone_padding
            let zoneY = ((zone.y / 100) * (clientArea.height - zone_padding)) + zone_padding
            let zoneWidth = ((zone.width / 100) * (clientArea.width - zone_padding)) - zone_padding
            let zoneHeight = ((zone.height / 100) * (clientArea.height - zone_padding)) - zone_padding
            if (client.geometry.x == zoneX && client.geometry.y == zoneY && client.geometry.width == zoneWidth && client.geometry.height == zoneHeight) {
                // zone found, set it and exit the loop
                client.zone = i
                client.zone = currentLayout
                break
            }
        }
    }

    function getWindowsInZone(zone) {
        let windows = []
        for (let i = 0; i < workspace.clientList().length; i++) {
            let client = workspace.clientList()[i]
            if (client.zone === zone && client.normalWindow) windows.push(client)
        }
        return windows
    }

    function switchWindowInZone(zone, reverse) {

        let clientsInZone = getWindowsInZone(zone)

        if (reverse) { clientsInZone.reverse() }

        // cycle through clients in zone
        if (clientsInZone.length > 0) {
            let index = clientsInZone.indexOf(workspace.activeClient)
            if (index === -1) {
                workspace.activeClient = clientsInZone[0]
            } else {
                workspace.activeClient = clientsInZone[(index + 1) % clientsInZone.length]
            }
        }
    }

    function moveClientToZone(client, zone) {

        // block abnormal windows from being moved (like plasmashell, docks, etc...)
        if (!client.normalWindow) return
        
        console.log("KZones: Moving client " + client.resourceClass.toString() + " to zone " + zone)

        saveWindowGeometries(client, zone)

        // move client to zone
        if (zone != -1) {
            let repeater_zone = repeater_zones.itemAt(zone)
            let global_x = repeater_zone.mapToGlobal(Qt.point(0, 0)).x
            let global_y = repeater_zone.mapToGlobal(Qt.point(0, 0)).y
            let newGeometry = Qt.rect(Math.round(global_x), Math.round(global_y), Math.round(repeater_zone.width), Math.round(repeater_zone.height))
            console.log("KZones: Moving client " + client.resourceClass.toString() + " to zone " + zone + " with geometry " + JSON.stringify(newGeometry))
            client.geometry = newGeometry
        }
    }

    function saveWindowGeometries(client, zone) {
        console.log("KZones: Saving geometry for client " + client.resourceClass.toString())
        // save current geometry
        if (config.rememberWindowGeometries) {
            let geometry = {
                "x": client.geometry.x,
                "y": client.geometry.y,
                "width": client.geometry.width,
                "height": client.geometry.height
            }
            if (zone != -1) {
                if (client.zone == -1) {
                    client.oldGeometry = geometry
                }                
            }
        }
        // save zone
        client.zone = zone
        client.layout = currentLayout
    }

    Component.onCompleted: {

        // register window
        KWin.registerWindow(mainDialog)

        // refresh client area
        refreshClientArea()        
        // shortcut: cycle through layouts
        bindShortcut("Cycle layouts", "Ctrl+Alt+D", function() {
            // reset timer to prevent osd from being hidden when switching layouts
            if (!moving) {
                hideOSD.running = false
                hideOSD.start()
            }

            osdCmd.exec(config.layouts[currentLayout].name)

            //cycle through layouts
            currentLayout = (currentLayout + 1) % config.layouts.length
            highlightedZone = -1
            show()
        })

        // shortcut: move to zone (1-9)
        for (let i = 0; i < 9; i++) {
            bindShortcut(`Move active window to zone ${i+1}`, `Ctrl+Alt+Num+${i+1}`, function() {
                moveClientToZone(workspace.activeClient, i)
            })
        }

        // shortcut: move to next zone
        bindShortcut("Move active window to next zone", "Ctrl+Alt+Right", function() {
            const client = workspace.activeClient
            // TODO: if client.zone = -1 check if client is in a zone by geometry
            const zonesLength = config.layouts[currentLayout].zones.length
            moveClientToZone(client, (client.zone + 1) % zonesLength)
        })

        // shortcut: move to previous zone
        bindShortcut("Move active window to previous zone", "Ctrl+Alt+Left", function() {
            const client = workspace.activeClient
            // TODO: if client.zone = -1 check if client is in a zone by geometry
            const zonesLength = config.layouts[currentLayout].zones.length
            moveClientToZone(client, (client.zone - 1 + zonesLength) % zonesLength)
        })

        // shortcut: toggle osd
        bindShortcut("Toggle OSD", "Ctrl+Alt+C", function() {
            if (!shown) {
                show()
            } else {
                hide()
            }
        })

        // shortcut: switch to next window in current zone
        bindShortcut("Switch to next window in current zone", "Ctrl+Alt+Up", function() {
            let zone = workspace.activeClient.zone
            switchWindowInZone(zone)
        })

        // shortcut: switch to previous window in current zone
        bindShortcut("Switch to previous window in current zone", "Ctrl+Alt+Down", function() {
            let zone = workspace.activeClient.zone
            switchWindowInZone(zone, true)
        })

        mainDialog.loadConfig()

        // match all clients to zones
        for (var i = 0; i < workspace.clientList().length; i++) {
            matchZone(workspace.clientList()[i])
        }

        console.log("KZones: Ready!")
    }

    function bindShortcut(title, sequence, callback) {
        KWin.registerShortcut(`KZones: ${title}`, `KZones: ${title}`, sequence, callback)
    }

    Item {
        id: mainItem
        anchors.fill: parent

        // main polling timer
        Timer {
            id: timer
            triggeredOnStart: true
            interval: config.pollingRate
            running: shown// && moving
            repeat: true

            onTriggered: {

                refreshClientArea()
                
                let pos = correctedCursorPos
                highlightedZone = checkZone(pos.x, pos.y)

                // mini selector
                config.layouts.forEach((layout, layoutIndex) => {
                    let layoutItem = repeater_layouts.itemAt(layoutIndex)
                    layout.zones.forEach((zone, zoneIndex) => {
                        let zoneItem = layoutItem.children[zoneIndex]
                        // check if cursor is above zoneItem
                        let zoneItemGlobal = zoneItem.mapToGlobal(Qt.point(0, 0))
                        if(isPointInside(workspace.cursorPos.x, workspace.cursorPos.y, {x: zoneItemGlobal.x, y: zoneItemGlobal.y, width: zoneItem.width, height: zoneItem.height})) {
                            highlightedZone = zoneIndex
                            currentLayout = layoutIndex
                        }
                    })
                })

            }
        }

        // osd qdbus
        PlasmaCore.DataSource {
            id: osdCmd
            engine: "executable"
            connectedSources: []
            onNewData: {
                disconnectSource(sourceName);
            }
            function exec(text, icon) {
                connectSource(`qdbus org.kde.plasmashell /org/kde/osdService showText "${icon}" "${text}"`);
            }
        }

        // debug handle
        Rectangle {
            id: handle
            color: color_debug_handle
            visible: config.enableDebugMode
            width: 32
            height: 32
            radius: 32
            x: correctedCursorPos.x - handle.width / 2
            y: correctedCursorPos.y - handle.height / 2
            z: 100
        }

        // debug osd
        Rectangle {
            id: debugOsd
            visible: config.enableDebugMode

            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.top: parent.top
            anchors.topMargin: 20

            z: 100
            width: debugOsdText.paintedWidth + debugOsdText.padding * 2
            height: debugOsdText.paintedHeight + debugOsdText.padding * 2
            radius: 5
            color: color_indicator

            Text {
                id: debugOsdText
                anchors.fill: parent
                padding: 15
                color: color_indicator_text
                text: {
                    // let correctedCursorPos = Qt.point(correctedCursorPos.x - clientArea.x, correctedCursorPos.y - clientArea.y)
                    if (config.enableDebugMode) {
                        let t = ""
                        t += `Active: ${workspace.activeClient.caption}\n`
                        t += `Window class: ${workspace.activeClient.resourceClass.toString()}\n`
                        t += `X: ${workspace.activeClient.geometry.x}, Y: ${workspace.activeClient.geometry.y}, Width: ${workspace.activeClient.geometry.width}, Height: ${workspace.activeClient.geometry.height}\n`
                        t += `Previous Zone: ${workspace.activeClient.zone}\n`
                        t += `Highlighted Zone: ${highlightedZone}\n`
                        t += `Layout: ${currentLayout}\n`
                        t += `Zones: ${config.layouts[currentLayout].zones.map(z => z.name).join(', ')}\n`
                        t += `Polling Rate: ${config.pollingRate}ms\n`
                        t += `Handle X: ${handle.x}, Y: ${handle.y}, Width: ${handle.width}, Height: ${handle.height}\n`
                        t += `Moving: ${moving}\n`
                        t += `Resizing: ${resizing}\n`
                        t += `Old Geometry: ${JSON.stringify(workspace.activeClient.oldGeometry)}\n`
                        t += `Active Screen: ${activeScreen}\n`
                        t += `Cursor pos: ${correctedCursorPos.x}, ${correctedCursorPos.y}`
                        return t
                    } else {
                        return ""
                    }                 
                }
                font.pixelSize: 14
                font.family: "Hack"
            }
        }

        // zones
        Repeater {
            id: repeater_zones
            model: config.layouts[currentLayout].zones

            // zone
            Rectangle {
                id: zone
                x: ((modelData.x / 100) * (clientArea.width - zone_padding)) + zone_padding
                y: ((modelData.y / 100) * (clientArea.height - zone_padding)) + zone_padding
                implicitWidth: ((modelData.width / 100) * (clientArea.width - zone_padding)) - zone_padding
                implicitHeight: ((modelData.height / 100) * (clientArea.height - zone_padding)) - zone_padding
                color: (highlightedZone == zoneIndex) ? color_zone_background_active : color_zone_background
                radius: 8 // TODO: make configurable (zoneRadius)
                border.color: (highlightedZone == zoneIndex) ? color_zone_border_active : color_zone_border
                border.width: 3

                property int zoneIndex: index
                property int zone_padding: config.layouts[currentLayout].padding || 0

                //! keep this the first child
                Rectangle {
                    id: indicator
                    width: 160 //180 // TODO: make configurable (indicatorWidth)
                    height: 90 //100 // TODO: make configurable (indicatorHeight)
                    radius: 5
                    color: config.alternateIndicatorStyle ? color_indicator : 'transparent'
                    opacity: (highlightedZone != zone.zoneIndex) ? 1.0 : 1
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        horizontalCenterOffset: (((modelData || {}).indicator || {}).offset || {}).x || 0
                        verticalCenter: parent.verticalCenter
                        verticalCenterOffset: (((modelData || {}).indicator || {}).offset || {}).y || 0
                    }

                    // zone indicator part
                    Repeater {
                        id: indicators
                        model: config.layouts[currentLayout].zones

                        Rectangle {
                            property int padding: config.alternateIndicatorStyle ? 0 : 3
                            radius: 5
                            visible: config.alternateIndicatorStyle ? ((index == zone.zoneIndex) ? true : false) : true
                            x: ((modelData.x / 100) * (indicator.width - padding)) + padding
                            y: ((modelData.y / 100) * (indicator.height - padding)) + padding
                            z: (index == zone.zoneIndex) ? 2 : 1
                            implicitWidth: ((modelData.width / 100) * (indicator.width - padding)) - padding
                            implicitHeight: ((modelData.height / 100) * (indicator.height - padding)) - padding
                            color: (index == zone.zoneIndex) ? color_indicator_accent : color_indicator
                            // opacity: (highlightedZone != zone.zoneIndex) ? 1.0 : 0.5 // TODO: add opacity to config
                            scale: (doAnimations) ? ((highlightedZone == zone.zoneIndex) ? ((index == zone.zoneIndex) ? 1.1 : 1) : 1.0) : 1
                            Behavior on scale {
                                NumberAnimation { duration: 150 }
                            }
                        }
                    }

                    // zone indicator label
                    Text {
                        z: 3
                        anchors.fill: indicator
                        font.pixelSize: 20
                        opacity: (highlightedZone != zone.zoneIndex) ? 1.0 : 0.5 // TODO: add opacity to config
                        color: color_indicator_text
                        leftPadding: 30
                        rightPadding: 30
                        topPadding: 30
                        bottomPadding: 30
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.name
                    }
                }

                // zone indicator shadow
                Components.Shadow{
                    target: indicator
                    visible: !config.alternateIndicatorStyle
                }

            }

        }

        // mini selector
        RowLayout {
            id: toolBarRowLayout
            spacing: 20
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 20

            Repeater {
                id: repeater_layouts
                model: config.layouts

                Rectangle {
                    id: layout
                    width: 200
                    height: 100
                    color: "transparent"
                    property int layoutIndex: index

                    Repeater {
                        id: zone
                        model: modelData.zones
                        property int zoneIndex: index

                        // zone
                        Rectangle {
                            id: zone_2
                            x: modelData.x / 100 * layout.width
                            y: modelData.y / 100 * layout.height
                            implicitWidth: modelData.width / 100 * layout.width
                            implicitHeight: modelData.height / 100 * layout.height
                            color: highlightedZone == index && currentLayout == layoutIndex ? color_indicator_accent : color_indicator
                            border.color: "black"
                            border.width: 2
                        }
                    }
                }
            }
        }
        

        // workspace connection
        Connections {
            target: workspace

            function onClientAdded(client) {
                // check if new window spawns in a zone
                if (client.zone == undefined || client.zone == -1) {
                    matchZone(client)
                }
            }

            function onClientFullScreenSet(client, fullscreen, user) {
                if (!client) return;
                console.log("KZones: Client fullscreen: " + client.resourceClass.toString() + " (fullscreen " + fullscreen + ")");
                mainDialog.hide();
            }

            // unused, but may be useful in the future
            // function onClientActivated(client) {
            //     if (client) {
            //         console.log("KZones: Client activated: " + client.resourceClass.toString() + " (zone " + client.zone + ")");
            //     }    
            // }
            // function onVirtualScreenSizeChanged(){ }
        }

        // options connection
        Connections {
            //! not working at the moment
            target: options

            function onConfigChanged() {
                console.log("KZones: Config changed")
                mainDialog.loadConfig()
            }
        }

        // activeClient connection
        Connections {
            target: workspace.activeClient

            // start moving
            function onClientStartUserMovedResized(client) {
                if (client.resizeable && client.normalWindow) {
                    if (client.move && checkFilter(client)) {
                        
                        cachedClientArea = clientArea
                        moving = true
                        resizing = false
                        hideOSD.running = false
                        console.log("KZones: Move start " + client.resourceClass.toString())
                        if (!config.invertedMode) mainDialog.show()
                    }
                    if (client.resize) {
                        moving = false
                        resizing = true
                        // client resizing
                    }
                }
            }

            // is moving
            function onClientStepUserMovedResized(client, r) {
                
                if (client.resizeable) {
                    if (moving && checkFilter(client)) {
                        // refresh client area
                        refreshClientArea()
                        if (config.rememberWindowGeometries && client.zone != -1) {
                            if (client.oldGeometry) {
                                let geometry = client.oldGeometry
                                let zone = config.layouts[client.layout].zones[client.zone]
                                let zoneCenterX = (zone.x + zone.width / 2) / 100 * cachedClientArea.width + cachedClientArea.x
                                let zoneX = ((zone.x / 100) * cachedClientArea.width + cachedClientArea.x)
                                let newGeometry = Qt.rect(Math.round((r.x - zoneX) + (zoneCenterX - geometry.width / 2)), Math.round(r.y), Math.round(geometry.width), Math.round(geometry.height))
                                client.geometry = newGeometry
                            }
                        }
                    }
                    if (resizing) {
                        // client resizing
                    }
                }
            }

            // stop moving
            function onClientFinishUserMovedResized(client) {
                if (moving) {
                    console.log("Kzones: Move end " + client.resourceClass.toString())
                    if (shown) {
                        moveClientToZone(client, highlightedZone)
                    } else {
                        saveWindowGeometries(client, -1)
                    }                    
                    hide()
                }
                if (resizing) {
                    // client resizing
                }
                moving = false
                resizing = false
            }

            // check filter
            function checkFilter(client) {

                let filter = config.filterList.split(/\r?\n/)

                if (config.filterList.length > 0) {
                    if (config.filterMode == 0) { // include
                        return filter.includes(client.resourceClass.toString())
                    }
                    if (config.filterMode == 1) { // exclude
                        return !filter.includes(client.resourceClass.toString())
                    }
                }
                return true
            }
        }

        // hide osd timer
        Timer {
            id: hideOSD
            interval: config.osdTimeout
            repeat: false

            onTriggered: {
                hide()
            }
        }

        // reusable timer
        Timer {
            id: delay

            function setTimeout(callback, timeout) {
                delay.interval = timeout
                delay.repeat = false
                delay.triggered.connect(callback)
                delay.triggered.connect(function release () {
                    delay.triggered.disconnect(callback)
                    delay.triggered.disconnect(release)
                })
                delay.start()
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            visible: config.enableDebugMode
            border.color: color_debug_handle
            border.width: 1
        }

    }

}