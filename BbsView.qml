import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  signal closeRequested()
  signal detachRequested()
  signal reattachRequested()

  property var bar: null
  property var hostWidget: null
  property bool detached: false
  property string launcherPath: ""
  property string screen: "loading"
  property string handle: ""
  property string role: "member"
  property string errorMessage: ""
  property string noticeMessage: ""
  property string pendingAction: ""
  property string pendingInput: ""
  property bool requestTimedOut: false
  property var queuedRequest: null
  property var currentThread: ({})
  property var currentProfile: ({})
  property var preferences: ({handle: "", bio: "", mention_notifications: true, reply_notifications: true, new_post_notifications: false, desktop_notifications: true})
  property var boardCategories: ["general", "projects", "help", "showcase", "meta"]
  property string categoryFilter: "all"
  property string composeCategory: "general"
  property int currentPage: 1
  property int totalPages: 1
  property int visibleUnreadCount: 0
  property int replyPage: 1
  property int replyPages: 1
  property int selectedPostIndex: 0
  property int selectedReplyIndex: -1
  property int selectedMentionIndex: 0
  property int selectedActivityIndex: 0
  property int selectedReportIndex: 0
  property int replyTargetId: 0
  property int focusReplyId: 0
  property string replyTargetHandle: ""
  property bool replyComposerOpen: false
  property string editorKind: ""
  property int editorId: 0
  property string reportKind: ""
  property int reportId: 0
  property string returnScreen: "threads"
  property string moderationReturn: "thread"
  property string moderatorCategory: "general"
  readonly property var barIdentity: hostWidget || root
  readonly property alias focusTarget: keyCatcher
  readonly property real implicitContentHeight: content.implicitHeight
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

  component InlineReplyEditor: Column {
    id: inlineComposer
    property int targetId: 0
    property string targetHandle: ""
    property bool active: false
    signal cancelRequested()
    signal submitRequested(string body)
    visible: active
    width: parent ? parent.width : 0
    spacing: Style.space(5)
    function focusEditor() { inlineBody.forceActiveFocus();root.ensureVisible(inlineComposer) }
    onActiveChanged: {
      if (active) Qt.callLater(focusEditor)
      else inlineBody.clear()
    }
    Row {
      spacing:Style.space(6)
      Text{anchors.verticalCenter:parent.verticalCenter;textFormat:Text.PlainText;text:inlineComposer.targetId?"Replying to @"+inlineComposer.targetHandle:"Replying to original post";color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
      Button{text:"Cancel";bordered:false;foreground:root.foreground;onClicked:inlineComposer.cancelRequested()}
    }
    Rectangle {
      id:editorFrame;width:parent.width;height:Math.min(Style.space(260),Math.max(Style.space(100),inlineBody.contentHeight+inlineBody.topPadding+inlineBody.bottomPadding));radius:Style.cornerRadius
      color:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.065);border.width:1;border.color:inlineBody.activeFocus?root.accent:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.38)
      Flickable {
        id:inlineFlick;anchors.fill:parent;anchors.margins:1;clip:true;contentWidth:width;contentHeight:Math.max(height,inlineBody.implicitHeight);boundsBehavior:Flickable.StopAtBounds
        Controls.ScrollBar.vertical:Controls.ScrollBar{policy:Controls.ScrollBar.AsNeeded}
        Controls.TextArea {
          id:inlineBody;width:inlineFlick.width;height:Math.max(inlineFlick.height,implicitHeight);textFormat:TextEdit.PlainText;placeholderText:inlineComposer.targetId?"Write a threaded reply":"Write a reply";placeholderTextColor:Color.muted;wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;background:null
          onCursorRectangleChanged:{if(cursorRectangle.y<inlineFlick.contentY)inlineFlick.contentY=cursorRectangle.y;else if(cursorRectangle.y+cursorRectangle.height>inlineFlick.contentY+inlineFlick.height)inlineFlick.contentY=Math.min(inlineFlick.contentHeight-inlineFlick.height,cursorRectangle.y+cursorRectangle.height-inlineFlick.height)}
          Keys.onEscapePressed:{inlineComposer.cancelRequested();keyCatcher.forceActiveFocus()}
          Keys.onPressed:function(event){if((event.modifiers&Qt.ControlModifier)&&(event.key===Qt.Key_Return||event.key===Qt.Key_Enter)){inlineComposer.submitRequested(inlineBody.text);event.accepted=true}}
        }
      }
    }
    Row {
      spacing:Style.space(6)
      Button{text:"Submit reply";iconText:"\uf1d8";bordered:true;foreground:root.foreground;enabled:!bridge.running&&inlineBody.text.trim()!=="";onClicked:inlineComposer.submitRequested(inlineBody.text)}
      Text{anchors.verticalCenter:parent.verticalCenter;textFormat:Text.PlainText;text:"Ctrl+Enter to submit";color:Color.muted;font.family:root.panelFont;font.pixelSize:Style.font.caption}
    }
  }

  component SelectableBody: Controls.TextArea {
    readOnly: true
    textFormat: TextEdit.PlainText
    wrapMode: TextEdit.Wrap
    selectByMouse: true
    persistentSelection: true
    activeFocusOnTab: false
    padding: 0
    color: root.foreground
    selectionColor: root.accent
    selectedTextColor: Color.background
    font.family: root.panelFont
    background: null
    height: implicitHeight
    Keys.onEscapePressed: {
      deselect()
      keyCatcher.forceActiveFocus()
    }
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) return
      if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) return
      event.accepted = true
    }
  }

  function open() { refreshIdentity() }
  function openToThread(id) { if(bridge.running)queuedRequest=({action:"thread",input:JSON.stringify({thread_id:id,reply_page:0})});else openThread(id,0) }
  function openToReply(threadId, replyId) { var input=JSON.stringify({thread_id:threadId,reply_page:0,reply_id:replyId});if(bridge.running)queuedRequest=({action:"thread",input:input});else run("thread",input) }
  function close() { root.closeRequested() }
  function switchPanel(direction) { return root.bar && root.bar.switchPanelFrom ? root.bar.switchPanelFrom(root.barIdentity, direction) : false }
  function diagnostic() { return ({screen:screen,selectedPost:selectedPostIndex,selectedReply:selectedReplyIndex,contentY:scroller.contentY,maxScroll:Math.max(0,scroller.contentHeight-scroller.height),keyFocus:keyCatcher.activeFocus,keyBlocked:keyCatcher.blocked,inputFocus:subjectField.activeFocus?"subject":composeBody.activeFocus?"post-body":replyComposerOpen?"reply-body":editTitle.activeFocus?"edit-title":editBody.activeFocus?"edit-body":reportReason.activeFocus?"report":searchField.activeFocus?"search":"",replyTarget:replyTargetId,replyComposerOpen:replyComposerOpen,replyPage:replyPage,replyPages:replyPages}) }
  function scrollBy(amount) { scroller.contentY = Math.max(0, Math.min(scroller.contentY + amount, Math.max(0, scroller.contentHeight - scroller.height))) }
  function ensureVisible(item) {
    if (!item) return
    var point = item.mapToItem(content, 0, 0); var margin = Style.space(12)
    if (point.y < scroller.contentY + margin) scroller.contentY = Math.max(0, point.y-margin)
    else if (point.y + item.height > scroller.contentY + scroller.height-margin) scroller.contentY = Math.min(Math.max(0,scroller.contentHeight-scroller.height), point.y+item.height-scroller.height+margin)
  }
  function moveSelection(delta) {
    if (screen === "threads" && threadModel.count) {
      if (delta < 0 && selectedPostIndex === 0) { scroller.contentY = 0; return }
      if (delta > 0 && selectedPostIndex === threadModel.count-1) { scroller.contentY = Math.max(0,scroller.contentHeight-scroller.height); return }
      selectedPostIndex=Math.max(0,Math.min(threadModel.count-1,selectedPostIndex+delta));ensureVisible(postRepeater.itemAt(selectedPostIndex))
    }
    else if (screen === "thread") moveThreadSelection(delta)
    else if (screen === "mentions" && mentionModel.count) { selectedMentionIndex=Math.max(0,Math.min(mentionModel.count-1,selectedMentionIndex+delta));ensureVisible(mentionRepeater.itemAt(selectedMentionIndex)) }
    else if (screen === "profile" && (currentProfile.activity||[]).length) { selectedActivityIndex=Math.max(0,Math.min(currentProfile.activity.length-1,selectedActivityIndex+delta));ensureVisible(activityRepeater.itemAt(selectedActivityIndex)) }
    else if (screen === "moderation" && reportModel.count) { selectedReportIndex=Math.max(0,Math.min(reportModel.count-1,selectedReportIndex+delta));ensureVisible(reportRepeater.itemAt(selectedReportIndex)) }
    else scrollBy(delta*Style.space(56))
  }
  function moveThreadSelection(delta) {
    var rows=currentThread.replies||[]
    if (delta < 0) {
      if (selectedReplyIndex < 0) { scroller.contentY=0;return }
      selectedReplyIndex--
      ensureVisible(selectedReplyIndex < 0 ? originalPostCard : replyRepeater.itemAt(selectedReplyIndex))
    } else if (delta > 0) {
      if (!rows.length || selectedReplyIndex >= rows.length-1) { scroller.contentY=Math.max(0,scroller.contentHeight-scroller.height);return }
      selectedReplyIndex++
      ensureVisible(replyRepeater.itemAt(selectedReplyIndex))
    }
  }
  function selectedReply() { var rows=currentThread.replies||[];return selectedReplyIndex>=0&&selectedReplyIndex<rows.length?rows[selectedReplyIndex]:null }
  function activateSelection() {
    if (screen === "threads" && threadModel.count) openThread(threadModel.get(selectedPostIndex).id)
    else if (screen === "thread") { var reply=selectedReply();if(reply)selectReplyTarget(reply.id,reply.handle,selectedReplyIndex);else startOriginalReply() }
    else if (screen === "mentions" && mentionModel.count) { var mention=mentionModel.get(selectedMentionIndex);if(mention.reply_id)openToReply(mention.thread_id,Number(mention.reply_id));else openThread(mention.thread_id) }
    else if (screen === "profile") { var activity=currentProfile.activity||[];if(activity.length)openThread(activity[selectedActivityIndex].thread_id) }
    else if (screen === "moderation" && reportModel.count) { var report=reportModel.get(selectedReportIndex);if(report.thread_id>0)openThread(report.thread_id) }
  }
  function deleteSelection() {
    if (screen !== "thread") return
    var reply=selectedReply()
    if (reply && !reply.deleted && (reply.mine||reply.can_moderate)) { editorKind="reply";run("delete",JSON.stringify({kind:"reply",id:reply.id})) }
    else if (!reply && (currentThread.mine||currentThread.can_moderate)) { editorKind="thread";run("delete",JSON.stringify({kind:"thread",id:currentThread.id})) }
  }
  function submitPost() { if(!bridge.running)run("create",JSON.stringify({category:composeCategory,title:subjectField.text,body:composeBody.text})) }
  function submitReply(body, targetId) { if(!bridge.running)run("reply",JSON.stringify({thread_id:currentThread.id,parent_reply_id:targetId,body:body})) }
  function submitEdit() { var p={kind:editorKind,id:editorId,body:editBody.text};if(editorKind==="thread"){p.title=editTitle.text;p.category=editCategory}run("edit",JSON.stringify(p)) }
  function submitReport() { run("report",JSON.stringify({kind:reportKind,id:reportId,reason:reportReason.text})) }
  function submitPreferences() { if(!bridge.running)run("preferences",JSON.stringify({action:"set",handle:profileHandleField.text,bio:bioField.text,mention_notifications:mentionToggle.checked,reply_notifications:replyToggle.checked,new_post_notifications:newPostToggle.checked,desktop_notifications:desktopToggle.checked})) }
  function cycleThreadNotifications() { var current=String(currentThread.notification_mode||"default");var next=current==="default"?"watch":(current==="watch"?"mute":"default");run("thread-notifications",JSON.stringify({thread_id:currentThread.id,mode:next})) }
  function toggleHeart() { if(screen!=="thread")return;var reply=selectedReply();var item=reply||currentThread;if(!item||item.deleted)return;run("like",JSON.stringify({kind:reply?"reply":"thread",id:item.id,enabled:!item.liked})) }
  function cycleCategory(current, delta) { var index=boardCategories.indexOf(current);return boardCategories[(index+delta+boardCategories.length)%boardCategories.length] }
  function editorKey(event, kind) {
    if ((event.modifiers&Qt.AltModifier)&&(event.key===Qt.Key_Left||event.key===Qt.Key_Right)) { var delta=event.key===Qt.Key_Left?-1:1;if(kind==="compose")composeCategory=cycleCategory(composeCategory,delta);else editCategory=cycleCategory(editCategory,delta);event.accepted=true;return }
    if ((event.modifiers&Qt.ControlModifier)&&(event.key===Qt.Key_Return||event.key===Qt.Key_Enter)) { if(kind==="compose")submitPost();else if(kind==="edit")submitEdit();else if(kind==="report")submitReport();event.accepted=true }
  }
  function moderationKey(event) {
    if ((event.modifiers&Qt.AltModifier)&&(event.key===Qt.Key_Left||event.key===Qt.Key_Right)) { moderatorCategory=cycleCategory(moderatorCategory,event.key===Qt.Key_Left?-1:1);event.accepted=true }
    else if ((event.modifiers&Qt.ControlModifier)&&event.key===Qt.Key_H) { suspensionHours.forceActiveFocus();event.accepted=true }
    else if ((event.modifiers&Qt.ControlModifier)&&event.key===Qt.Key_M) { moderationReturn="moderation";run("moderation",JSON.stringify({action:"category_moderator",handle:moderationHandle.text,category:moderatorCategory,enabled:!(event.modifiers&Qt.ShiftModifier)}));event.accepted=true }
    else if ((event.modifiers&Qt.ControlModifier)&&event.key===Qt.Key_S) { moderationReturn="moderation";run("moderation",JSON.stringify({action:"suspend",handle:moderationHandle.text,hours:Number(suspensionHours.text)}));event.accepted=true }
    else if ((event.modifiers&Qt.ControlModifier)&&event.key===Qt.Key_U) { moderationReturn="moderation";run("moderation",JSON.stringify({action:"suspend",handle:moderationHandle.text,hours:0}));event.accepted=true }
  }
  function handleShortcut(key) {
    if (key === "R") { if(screen==="threads")refreshThreads();else if(screen==="thread")openThread(currentThread.id,replyPage) }
    else if ((key === "n" || key === "N") && handle) { screen="compose";Qt.callLater(function(){subjectField.forceActiveFocus()}) }
    else if ((key === "m" || key === "M") && handle) loadMentions(true)
    else if ((key === "g" || key === "G") && role === "admin") loadReports()
    else if ((key === "p" || key === "P") && screen === "thread") { var reply=selectedReply();loadProfile(reply?reply.handle:currentThread.handle) }
    else if ((key === "p" || key === "P") && handle) loadProfile(handle)
    else if ((key === "s" || key === "S") && screen === "threads") searchField.forceActiveFocus()
    else if (key === "[" && screen === "threads") { categoryFilter=cycleCategory(categoryFilter==="all"?boardCategories[0]:categoryFilter,-1);currentPage=1;refreshThreads() }
    else if (key === "]" && screen === "threads") { categoryFilter=cycleCategory(categoryFilter==="all"?boardCategories[boardCategories.length-1]:categoryFilter,1);currentPage=1;refreshThreads() }
    else if ((key === "b" || key === "B") && screen !== "threads" && screen !== "onboarding") refreshThreads()
    else if ((key === "a" || key === "A") && screen === "thread") startOriginalReply()
    else if (key === "0" && screen === "thread") { selectedReplyIndex=-1;scroller.contentY=0 }
    else if (key === "r" && screen === "thread") activateSelection()
    else if (key === "H" && screen === "thread") toggleHeart()
    else if ((key === "t" || key === "T") && screen === "thread") cycleThreadNotifications()
    else if (key === "d" || key === "D") { if(root.detached)root.reattachRequested();else root.detachRequested() }
    else if ((key === "e" || key === "E") && screen === "profile" && currentProfile.mine) loadPreferences()
    else if ((key === "e" || key === "E") && screen === "thread") { reply=selectedReply();if(reply&&(reply.mine||reply.can_moderate))prepareEdit("reply",reply);else if(!reply&&(currentThread.mine||currentThread.can_moderate))prepareEdit("thread",currentThread) }
    else if ((key === "f" || key === "F") && screen === "thread") { reply=selectedReply();prepareReport(reply?"reply":"thread",reply?reply.id:currentThread.id) }
    else if (key === "I" && screen === "thread" && currentThread.can_moderate) { moderationReturn="thread";run("moderation",JSON.stringify({action:"pin",thread_id:currentThread.id,enabled:!currentThread.pinned})) }
    else if (key === "L" && screen === "thread" && currentThread.can_moderate) { moderationReturn="thread";run("moderation",JSON.stringify({action:"lock",thread_id:currentThread.id,enabled:!currentThread.locked})) }
    else if ((key === "u" || key === "U") && screen === "moderation") moderationHandle.forceActiveFocus()
    else if ((key === "v" || key === "V") && screen === "moderation" && reportModel.count) { var report=reportModel.get(selectedReportIndex);moderationReturn="moderation";run("moderation",JSON.stringify({action:"resolve_report",report_id:report.id})) }
  }
  function run(action, input) {
    if (bridge.running || launcherPath === "") return
    errorMessage = ""; noticeMessage = ""; pendingAction = action; pendingInput = input || "";requestTimedOut=false
    bridge.environment = pendingInput !== "" ? ({"OMARCHY_BBS_PAYLOAD":pendingInput}) : ({})
    bridge.command = [launcherPath, action]; bridge.running = true
  }
  function continueWith(action, input) {
    if (bridge.running) queuedRequest = ({action: action, input: input || ""})
    else run(action, input || "")
  }
  function refreshIdentity() { screen = "loading"; run("identity", "") }
  function refreshThreads() { screen = "loading"; run("threads", JSON.stringify({query: searchField.text, category: categoryFilter, page: currentPage})) }
  function openThread(id, page, replyId) { screen = "loading"; run("thread", JSON.stringify({thread_id: id, reply_page: page || 0, reply_id: replyId || 0})) }
  function loadProfile(name) { screen = "loading"; run("profile", JSON.stringify({handle: name || handle})) }
  function loadPreferences() { screen = "loading"; run("preferences", JSON.stringify({action: "get"})) }
  function loadMentions(markRead) { screen = "loading"; run("mentions", JSON.stringify({page: 1, mark_read: !!markRead})) }
  function loadReports() { screen = "loading"; run("moderation", JSON.stringify({action: "list_reports"})) }
  function startOriginalReply() { replyTargetId=0;replyTargetHandle=currentThread.handle||"";replyComposerOpen=true;Qt.callLater(function(){originalReplyEditor.focusEditor()}) }
  function selectReplyTarget(id, name, index) { var item=replyRepeater.itemAt(index);if(!item)return;replyTargetId=id;replyTargetHandle=name;replyComposerOpen=true;Qt.callLater(function(){item.focusComposer()}) }
  function clearReplyTarget() { replyTargetId=0;replyTargetHandle="";replyComposerOpen=false }
  function prepareEdit(kind, item) {
    editorKind = kind; editorId = item.id; returnScreen = kind === "thread" ? "thread" : "thread"
    editTitle.text = kind === "thread" ? item.title : ""
    editBody.text = item.body || ""
    editCategory = item.category || currentThread.category || "general"
    screen = "edit";Qt.callLater(function(){if(editorKind==="thread")editTitle.forceActiveFocus();else editBody.forceActiveFocus()})
  }
  property string editCategory: "general"
  function prepareReport(kind, id) { reportKind = kind; reportId = id; reportReason.text = ""; screen = "report";Qt.callLater(function(){reportReason.forceActiveFocus()}) }
  function afterMutation(message) { noticeMessage = message; screen = "loading"; continueWith("thread", JSON.stringify({thread_id: currentThread.id, reply_page: replyPage})) }
  function parseResult(text) {
    var result
    try { result = JSON.parse(String(text || "{}")) } catch (e) { errorMessage = "The server returned an unreadable response."; screen = handle ? "threads" : "onboarding"; return }
    if (!result.ok) { errorMessage = result.error || "The request failed."; if (screen === "loading") screen = handle ? "threads" : "onboarding"; return }
    if (pendingAction === "identity") {
      if (result.registered) { handle = result.handle; screen = "loading"; continueWith("threads", JSON.stringify({query: "", category: "all", page: 1})) }
      else { handleField.text = result.suggested_handle; screen = "onboarding";Qt.callLater(function(){handleField.forceActiveFocus()}) }
    } else if (pendingAction === "register") {
      handle = result.handle; screen = "loading"; continueWith("threads", JSON.stringify({query: "", category: "all", page: 1}))
    } else if (pendingAction === "threads") {
      threadModel.clear(); boardCategories = result.categories || boardCategories; role = result.role || role
      var rows = result.threads || []; visibleUnreadCount = 0
      for (var i = 0; i < rows.length; ++i) {
        var row = rows[i]
        if (row.pinned === undefined) row.pinned = false
        if (row.locked === undefined) row.locked = false
        if (row.unread === undefined) row.unread = false
        if (row.likes === undefined) row.likes = 0
        if (row.liked === undefined) row.liked = false
        if (row.notification_mode === undefined) row.notification_mode = "default"
        if (row.unread) visibleUnreadCount++
        threadModel.append(row)
      }
      currentPage = result.page || 1; totalPages = result.pages || 1; selectedPostIndex=0;handle = result.handle || handle; screen = "threads";Qt.callLater(function(){keyCatcher.forceActiveFocus()})
    } else if (pendingAction === "thread") {
      clearReplyTarget();var item = result.thread; var replies = item.replies || []
      for (var j = 0; j < replies.length; ++j) { if(replies[j].depth===undefined)replies[j].depth=replies[j].parent_reply_id?1:0;if(replies[j].likes===undefined)replies[j].likes=0;if(replies[j].liked===undefined)replies[j].liked=false }
      if(item.likes===undefined)item.likes=0;if(item.liked===undefined)item.liked=false;if(item.notification_mode===undefined)item.notification_mode="default"
      focusReplyId=item.focus_reply_id||0;selectedReplyIndex=-1;for(j=0;j<replies.length;++j)if(replies[j].id===focusReplyId){selectedReplyIndex=j;break}
      item.replies = replies; currentThread = item; replyPage = item.reply_page || 1; replyPages = item.reply_pages || 1;screen = "thread"; scroller.contentY = 0;Qt.callLater(function(){var target=selectedReplyIndex>=0?replyRepeater.itemAt(selectedReplyIndex):null;if(target)ensureVisible(target);keyCatcher.forceActiveFocus()})
      if (hostWidget && hostWidget.refreshStatus) hostWidget.refreshStatus()
    } else if (pendingAction === "create") {
      subjectField.text = ""; composeBody.text = ""; screen = "loading"; continueWith("thread", JSON.stringify({thread_id: result.thread_id}))
    } else if (pendingAction === "reply") {
      clearReplyTarget(); noticeMessage = "Reply added"; screen = "loading"; continueWith("thread", JSON.stringify({thread_id: currentThread.id, reply_page: result.reply_page || 0}))
    } else if (pendingAction === "like") afterMutation(result.liked?"Heart added":"Heart removed")
    else if (pendingAction === "thread-notifications") afterMutation(result.mode==="watch"?"Watching this thread":(result.mode==="mute"?"Thread muted":"Using global notification settings"))
    else if (pendingAction === "edit") afterMutation("Changes saved")
    else if (pendingAction === "delete") {
      if (editorKind === "thread") { noticeMessage = "Post deleted"; currentPage = 1; refreshThreads() } else afterMutation("Reply deleted")
    } else if (pendingAction === "report") afterMutation("Report submitted")
    else if (pendingAction === "profile") { currentProfile = result.profile; selectedActivityIndex=0;screen = "profile";Qt.callLater(function(){keyCatcher.forceActiveFocus()}) }
    else if (pendingAction === "preferences") {
      preferences = result.preferences
      var preferenceRequest={};try{preferenceRequest=JSON.parse(pendingInput||"{}")}catch(e){}
      if(preferenceRequest.action==="set"){handle=preferences.handle||result.handle||handle;noticeMessage="Profile saved";screen="loading";continueWith("profile",JSON.stringify({handle:handle}))}
      else{profileHandleField.text=preferences.handle||handle;bioField.text=preferences.bio||"";mentionToggle.checked=!!preferences.mention_notifications;replyToggle.checked=preferences.reply_notifications!==false;newPostToggle.checked=!!preferences.new_post_notifications;desktopToggle.checked=preferences.desktop_notifications!==false;screen="preferences";Qt.callLater(function(){profileHandleField.forceActiveFocus()})}
    }
    else if (pendingAction === "mentions") { mentionModel.clear(); rows = result.mentions || []; for (i=0;i<rows.length;++i) mentionModel.append(rows[i]);selectedMentionIndex=0;screen = "mentions";Qt.callLater(function(){keyCatcher.forceActiveFocus()}) }
    else if (pendingAction === "moderation") {
      if (result.reports !== undefined) { reportModel.clear(); rows=result.reports||[];for(i=0;i<rows.length;++i)reportModel.append(rows[i]);selectedReportIndex=0;screen="moderation";Qt.callLater(function(){keyCatcher.forceActiveFocus()}) }
      else if (moderationReturn === "moderation") { noticeMessage = "Moderation action applied"; screen = "loading"; continueWith("moderation", JSON.stringify({action:"list_reports"})) }
      else afterMutation("Moderation action applied")
    }
  }

  ListModel { id: threadModel }
  ListModel { id: mentionModel }
  ListModel { id: reportModel }

  Timer {
    id:requestWatchdog;interval:20000;repeat:false;running:bridge.running
    onTriggered: {
      root.requestTimedOut=true;root.queuedRequest=null
      root.errorMessage="The BBS request timed out. Try again."
      root.screen=root.handle?"threads":"onboarding"
      bridge.running=false
      Qt.callLater(function(){keyCatcher.forceActiveFocus()})
    }
  }

  Process {
    id: bridge
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseResult(text) }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (root.requestTimedOut) { root.requestTimedOut=false;return }
      if (code !== 0 && root.errorMessage === "") root.errorMessage = "The BBS client could not complete the request."
      if (root.queuedRequest) { var next=root.queuedRequest;root.queuedRequest=null;Qt.callLater(function(){root.run(next.action,next.input)}) }
    }
  }

  Item {
    id: panel; anchors.fill: parent
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
        blocked: handleField.activeFocus || searchField.activeFocus || subjectField.activeFocus || composeBody.activeFocus || root.replyComposerOpen || editTitle.activeFocus || editBody.activeFocus || reportReason.activeFocus || profileHandleField.activeFocus || bioField.activeFocus || moderationHandle.activeFocus || suspensionHours.activeFocus
        onMoveRequested: function(dx, dy) {
          if (dy !== 0) root.moveSelection(dy)
          else if (root.screen === "threads" && dx < 0 && root.currentPage > 1) { root.currentPage--;root.refreshThreads() }
          else if (root.screen === "threads" && dx > 0 && root.currentPage < root.totalPages) { root.currentPage++;root.refreshThreads() }
          else if (root.screen === "thread" && dx < 0 && root.replyPage > 1) root.openThread(root.currentThread.id, root.replyPage-1)
          else if (root.screen === "thread" && dx > 0 && root.replyPage < root.replyPages) root.openThread(root.currentThread.id, root.replyPage+1)
        }
        onActivateRequested: root.activateSelection()
        onDeleteRequested: root.deleteSelection()
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
          Item {
            width: parent.width
            implicitHeight: windowModeButton.implicitHeight
            Button {
              id: windowModeButton
              x: parent.width - width
              text: (root.detached ? "Return to bar" : "Open as window") + "  (D)"
              iconText: root.detached ? "\uf2d2" : "\uf35d"
              bordered: true
              foreground: root.foreground
              onClicked: root.detached ? root.reattachRequested() : root.detachRequested()
            }
          }
          PanelSeparator { width: parent.width }
          Text { visible: root.errorMessage!=="";width:parent.width;textFormat:Text.PlainText;text:"! "+root.errorMessage;color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap }
          Text { visible: root.noticeMessage!=="";width:parent.width;textFormat:Text.PlainText;text:root.noticeMessage;color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall }
          Rectangle {
            visible:!!root.hostWidget&&root.hostWidget.updateAvailable;width:parent.width;implicitHeight:updateRow.implicitHeight+Style.space(12);radius:Style.cornerRadius;color:Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.10);border.width:1;border.color:Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.45)
            Row{id:updateRow;anchors.fill:parent;anchors.margins:Style.space(6);spacing:Style.space(7);Text{anchors.verticalCenter:parent.verticalCenter;textFormat:Text.PlainText;text:"BBS "+(root.hostWidget?root.hostWidget.latestVersion:"")+" available";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}Button{text:"Update now";iconText:"\uf019";bordered:true;foreground:root.foreground;onClicked:root.hostWidget.installUpdate()}}
          }
          Text { visible:root.screen==="threads";width:parent.width;textFormat:Text.PlainText;text:(threadModel.count?"POST "+(root.selectedPostIndex+1)+" OF "+threadModel.count+"  ·  ":"")+"↑↓ SELECT  ·  ENTER OPEN  ·  N NEW  ·  S SEARCH";color:Color.muted;font.family:root.panelFont;font.pixelSize:Style.font.caption;wrapMode:Text.WordWrap }
          Text { visible:root.screen==="thread";width:parent.width;textFormat:Text.PlainText;text:(root.selectedReplyIndex<0?"ORIGINAL POST SELECTED":"REPLY "+(root.selectedReplyIndex+1)+" OF "+(root.currentThread.replies||[]).length+" SELECTED")+"  ·  ↑↓ SELECT  ·  ENTER/R REPLY  ·  H HEART  ·  T NOTIFY  ·  A REPLY TO POST  ·  E EDIT  ·  F REPORT  ·  X DELETE  ·  ←→ PAGE";color:Color.muted;font.family:root.panelFont;font.pixelSize:Style.font.caption;wrapMode:Text.WordWrap }
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
              TextField{id:searchField;width:parent.width-Style.space(106);foreground:root.foreground;placeholderText:"Search posts";onAccepted:{root.currentPage=1;root.refreshThreads()} Keys.onEscapePressed:keyCatcher.forceActiveFocus()}
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
            Text{visible:root.visibleUnreadCount>0;width:parent.width;textFormat:Text.PlainText;text:"●  "+root.visibleUnreadCount+(root.visibleUnreadCount===1?" THREAD":" THREADS")+" WITH NEW ACTIVITY";color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall;font.bold:true}
            Text{visible:threadModel.count===0;width:parent.width;textFormat:Text.PlainText;text:"NO POSTS FOUND.";color:Qt.darker(root.foreground,1.35);font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
            Repeater { id:postRepeater;model:threadModel;delegate:Rectangle{
              required property int index;required property int id;required property string category;required property string title;required property string handle;required property string created_at;required property int replies;required property int likes;required property bool liked;required property bool pinned;required property bool locked;required property bool unread;required property string notification_mode
              width:parent.width
              implicitHeight:postCardColumn.implicitHeight+Style.space(16)
              radius:Style.cornerRadius
              color:unread?Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.10):Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,postMouse.containsMouse?.075:.04)
              border.width:1
              border.color:unread?Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.55):Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.12)
              Rectangle{visible:index===root.selectedPostIndex;width:Style.space(3);height:parent.height-Style.space(12);anchors.left:parent.left;anchors.leftMargin:Style.space(3);anchors.verticalCenter:parent.verticalCenter;radius:width/2;color:root.accent}
              Column {
                id:postCardColumn;anchors.fill:parent;anchors.margins:Style.space(8);spacing:Style.space(5)
                Flow {
                  width:parent.width;spacing:Style.space(4)
                  BbsChip{label:category.toUpperCase()}
                  BbsChip{visible:unread;label:"NEW";highlighted:true}
                  BbsChip{visible:pinned;label:"PINNED"}
                  BbsChip{visible:locked;label:"LOCKED"}
                  BbsChip{visible:notification_mode==="watch";label:"WATCHING"}
                  BbsChip{visible:notification_mode==="mute";label:"MUTED"}
                }
                Text{width:parent.width;textFormat:Text.PlainText;text:title;color:unread?root.accent:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;font.bold:true;wrapMode:Text.WordWrap}
                Row {
                  width: parent.width
                  Text{id:postMetaPrefix;textFormat:Text.PlainText;text:"@"+handle+"  ·  "+replies+" repl.  ·  ";color:Color.muted;font.family:root.panelFont;font.pixelSize:Style.font.caption}
                  Text{id:postHeartMeta;textFormat:Text.PlainText;text:"♥ "+likes;color:liked?root.accent:Color.muted;font.family:root.panelFont;font.pixelSize:Style.font.caption;font.bold:liked}
                  Text{width:Math.max(0,parent.width-postMetaPrefix.width-postHeartMeta.width);textFormat:Text.PlainText;text:"  ·  "+created_at;color:Color.muted;font.family:root.panelFont;font.pixelSize:Style.font.caption;elide:Text.ElideRight}
                }
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
            TextField{id:subjectField;width:parent.width;foreground:root.foreground;placeholderText:"Subject";maximumLength:120;Keys.onEscapePressed:{root.screen="threads";keyCatcher.forceActiveFocus()} Keys.onPressed:function(event){root.editorKey(event,"compose")}}
            Controls.ScrollView{id:composeScroll;width:parent.width;height:Math.min(Style.space(300),Math.max(Style.space(150),composeBody.contentHeight+composeBody.topPadding+composeBody.bottomPadding));clip:true;Controls.ScrollBar.vertical.policy:Controls.ScrollBar.AsNeeded;Controls.TextArea{id:composeBody;width:composeScroll.availableWidth;textFormat:TextEdit.PlainText;placeholderText:"Write your post";placeholderTextColor:Color.muted;wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;Keys.onEscapePressed:{root.screen="threads";keyCatcher.forceActiveFocus()} Keys.onPressed:function(event){root.editorKey(event,"compose")} background:Rectangle{color:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.055);border.width:1;border.color:composeBody.activeFocus?root.accent:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.32);radius:Style.cornerRadius}}}
            Row {
              spacing:Style.space(6)
              Button{text:"Post";iconText:"\uf1d8";bordered:true;foreground:root.foreground;enabled:!bridge.running;onClicked:root.submitPost()}
              Button{text:"Cancel";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            }
          }

          Column {
            id:threadScreen;visible:root.screen==="thread";width:parent.width;spacing:Style.space(8)
            Button{text:"Back to posts";iconText:"\uf060";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            Rectangle {
              id:originalPostCard
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
                  BbsChip{visible:String(root.currentThread.notification_mode||"default")!=="default";label:root.currentThread.notification_mode==="watch"?"WATCHING":"MUTED";highlighted:root.currentThread.notification_mode==="watch"}
                }
                Text{width:parent.width;textFormat:Text.PlainText;text:root.currentThread.title||"";color:root.accent;font.family:root.panelFont;font.pixelSize:Style.font.heading;font.bold:true;wrapMode:Text.WordWrap}
                Button{text:"@"+(root.currentThread.handle||"");bordered:false;foreground:root.foreground;onClicked:root.loadProfile(root.currentThread.handle)}
                PanelSeparator{width:parent.width}
                SelectableBody{width:parent.width;text:root.currentThread.body||"";font.pixelSize:Style.font.body}
                InlineReplyEditor{id:originalReplyEditor;active:root.replyComposerOpen&&root.replyTargetId===0&&(!root.currentThread.locked||!!root.currentThread.can_moderate);targetId:0;targetHandle:root.currentThread.handle||"";onCancelRequested:root.clearReplyTarget();onSubmitRequested:function(body){root.submitReply(body,0)}}
              }
            }
            PanelSectionHeader{text:"POST OPTIONS";foreground:root.foreground;fontFamily:root.panelFont}
            Flow { width:parent.width;spacing:Style.space(5)
              Button{text:"Reply";iconText:"↩";bordered:true;foreground:root.foreground;onClicked:root.startOriginalReply()}
              Button{text:(root.currentThread.liked?"Hearted":"Heart")+" · "+(root.currentThread.likes||0);iconText:"♥";bordered:true;active:!!root.currentThread.liked;foreground:root.currentThread.liked?root.accent:root.foreground;onClicked:root.toggleHeart()}
              Button{text:"Notifications: "+(root.currentThread.notification_mode==="watch"?"Watching":(root.currentThread.notification_mode==="mute"?"Muted":"Default"));iconText:root.currentThread.notification_mode==="mute"?"\uf1f6":"\uf0f3";bordered:true;active:root.currentThread.notification_mode==="watch";foreground:root.currentThread.notification_mode==="watch"?root.accent:root.foreground;onClicked:root.cycleThreadNotifications()}
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
            Repeater { id:replyRepeater;model:root.currentThread.replies||[];delegate:Rectangle{
              required property int index;required property var modelData;function focusComposer(){inlineReplyEditor.focusEditor()} x:Math.min(modelData.depth||0,6)*Style.space(16);width:parent.width-x;implicitHeight:replyColumn.implicitHeight+Style.space(14);color:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.045);radius:Style.cornerRadius;border.width:1;border.color:modelData.depth?Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.28):Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.11)
              Rectangle{visible:index===root.selectedReplyIndex;width:Style.space(3);height:parent.height-Style.space(10);anchors.left:parent.left;anchors.leftMargin:Style.space(3);anchors.verticalCenter:parent.verticalCenter;radius:width/2;color:root.accent}
              Column{id:replyColumn;anchors.fill:parent;anchors.margins:Style.space(7);spacing:Style.space(4)
                Row{spacing:Style.space(5);BbsChip{label:modelData.parent_handle?"REPLY TO @"+modelData.parent_handle:"REPLY";highlighted:!!modelData.parent_reply_id}Button{text:"@"+modelData.handle+(modelData.edited?"  ·  edited":"");bordered:false;foreground:root.foreground;onClicked:root.loadProfile(modelData.handle)} }
                SelectableBody{width:parent.width;text:modelData.body;font.pixelSize:Style.font.bodySmall}
                PanelSeparator{width:parent.width}
                Flow{width:parent.width;spacing:Style.space(4)
                  Button{visible:!modelData.deleted;text:(modelData.liked?"Hearted":"Heart")+" · "+(modelData.likes||0);iconText:"♥";bordered:false;active:!!modelData.liked;foreground:modelData.liked?root.accent:root.foreground;onClicked:root.run("like",JSON.stringify({kind:"reply",id:modelData.id,enabled:!modelData.liked}))}
                  Button{visible:!modelData.deleted;text:"Reply";iconText:"↩";bordered:false;foreground:root.foreground;onClicked:root.selectReplyTarget(modelData.id,modelData.handle,index)}
                  Button{visible:!modelData.deleted&&(modelData.mine||modelData.can_moderate);text:"Edit";bordered:false;foreground:root.foreground;onClicked:root.prepareEdit("reply",modelData)}
                  Button{visible:!modelData.deleted&&(modelData.mine||modelData.can_moderate);text:"Delete";bordered:false;foreground:root.foreground;onClicked:{root.editorKind="reply";root.run("delete",JSON.stringify({kind:"reply",id:modelData.id}))}}
                  Button{visible:!modelData.deleted;text:"Report";bordered:false;foreground:root.foreground;onClicked:root.prepareReport("reply",modelData.id)}
                }
                InlineReplyEditor{id:inlineReplyEditor;active:root.replyComposerOpen&&root.replyTargetId===modelData.id&&(!root.currentThread.locked||!!root.currentThread.can_moderate);targetId:modelData.id;targetHandle:modelData.handle;onCancelRequested:root.clearReplyTarget();onSubmitRequested:function(body){root.submitReply(body,modelData.id)}}
              }
            }}
          }

          Column {
            visible:root.screen==="edit";width:parent.width;spacing:Style.space(8)
            PanelSectionHeader{text:"EDIT "+root.editorKind.toUpperCase();foreground:root.foreground;fontFamily:root.panelFont}
            Flow{visible:root.editorKind==="thread";width:parent.width;spacing:Style.space(5);Repeater{model:root.boardCategories;delegate:Button{required property string modelData;text:modelData.toUpperCase();bordered:true;foreground:root.foreground;active:root.editCategory===modelData;onClicked:root.editCategory=modelData}}}
            TextField{id:editTitle;visible:root.editorKind==="thread";width:parent.width;foreground:root.foreground;maximumLength:120;Keys.onEscapePressed:{root.screen="thread";keyCatcher.forceActiveFocus()} Keys.onPressed:function(event){root.editorKey(event,"edit")}}
            Controls.TextArea{id:editBody;width:parent.width;height:Math.max(Style.space(160),contentHeight+topPadding+bottomPadding);textFormat:TextEdit.PlainText;wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;Keys.onEscapePressed:{root.screen="thread";keyCatcher.forceActiveFocus()} Keys.onPressed:function(event){root.editorKey(event,"edit")} background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Row {
              spacing:Style.space(6)
              Button{text:"Save";bordered:true;foreground:root.foreground;onClicked:root.submitEdit()}
              Button{text:"Cancel";bordered:true;foreground:root.foreground;onClicked:root.screen="thread"}
            }
          }

          Column {
            visible:root.screen==="report";width:parent.width;spacing:Style.space(8)
            PanelSectionHeader{text:"REPORT CONTENT";foreground:root.foreground;fontFamily:root.panelFont}
            Text{width:parent.width;textFormat:Text.PlainText;text:"Explain what should be reviewed by a moderator.";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall;wrapMode:Text.WordWrap}
            Controls.TextArea{id:reportReason;width:parent.width;height:Math.max(Style.space(120),contentHeight+topPadding+bottomPadding);textFormat:TextEdit.PlainText;placeholderText:"Reason";wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;Keys.onEscapePressed:{root.screen="thread";keyCatcher.forceActiveFocus()} Keys.onPressed:function(event){if((event.modifiers&Qt.ControlModifier)&&(event.key===Qt.Key_Return||event.key===Qt.Key_Enter)){root.submitReport();event.accepted=true}} background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Row {
              spacing:Style.space(6)
              Button{text:"Submit report";bordered:true;foreground:root.foreground;onClicked:root.submitReport()}
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
            Repeater{id:activityRepeater;model:root.currentProfile.activity||[];delegate:Button{required property int index;required property var modelData;width:parent.width;text:modelData.kind.toUpperCase()+"  ·  "+modelData.created_at;leftAlign:true;bordered:true;active:index===root.selectedActivityIndex;foreground:root.foreground;onClicked:root.openThread(modelData.thread_id)}}
          }

          Column {
            visible:root.screen==="preferences";width:parent.width;spacing:Style.space(8)
            PanelSectionHeader{text:"PROFILE & NOTIFICATIONS";foreground:root.foreground;fontFamily:root.panelFont}
            Controls.TextField{id:profileHandleField;width:parent.width;maximumLength:32;placeholderText:"Username";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;Keys.onEscapePressed:root.loadProfile(root.handle);Keys.onPressed:function(event){if((event.modifiers&Qt.ControlModifier)&&(event.key===Qt.Key_Return||event.key===Qt.Key_Enter)){root.submitPreferences();event.accepted=true}} background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Text{width:parent.width;textFormat:Text.PlainText;text:"3–32 lowercase letters, numbers, hyphens, or underscores. Usernames are unique.";color:Qt.darker(root.foreground,1.35);font.family:root.panelFont;font.pixelSize:Style.font.caption;wrapMode:Text.WordWrap}
            Controls.TextArea{id:bioField;width:parent.width;height:Math.max(Style.space(110),contentHeight+topPadding+bottomPadding);textFormat:TextEdit.PlainText;placeholderText:"Short bio";wrapMode:TextEdit.Wrap;color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.body;Keys.onEscapePressed:root.loadProfile(root.handle);Keys.onPressed:function(event){if((event.modifiers&Qt.ControlModifier)&&event.key===Qt.Key_N){mentionToggle.checked=!mentionToggle.checked;event.accepted=true}else if((event.modifiers&Qt.ControlModifier)&&(event.key===Qt.Key_Return||event.key===Qt.Key_Enter)){root.submitPreferences();event.accepted=true}} background:Rectangle{color:Color.background;border.color:Qt.darker(root.foreground,1.8);radius:Style.cornerRadius}}
            Controls.CheckBox{id:mentionToggle;text:"Notify me about @mentions";font.family:root.panelFont;palette.windowText:root.foreground}
            Controls.CheckBox{id:replyToggle;text:"Notify me about replies to my posts or replies";font.family:root.panelFont;palette.windowText:root.foreground}
            Controls.CheckBox{id:newPostToggle;text:"Notify me about every new post";font.family:root.panelFont;palette.windowText:root.foreground}
            Controls.CheckBox{id:desktopToggle;text:"Enable desktop notifications";font.family:root.panelFont;palette.windowText:root.foreground}
            Text{width:parent.width;textFormat:Text.PlainText;text:"Thread settings override these defaults. Watching adds all replies; Muted suppresses alerts without changing unread or mention history.";color:Color.muted;font.family:root.panelFont;font.pixelSize:Style.font.caption;wrapMode:Text.WordWrap}
            Row {
              spacing:Style.space(6)
              Button{text:"Save";bordered:true;foreground:root.foreground;onClicked:root.submitPreferences()}
              Button{text:"Cancel";bordered:true;foreground:root.foreground;onClicked:root.loadProfile(root.handle)}
            }
          }

          Column {
            visible:root.screen==="mentions";width:parent.width;spacing:Style.space(7)
            Button{text:"Back to posts";iconText:"\uf060";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            PanelSectionHeader{text:"MENTIONS";foreground:root.foreground;fontFamily:root.panelFont}
            Text{visible:mentionModel.count===0;textFormat:Text.PlainText;text:"No mentions.";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
            Repeater{id:mentionRepeater;model:mentionModel;delegate:Button{required property int index;required property int thread_id;required property var reply_id;required property string actor;required property string created_at;width:parent.width;text:"@"+actor+" mentioned you  ·  "+created_at;iconText:"@";leftAlign:true;bordered:true;active:index===root.selectedMentionIndex;foreground:root.foreground;onClicked:reply_id?root.openToReply(thread_id,Number(reply_id)):root.openThread(thread_id)}}
          }

          Column {
            visible:root.screen==="moderation";width:parent.width;spacing:Style.space(7)
            Button{text:"Back to posts";iconText:"\uf060";bordered:true;foreground:root.foreground;onClicked:root.refreshThreads()}
            PanelSectionHeader{text:"USER MODERATION";foreground:root.foreground;fontFamily:root.panelFont}
            TextField{id:moderationHandle;width:parent.width;foreground:root.foreground;placeholderText:"Username";maximumLength:32;Keys.onEscapePressed:keyCatcher.forceActiveFocus();Keys.onPressed:function(event){root.moderationKey(event)}}
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
              TextField{id:suspensionHours;width:Style.space(110);foreground:root.foreground;placeholderText:"Hours";inputMethodHints:Qt.ImhDigitsOnly;Keys.onEscapePressed:keyCatcher.forceActiveFocus();Keys.onPressed:function(event){root.moderationKey(event)}}
              Button{text:"Suspend";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="moderation";root.run("moderation",JSON.stringify({action:"suspend",handle:moderationHandle.text,hours:Number(suspensionHours.text)}))}}
              Button{text:"Unsuspend";bordered:true;foreground:root.foreground;onClicked:{root.moderationReturn="moderation";root.run("moderation",JSON.stringify({action:"suspend",handle:moderationHandle.text,hours:0}))}}
            }
            PanelSeparator{width:parent.width}
            PanelSectionHeader{text:"OPEN REPORTS";foreground:root.foreground;fontFamily:root.panelFont}
            Text{visible:reportModel.count===0;textFormat:Text.PlainText;text:"No open reports.";color:root.foreground;font.family:root.panelFont;font.pixelSize:Style.font.bodySmall}
            Repeater { id:reportRepeater
              model:reportModel
              delegate:Rectangle {
                required property int index
                required property int id
                required property string target_kind
                required property int target_id
                required property string reporter
                required property string reason
                required property int thread_id
                width:parent.width
                implicitHeight:reportColumn.implicitHeight+Style.space(14)
                color:index===root.selectedReportIndex?Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.08):Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.05)
                radius:Style.cornerRadius
                border.width:1
                border.color:Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,.12)
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
        MouseArea {
          anchors.fill: parent
          z: 10
          enabled: !root.replyComposerOpen && ["compose", "edit", "report", "preferences"].indexOf(root.screen) < 0
          acceptedButtons: Qt.NoButton
          propagateComposedEvents: true
          onWheel: function(wheel) {
            var pixelY = wheel.pixelDelta ? wheel.pixelDelta.y : 0
            if (pixelY !== 0) {
              root.scrollBy(-pixelY * 6.0)
              wheel.accepted = true
            } else {
              wheel.accepted = false
            }
          }
        }
      }
      }
    }
  }
}
