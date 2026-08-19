import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.thoughtlesslabs.omarchy-bbs"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "BBS"
    tooltipText: "Open Omarchy BBS"
    onPressed: root.bar.run(Qt.resolvedUrl("bin/omarchy-bbs").toString().replace("file://", ""))
  }
}
