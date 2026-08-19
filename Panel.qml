import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.thoughtlesslabs.omarchy-bbs"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string launcherPath: ""
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string panelFont: bar ? bar.fontFamily : Style.font.family

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function launch(action) {
    if (!root.bar || root.launcherPath === "") return
    root.bar.run(root.bar.shellQuote(root.launcherPath) + " " + action)
    root.close()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "o" || text === "O") root.launch("open")
        else if (text === "n" || text === "N") root.launch("new")
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Omarchy BBS"
          meta: "Community frequency"
          detail: "Encrypted"
          foreground: root.foreground
          fontFamily: root.panelFont
          iconComponent: Component {
            Text {
              text: "\uf075"
              color: root.foreground
              font.family: root.panelFont
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { width: parent.width }
        PanelSectionHeader {
          text: "QUICK ACCESS"
          foreground: root.foreground
          fontFamily: root.panelFont
        }

        Button {
          width: parent.width
          text: "Open board"
          iconText: "\uf35d"
          leftAlign: true
          bordered: true
          focusable: true
          foreground: root.foreground
          fontFamily: root.panelFont
          onClicked: root.launch("open")
        }

        Button {
          width: parent.width
          text: "New transmission"
          iconText: "\uf044"
          leftAlign: true
          bordered: true
          focusable: true
          foreground: root.foreground
          fontFamily: root.panelFont
          onClicked: root.launch("new")
        }

        Text {
          width: parent.width
          text: "O  open board    N  new transmission\nRight-click the bar icon for a direct launch."
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
