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

  function open() { root.controller.show(); view.open() }
  function openToThread(id) { root.controller.show(); view.openToThread(id) }
  function openToReply(threadId, replyId) { root.controller.show(); view.openToReply(threadId, replyId) }
  function diagnostic() { return view.diagnostic() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: view.focusTarget
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(Math.min(view.implicitContentHeight, Style.space(700)))

    BbsView {
      id: view
      width: parent.width
      height: parent.height
      bar: root.bar
      hostWidget: root.hostWidget
      launcherPath: root.launcherPath
      onCloseRequested: root.close()
      onDetachRequested: if (root.hostWidget) root.hostWidget.detach()
    }
  }
}
