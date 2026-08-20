import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.thoughtlesslabs.omarchy-bbs"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string launcherPath: ""
  property string screen: "loading"
  property string handle: ""
  property string role: "member"
  property string errorMessage: ""
  property string noticeMessage: ""
  property string pendingAction: ""
  property string pendingInput: ""
  property var queuedRequest: null
  property var currentThread: ({})
  property var currentProfile: ({})
  property var preferences: ({bio: "", mention_notifications: true})
  property var boardCategories: ["general", "projects", "help", "showcase", "meta"]
  property string categoryFilter: "all"
  property string composeCategory: "general"
  property int currentPage: 1
  property int totalPages: 1
  property int replyPage: 1
  property int replyPages: 1
  property int replyTargetId: 0
  property string replyTargetHandle: ""
  property string editorKind: ""
  property int editorId: 0
  property string reportKind: ""
  property int reportId: 0
  property string returnScreen: "threads"
  property string moderationReturn: "thread"
  property string moderatorCategory: "general"
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string panelFont: bar ? bar.fontFamily : Style.font.family

  component BbsChip: Rectangle {
    property string label: ""
    property color chipForeground: Color.foreground
    property color chipAccent: Color.accent
    property string chipFont: Style.font.family
    property bool highlighted: false
    implicitWidth: chipText.implicitWidth + Style.space(12)
    implicitHeight: chipText.implicitHeight + Style.space(5)
    radius: implicitHeight / 2
    color: highlighted ? Qt.rgba(chipAccent.r, chipAccent.g, chipAccent.b, .16) : Qt.rgba(chipForeground.r, chipForeground.g, chipForeground.b, .07)
    border.width: 1
    border.color: highlighted ? Qt.rgba(chipAccent.r, chipAccent.g, chipAccent.b, .55) : Qt.rgba(chipForeground.r, chipForeground.g, chipForeground.b, .14)
    Text {
      id: chipText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: label
      color: highlighted ? chipAccent : chipForeground
      font.family: chipFont
      font.pixelSize: Style.font.caption
      font.bold: highlighted
    }
  }

  function open() { root.controller.show(); refreshIdentity() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function switchPanel(direction) { return root.bar && root.bar.switchPanelFrom ? root.bar.switchPanelFrom(root.barIdentity, direction) : false }
  function scrollBy(amount) { scroller.contentY = Math.max(0, Math.min(scroller.contentY + amount, Math.max(0, scroller.contentHeight - scroller.height))) }
  function handleShortcut(key) {
    if (key === "r" || key === "R") { if (screen === "thread") openThread(currentThread.id, replyPage); else refreshThreads() }
    else if ((key === "n" || key === "N") && handle) screen = "compose"
    else if ((key === "m" || key === "M") && handle) loadMentions(true)
    else if ((key === "p" || key === "P") && handle) loadProfile(handle)
    else if ((key === "s" || key === "S") && screen === "threads") searchField.forceActiveFocus()
    else if ((key === "b" || key === "B") && screen !== "threads" && screen !== "onboarding") refreshThreads()
  }
  function run(action, input) {
    if (bridge.running || launcherPath === "") return
    errorMessage = ""; noticeMessage = ""; pendingAction = action; pendingInput = input || ""
    bridge.command = [launcherPath, action]; bridge.running = true
  }
  function continueWith(action, input) {
    if (bridge.running) queuedRequest = ({action: action, input: input || ""})
    else run(action, input || "")
  }
  function refreshIdentity() { screen = "loading"; run("identity", "") }
  function refreshThreads() { screen = "loading"; run("threads", JSON.stringify({query: searchField.text, category: categoryFilter, page: currentPage})) }
  function openThread(id, page) { screen = "loading"; run("thread", JSON.stringify({thread_id: id, reply_page: page || 0})) }
  function loadProfile(name) { screen = "loading"; run("profile", JSON.stringify({handle: name || handle})) }
  function loadPreferences() { screen = "loading"; run("preferences", JSON.stringify({action: "get"})) }
  function loadMentions(markRead) { screen = "loading"; run("mentions", JSON.stringify({page: 1, mark_read: !!markRead})) }
  function loadReports() { screen = "loading"; run("moderation", JSON.stringify({action: "list_reports"})) }
  function selectReplyTarget(id, name) { replyTargetId = id; replyTargetHandle = name; replyBody.forceActiveFocus() }
  function clearReplyTarget() { replyTargetId = 0; replyTargetHandle = "" }
  function prepareEdit(kind, item) {
    editorKind = kind; editorId = item.id; returnScreen = kind === "thread" ? "thread" : "thread"
    editTitle.text = kind === "thread" ? item.title : ""
    editBody.text = item.body || ""
    editCategory = item.category || currentThread.category || "general"
    screen = "edit"
  }
  property string editCategory: "general"
  function prepareReport(kind, id) { reportKind = kind; reportId = id; reportReason.text = ""; screen = "report" }
  function afterMutation(message) { noticeMessage = message; screen = "loading"; continueWith("thread", JSON.stringify({thread_id: currentThread.id, reply_page: replyPage})) }
  function parseResult(text) {
    var result
    try { result = JSON.parse(String(text || "{}")) } catch (e) { errorMessage = "The server returned an unreadable response."; screen = handle ? "threads" : "onboarding"; return }
    if (!result.ok) { errorMessage = result.error || "The request failed."; if (screen === "loading") screen = handle ? "threads" : "onboarding"; return }
    if (pendingAction === "identity") {
      if (result.registered) { handle = result.handle; screen = "loading"; continueWith("threads", JSON.stringify({query: "", category: "all", page: 1})) }
      else { handleField.text = result.suggested_handle; screen = "onboarding" }
    } else if (pendingAction === "register") {
      handle = result.handle; screen = "loading"; continueWith("threads", JSON.stringify({query: "", category: "all", page: 1}))
    } else if (pendingAction === "threads") {
      threadModel.clear(); boardCategories = result.categories || boardCategories; role = result.role || role
      var rows = result.threads || []
      for (var i = 0; i < rows.length; ++i) {
        var row = rows[i]
        if (row.pinned === undefined) row.pinned = false
        if (row.locked === undefined) row.locked = false
        if (row.unread === undefined) row.unread = false
        threadModel.append(row)
      }
      currentPage = result.page || 1; totalPages = result.pages || 1; handle = result.handle || handle; screen = "threads"
    } else if (pendingAction === "thread") {
      var item = result.thread; var replies = item.replies || []
      for (var j = 0; j < replies.length; ++j) replies[j].depth = replies[j].parent_reply_id ? 1 : 0
      item.replies = replies; currentThread = item; replyPage = item.reply_page || 1; replyPages = item.reply_pages || 1; clearReplyTarget(); screen = "thread"; scroller.contentY = 0
      if (hostWidget && hostWidget.refreshStatus) hostWidget.refreshStatus()
    } else if (pendingAction === "create") {
      subjectField.text = ""; composeBody.text = ""; screen = "loading"; continueWith("thread", JSON.stringify({thread_id: result.thread_id}))
    } else if (pendingAction === "reply") {
      replyBody.text = ""; noticeMessage = "Reply added"; screen = "loading"; continueWith("thread", JSON.stringify({thread_id: currentThread.id, reply_page: result.reply_page || 0}))
    } else if (pendingAction === "edit") afterMutation("Changes saved")
    else if (pendingAction === "delete") {
      if (editorKind === "thread") { noticeMessage = "Post deleted"; currentPage = 1; refreshThreads() } else afterMutation("Reply deleted")
    } else if (pendingAction === "report") afterMutation("Report submitted")
    else if (pendingAction === "profile") { currentProfile = result.profile; screen = "profile" }
    else if (pendingAction === "preferences") { preferences = result.preferences; bioField.text = preferences.bio || ""; mentionToggle.checked = !!preferences.mention_notifications; screen = "preferences" }
    else if (pendingAction === "mentions") { mentionModel.clear(); rows = result.mentions || []; for (i=0;i<rows.length;++i) mentionModel.append(rows[i]); screen = "mentions" }
    else if (pendingAction === "moderation") {
      if (result.reports !== undefined) { reportModel.clear(); rows=result.reports||[];for(i=0;i<rows.length;++i)reportModel.append(rows[i]);screen="moderation" }
      else if (moderationReturn === "moderation") { noticeMessage = "Moderation action applied"; screen = "loading"; continueWith("moderation", JSON.stringify({action:"list_reports"})) }
      else afterMutation("Moderation action applied")
    }
  }

  ListModel { id: threadModel }
  ListModel { id: mentionModel }
  ListModel { id: reportModel }

  Process {
    id: bridge; stdinEnabled: true
    onStarted: { if (root.pendingInput !== "") write(root.pendingInput + "\n") }
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseResult(text) }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0 && root.errorMessage === "") root.errorMessage = "The BBS client could not complete the request."
      if (root.queuedRequest) { var next=root.queuedRequest;root.queuedRequest=null;Qt.callLater(function(){root.run(next.action,next.input)}) }
    }
  }

  KeyboardPanel {
    id: panel; anchorItem: root.anchorItem; owner: root.barIdentity; bar: root.bar; open: root.opened; focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520)); contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(700)))
    FocusScope {
      id: keyboardScope; anchors.fill:parent; focus:true
      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_PageDown) { root.scrollBy(scroller.height * .8); event.accepted = true }
        else if (event.key === Qt.Key_PageUp) { root.scrollBy(-scroller.height * .8); event.accepted = true }
        else if (event.key === Qt.Key_Home) { scroller.contentY = 0; event.accepted = true }
        else if (event.key === Qt.Key_End) { scroller.contentY = Math.max(0, scroller.contentHeight-scroller.height); event.accepted = true }
      }
      PanelKeyCatcher {
        id: keyCatcher; anchors.fill: parent
        blocked: handleField.activeFocus || searchField.activeFocus || subjectField.activeFocus || composeBody.activeFocus || replyBody.activeFocus || editTitle.activeFocus || editBody.activeFocus || reportReason.activeFocus || bioField.activeFocus || moderationHandle.activeFocus || suspensionHours.activeFocus
        onMoveRequested: function(dx, dy) {
          if (dy !== 0) root.scrollBy(dy * Style.space(56))
          else if (root.screen === "thread" && dx < 0 && root.replyPage > 1) root.openThread(root.currentThread.id, root.replyPage-1)
          else if (root.screen === "thread" && dx > 0 && root.replyPage < root.replyPages) root.openThread(root.currentThread.id, root.replyPage+1)
        }
        onCloseRequested: { if (root.screen !== "threads" && root.screen !== "onboarding") root.refreshThreads(); else root.close() }
        onTabRequested: function(direction) { root.switchPanel(direction) }
        onTextKey: function(t) { root.handleShortcut(t) }
      Flickable {
        id: scroller; anchors.fill: parent; clip: true; boundsBehavior: Flickable.StopAtBounds; contentWidth: width; contentHeight: content.implicitHeight
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
        Column {
          id: content; width: scroller.width - (scroller.contentHeight > scroller.height ? Style.space(8) : 0); spacing: Style.space(8)
          PanelHero {
            width: parent.width; title: "OMARCHY // BBS"; meta: root.handle ? "@" + root.handle : "COMMUNITY BOARD"; detail: root.role === "admin" ? "ADMIN" : "ENCRYPTED"; foreground: root.foreground; fontFamily: root.panelFont
            iconComponent: Component {
              Item {
                implicitWidth: Style.space(42); implicitHeight: Style.space(42)
                Text { anchors.centerIn:parent; textFormat:Text.PlainText; text:"\uf086"; color:root.accent; font.family:root.panelFont; font.pixelSize:Style.font.display }
                Rectangle { width:Style.space(6); height:width; radius:width/2; color:root.accent; anchors.right:parent.right; anchors.bottom:parent.bottom }
              }
            }
          }
          PanelSeparator { width: parent.width }
          Text { visible: root.errorMessage!=="";width:parent.width;textFormat:Text.PlainText;text:"! "+root.errorMessage;color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap }
          Text { visible: root.noticeMessage!=="";width:parent.width;textFormat:Text.PlainText;text:root.noticeMessage;color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall }
          Text { visible: root.screen==="loading";width:parent.width;textFormat:Text.PlainText;text:"LOADING…";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;horizontalAlignment:Text.AlignHCenter }

          Column {
            visible: root.screen==="onboarding";width:parent.width;spacing:Style.space(10)
            PanelSectionHeader{text:"CHOOSE YOUR USERNAME";foreground:root.foreground;fontFamily:root.panelFont}
            Text{width:parent.width;textFormat:Text.PlainText;text:"Your hostname is suggested. This public username appears on your posts.";color:Qt.darker(root.foreground,1.35);font.family:root.panelFont;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap}
            TextField{id:handleField;width:parent.width;foreground:root.foreground;maximumLength:32;onAccepted:joinButton.clicked()}
            Button{id:joinButton;width:parent.width;text:bridge.running?"Joining…":"Join board";iconText:"\uf086";leftAlign:true;bordered:true;foreground:root.foreground;enabled:!bridge.running;onClicked:root.run("register",JSON.stringify({handle:handleField.text}))}
          }

          Column {
            visible: root.screen==="threads";width:parent.width;spacing:Style.space(7)
            PanelSectionHeader{text:"FIND POSTS";foreground:root.foreground;fontFamily:root.panelFont}
            Row { width:parent.width;spacing:Style.space(6)
              Button{width:(parent.width-parent.spacing)*.55;text:"New post";iconText:"\uf1d8";leftAlign:true;bordered:true;foreground:root.foreground;onClicked:root.screen="compose"}
              Button{width:(parent.width-parent.spacing)*.45;text:"Profile";iconText:"\uf2bd";leftAlign:true;bordered:true;foreground:root.foreground;onClicked:root.loadProfile(root.handle)}
            }
            Row { width:parent.width;spacing:Style.space(6)
              TextField{id:searchField;width:parent.width-Style.space(106);foreground:root.foreground;placeholderText:"Search posts";onAccepted:{root.currentPage=1;root.refreshThreads()}}
              Button{width:Style.space(100);text:"Search";iconText:"\uf002";bordered:true;foreground:root.foreground;onClicked:{root.currentPage=1;root.refreshThreads()}}
            }
            Flow { width:parent.width;spacing:Style.space(5)
              Repeater { model:["all"].concat(root.boardCategories);delegate:Button{required property string modelData;text:modelData.toUpperCase();bordered:true;foreground:root.foreground;active:root.categoryFilter===modelData;onClicked:{root.categoryFilter=modelData;root.currentPage=1;root.refreshThreads()}} }
            }
            Row { width:parent.width;spacing:Style.space(6)
              Button{text:"Mentions";iconText:"@";bordered:true;foreground:root.foreground;onClicked:root.loadMentions(true)}
              Button{visible:root.role==="admin";text:"Moderation";iconText:"\uf3ed";bordered:true;foreground:root.foreground;onClicked:root.loadReports()}
              Button{text:"Refresh";iconText:"\uf021";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            }
            PanelSectionHeader{text:"POSTS";foreground:root.foreground;fontFamily:root.panelFont}
            Text{visible:threadModel.count===0;width:parent.width;textFormat:Text.PlainText;text:"NO POSTS FOUND.";color:Qt.darker(root.foreground,1.35);font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
            Repeater { model:threadModel;delegate:Rectangle{
              required property int id;required property string category;required property string title;required property string handle;required property string created_at;required property int replies;required property bool pinned;required property bool locked;required property bool unread
              width:parent.width
              implicitHeight:postCardColumn.implicitHeight+Style.space(16)
              radius:Style.cornerRadius
              color:postMouse.containsMouse?Style.hoverFillFor(root.foreground,root.accent):(unread?Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.10):Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.04))
              border.width:1
              border.color:(unread||pinned)?Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.55):Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.12)
              Column {
                id:postCardColumn;anchors.fill:parent;anchors.margins:Style.space(8);spacing:Style.space(5)
                Flow {
                  width:parent.width;spacing:Style.space(4)
                  BbsChip{label:category.toUpperCase();highlighted:true}
                  BbsChip{visible:unread;label:"NEW";highlighted:true}
                  BbsChip{visible:pinned;label:"PINNED"}
                  BbsChip{visible:locked;label:"LOCKED"}
                }
                Text{width:parent.width;textFormat:Text.PlainText;text:title;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;font.bold:true;wrapMode:Text.WordWrap}
                Text{width:parent.width;textFormat:Text.PlainText;text:"@"+handle+"  ·  "+replies+" repl.  ·  "+created_at;color:Color.muted;font.family:root.panelFont;font.pixelSize:Style.font.caption;elide:Text.ElideRight}
              }
              MouseArea{id:postMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.openThread(id)}
            }}
            Row { visible:root.totalPages>1;spacing:Style.space(6)
              Button{text:"Previous";bordered:true;foreground:root.foreground;enabled:root.currentPage>1;onClicked:{root.currentPage--;root.refreshThreads()}}
              Text{anchors.verticalCenter:parent.verticalCenter;textFormat:Text.PlainText;text:root.currentPage+" / "+root.totalPages;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
              Button{text:"Next";bordered:true;foreground:root.foreground;enabled:root.currentPage<root.totalPages;onClicked:{root.currentPage++;root.refreshThreads()}}
            }
          }

          Column {
            visible:root.screen==="compose";width:parent.width;spacing:Style.space(8)
            PanelSectionHeader{text:"NEW POST";foreground:root.foreground;fontFamily:root.panelFont}
            Flow{width:parent.width;spacing:Style.space(5);Repeater{model:root.boardCategories;delegate:Button{required property string modelData;text:modelData.toUpperCase();bordered:true;foreground:root.foreground;active:root.composeCategory===modelData;onClicked:root.composeCategory=modelData}}}
            TextField{id:subjectField;width:parent.width;foreground:root.foreground;placeholderText:"Subject";maximumLength:120}
            Controls.TextArea{id:composeBody;width:parent.width;height:Style.space(150);textFormat:TextEdit.PlainText;placeholderText:"Write your post";wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Row {
              spacing:Style.space(6)
              Button{text:"Post";iconText:"\uf1d8";bordered:true;foreground:root.foreground;enabled:!bridge.running;onClicked:root.run("create",JSON.stringify({category:root.composeCategory,title:subjectField.text,body:composeBody.text}))}
              Button{text:"Cancel";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            }
          }

          Column {
            visible:root.screen==="thread";width:parent.width;spacing:Style.space(8)
            Button{text:"Back to posts";iconText:"\uf060";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            Rectangle {
              width:parent.width;implicitHeight:threadCardColumn.implicitHeight+Style.space(18);radius:Style.cornerRadius
              color:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.04)
              border.width:1;border.color:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.13)
              Column {
                id:threadCardColumn;anchors.fill:parent;anchors.margins:Style.space(9);spacing:Style.space(6)
                Flow {
                  width:parent.width;spacing:Style.space(4)
                  BbsChip{label:String(root.currentThread.category||"general").toUpperCase();highlighted:true}
                  BbsChip{visible:!!root.currentThread.pinned;label:"PINNED"}
                  BbsChip{visible:!!root.currentThread.locked;label:"LOCKED"}
                }
                Text{width:parent.width;textFormat:Text.PlainText;text:root.currentThread.title||"";color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.heading;font.bold:true;wrapMode:Text.WordWrap}
                Button{text:"@"+(root.currentThread.handle||"");bordered:false;foreground:root.foreground;onClicked:root.loadProfile(root.currentThread.handle)}
                PanelSeparator{width:parent.width}
                Text{width:parent.width;textFormat:Text.PlainText;text:root.currentThread.body||"";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;wrapMode:Text.WordWrap}
              }
            }
            PanelSectionHeader{text:"POST OPTIONS";foreground:root.foreground;fontFamily:root.panelFont}
            Flow { width:parent.width;spacing:Style.space(5)
              Button{visible:!!root.currentThread.mine||!!root.currentThread.can_moderate;text:"Edit";iconText:"\uf044";bordered:true;foreground:root.foreground;onClicked:root.prepareEdit("thread",root.currentThread)}
              Button{visible:!!root.currentThread.mine||!!root.currentThread.can_moderate;text:"Delete";iconText:"\uf2ed";bordered:true;foreground:root.foreground;onClicked:{root.editorKind="thread";root.run("delete",JSON.stringify({kind:"thread",id:root.currentThread.id}))}}
              Button{text:"Report";iconText:"\uf024";bordered:true;foreground:root.foreground;onClicked:root.prepareReport("thread",root.currentThread.id)}
              Button{visible:!!root.currentThread.can_moderate;text:root.currentThread.pinned?"Unpin":"Pin";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="thread";root.run("moderation",JSON.stringify({action:"pin",thread_id:root.currentThread.id,enabled:!root.currentThread.pinned}))}}
              Button{visible:!!root.currentThread.can_moderate;text:root.currentThread.locked?"Unlock":"Lock";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="thread";root.run("moderation",JSON.stringify({action:"lock",thread_id:root.currentThread.id,enabled:!root.currentThread.locked}))}}
            }
            PanelSectionHeader{text:"REPLIES";foreground:root.foreground;fontFamily:root.panelFont}
            Row { visible:root.replyPages>1;width:parent.width;spacing:Style.space(6)
              Button{text:"Previous";bordered:true;foreground:root.foreground;enabled:root.replyPage>1;onClicked:root.openThread(root.currentThread.id,root.replyPage-1)}
              Text{anchors.verticalCenter:parent.verticalCenter;textFormat:Text.PlainText;text:"Replies "+root.replyPage+" / "+root.replyPages;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
              Button{text:"Next";bordered:true;foreground:root.foreground;enabled:root.replyPage<root.replyPages;onClicked:root.openThread(root.currentThread.id,root.replyPage+1)}
            }
            Repeater { model:root.currentThread.replies||[];delegate:Rectangle{
              required property var modelData;x:(modelData.depth||0)*Style.space(16);width:parent.width-x;implicitHeight:replyColumn.implicitHeight+Style.space(14);color:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.045);radius:Style.cornerRadius;border.width:1;border.color:modelData.depth?Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.28):Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.11)
              Column{id:replyColumn;anchors.fill:parent;anchors.margins:Style.space(7);spacing:Style.space(4)
                Row{spacing:Style.space(5);BbsChip{label:modelData.parent_handle?"REPLY TO @"+modelData.parent_handle:"REPLY";highlighted:!!modelData.parent_reply_id}Button{text:"@"+modelData.handle+(modelData.edited?"  ·  edited":"");bordered:false;foreground:root.foreground;onClicked:root.loadProfile(modelData.handle)} }
                Text{width:parent.width;textFormat:Text.PlainText;text:modelData.body;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap}
                PanelSeparator{width:parent.width}
                Flow{width:parent.width;spacing:Style.space(4)
                  Button{visible:!modelData.deleted;text:"Reply";iconText:"\uf3e5";bordered:false;foreground:root.foreground;onClicked:root.selectReplyTarget(modelData.id,modelData.handle)}
                  Button{visible:!modelData.deleted&&(modelData.mine||modelData.can_moderate);text:"Edit";bordered:false;foreground:root.foreground;onClicked:root.prepareEdit("reply",modelData)}
                  Button{visible:!modelData.deleted&&(modelData.mine||modelData.can_moderate);text:"Delete";bordered:false;foreground:root.foreground;onClicked:{root.editorKind="reply";root.run("delete",JSON.stringify({kind:"reply",id:modelData.id}))}}
                  Button{visible:!modelData.deleted;text:"Report";bordered:false;foreground:root.foreground;onClicked:root.prepareReport("reply",modelData.id)}
                }
              }
            }}
            Row {
              visible:root.replyTargetId>0; spacing:Style.space(6)
              Text{anchors.verticalCenter:parent.verticalCenter;textFormat:Text.PlainText;text:"Replying to @"+root.replyTargetHandle;color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
              Button{text:"Cancel";bordered:false;foreground:root.foreground;onClicked:root.clearReplyTarget()}
            }
            Controls.TextArea{id:replyBody;visible:!root.currentThread.locked||!!root.currentThread.can_moderate;width:parent.width;height:Style.space(90);textFormat:TextEdit.PlainText;placeholderText:root.replyTargetId?"Write a threaded reply":"Write a reply";wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Button{visible:replyBody.visible;text:"Reply";iconText:"\uf1d8";bordered:true;foreground:root.foreground;enabled:!bridge.running;onClicked:root.run("reply",JSON.stringify({thread_id:root.currentThread.id,parent_reply_id:root.replyTargetId,body:replyBody.text}))}
          }

          Column {
            visible:root.screen==="edit";width:parent.width;spacing:Style.space(8)
            PanelSectionHeader{text:"EDIT "+root.editorKind.toUpperCase();foreground:root.foreground;fontFamily:root.panelFont}
            Flow{visible:root.editorKind==="thread";width:parent.width;spacing:Style.space(5);Repeater{model:root.boardCategories;delegate:Button{required property string modelData;text:modelData.toUpperCase();bordered:true;foreground:root.foreground;active:root.editCategory===modelData;onClicked:root.editCategory=modelData}}}
            TextField{id:editTitle;visible:root.editorKind==="thread";width:parent.width;foreground:root.foreground;maximumLength:120}
            Controls.TextArea{id:editBody;width:parent.width;height:Style.space(160);textFormat:TextEdit.PlainText;wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Row {
              spacing:Style.space(6)
              Button{text:"Save";bordered:true;foreground:root.foreground;onClicked:{var p={kind:root.editorKind,id:root.editorId,body:editBody.text};if(root.editorKind==="thread"){p.title=editTitle.text;p.category=root.editCategory}root.run("edit",JSON.stringify(p))}}
              Button{text:"Cancel";bordered:true;foreground:root.foreground;onClicked:root.screen="thread"}
            }
          }

          Column {
            visible:root.screen==="report";width:parent.width;spacing:Style.space(8)
            PanelSectionHeader{text:"REPORT CONTENT";foreground:root.foreground;fontFamily:root.panelFont}
            Text{width:parent.width;textFormat:Text.PlainText;text:"Explain what should be reviewed by a moderator.";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap}
            Controls.TextArea{id:reportReason;width:parent.width;height:Style.space(120);textFormat:TextEdit.PlainText;placeholderText:"Reason";wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Row {
              spacing:Style.space(6)
              Button{text:"Submit report";bordered:true;foreground:root.foreground;onClicked:root.run("report",JSON.stringify({kind:root.reportKind,id:root.reportId,reason:reportReason.text}))}
              Button{text:"Cancel";bordered:true;foreground:root.foreground;onClicked:root.screen="thread"}
            }
          }

          Column {
            visible:root.screen==="profile";width:parent.width;spacing:Style.space(8)
            Button{text:"Back";iconText:"\uf060";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            PanelSectionHeader{text:"@"+(root.currentProfile.handle||"");foreground:root.foreground;fontFamily:root.panelFont}
            Text{width:parent.width;textFormat:Text.PlainText;text:(root.currentProfile.role||"member").toUpperCase()+"  ·  joined "+(root.currentProfile.joined_at||"");color:Qt.darker(root.foreground,1.35);font.family:root.panelFont;font.pixelSize:Style.font.caption;wrapMode:Text.WordWrap}
            Text{width:parent.width;textFormat:Text.PlainText;text:root.currentProfile.bio||"No bio yet.";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;wrapMode:Text.WordWrap}
            Text{width:parent.width;textFormat:Text.PlainText;text:(root.currentProfile.posts||0)+" posts  ·  "+(root.currentProfile.replies||0)+" replies";color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
            Button{visible:!!root.currentProfile.mine;text:"Edit profile & notifications";iconText:"\uf013";bordered:true;foreground:root.foreground;onClicked:root.loadPreferences()}
            Repeater{model:root.currentProfile.activity||[];delegate:Button{required property var modelData;width:parent.width;text:modelData.kind.toUpperCase()+"  ·  "+modelData.created_at;leftAlign:true;bordered:true;foreground:root.foreground;onClicked:root.openThread(modelData.thread_id)}}
          }

          Column {
            visible:root.screen==="preferences";width:parent.width;spacing:Style.space(8)
            PanelSectionHeader{text:"PROFILE & NOTIFICATIONS";foreground:root.foreground;fontFamily:root.panelFont}
            Controls.TextArea{id:bioField;width:parent.width;height:Style.space(110);textFormat:TextEdit.PlainText;placeholderText:"Short bio";wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Controls.CheckBox{id:mentionToggle;text:"Notify me about @mentions";font.family:root.panelFont;palette.windowText:root.foreground}
            Row {
              spacing:Style.space(6)
              Button{text:"Save";bordered:true;foreground:root.foreground;onClicked:root.run("preferences",JSON.stringify({action:"set",bio:bioField.text,mention_notifications:mentionToggle.checked}))}
              Button{text:"Cancel";bordered:true;foreground:root.foreground;onClicked:root.loadProfile(root.handle)}
            }
          }

          Column {
            visible:root.screen==="mentions";width:parent.width;spacing:Style.space(7)
            Button{text:"Back to posts";iconText:"\uf060";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            PanelSectionHeader{text:"MENTIONS";foreground:root.foreground;fontFamily:root.panelFont}
            Text{visible:mentionModel.count===0;textFormat:Text.PlainText;text:"No mentions.";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
            Repeater{model:mentionModel;delegate:Button{required property int thread_id;required property string actor;required property string created_at;width:parent.width;text:"@"+actor+" mentioned you  ·  "+created_at;iconText:"@";leftAlign:true;bordered:true;foreground:root.foreground;onClicked:root.openThread(thread_id)}}
          }

          Column {
            visible:root.screen==="moderation";width:parent.width;spacing:Style.space(7)
            Button{text:"Back to posts";iconText:"\uf060";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            PanelSectionHeader{text:"USER MODERATION";foreground:root.foreground;fontFamily:root.panelFont}
            TextField{id:moderationHandle;width:parent.width;foreground:root.foreground;placeholderText:"Username";maximumLength:32}
            Flow {
              width:parent.width;spacing:Style.space(5)
              Repeater{model:root.boardCategories;delegate:Button{required property string modelData;text:modelData.toUpperCase();bordered:true;foreground:root.foreground;active:root.moderatorCategory===modelData;onClicked:root.moderatorCategory=modelData}}
            }
            Row {
              spacing:Style.space(5)
              Button{text:"Make category mod";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="moderation";root.run("moderation",JSON.stringify({action:"category_moderator",handle:moderationHandle.text,category:root.moderatorCategory,enabled:true}))}}
              Button{text:"Remove category mod";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="moderation";root.run("moderation",JSON.stringify({action:"category_moderator",handle:moderationHandle.text,category:root.moderatorCategory,enabled:false}))}}
            }
            Row {
              spacing:Style.space(5)
              TextField{id:suspensionHours;width:Style.space(110);foreground:root.foreground;placeholderText:"Hours";inputMethodHints:Qt.ImhDigitsOnly}
              Button{text:"Suspend";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="moderation";root.run("moderation",JSON.stringify({action:"suspend",handle:moderationHandle.text,hours:Number(suspensionHours.text)}))}}
              Button{text:"Unsuspend";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="moderation";root.run("moderation",JSON.stringify({action:"suspend",handle:moderationHandle.text,hours:0}))}}
            }
            PanelSeparator{width:parent.width}
            PanelSectionHeader{text:"OPEN REPORTS";foreground:root.foreground;fontFamily:root.panelFont}
            Text{visible:reportModel.count===0;textFormat:Text.PlainText;text:"No open reports.";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
            Repeater {
              model:reportModel
              delegate:Rectangle {
                required property int id
                required property string target_kind
                required property int target_id
                required property string reporter
                required property string reason
                required property int thread_id
                width:parent.width
                implicitHeight:reportColumn.implicitHeight+Style.space(14)
                color:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.05)
                radius:Style.cornerRadius
                Column {
                  id:reportColumn
                  anchors.fill:parent
                  anchors.margins:Style.space(7)
                  spacing:Style.space(5)
                  Text{width:parent.width;textFormat:Text.PlainText;text:target_kind.toUpperCase()+" #"+target_id+" reported by @"+reporter;color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
                  Text{width:parent.width;textFormat:Text.PlainText;text:reason;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap}
                  Row {
                    spacing:Style.space(5)
                    Button{text:"Open";bordered:true;foreground:root.foreground;enabled:thread_id>0;onClicked:root.openThread(thread_id)}
                    Button{text:"Resolve";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="moderation";root.run("moderation",JSON.stringify({action:"resolve_report",report_id:id}))}}
                  }
                }
              }
            }
          }
        }
      }
      }
    }
  }
}
