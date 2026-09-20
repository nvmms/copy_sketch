import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: win
    width: 1440; height: 900; minimumWidth: 1100; minimumHeight: 700
    visible: true; title: "Linea — "+documentName+(documentModified?" *":""); color: systemDark?"#111214":"#eceef1"
    readonly property bool systemDark:Application.styleHints.colorScheme===Qt.ColorScheme.Dark
    palette.window:systemDark?"#191a1d":"#f4f4f5"
    palette.windowText:systemDark?"#f4f4f5":"#202124"
    palette.base:systemDark?"#232429":"#ffffff"
    palette.alternateBase:systemDark?"#292a30":"#eceef1"
    palette.text:systemDark?"#f4f4f5":"#202124"
    palette.button:systemDark?"#232429":"#f4f4f5"
    palette.buttonText:systemDark?"#f4f4f5":"#202124"
    palette.highlight:accent
    palette.highlightedText:"#ffffff"
    palette.placeholderText:systemDark?"#92959e":"#74777f"
    readonly property color panel:systemDark?"#191a1d":"#f7f7f8"
    readonly property color line:systemDark?"#2b2d32":"#d7d8dc"
    readonly property color muted:systemDark?"#92959e":"#696c74"
    readonly property color ink:systemDark?"#f4f4f5":"#202124"
    readonly property color surface:systemDark?"#232429":"#ffffff"
    readonly property color hoverSurface:systemDark?"#303238":"#e8e9ed"
    readonly property color selectedSurface:systemDark?"#302d49":"#e7e3ff"
    readonly property color subtleInk:systemDark?"#c7c9ce":"#4f525a"
    readonly property color workspaceBackground:systemDark?"#292a2e":"#dedfe3"
    readonly property color gridLine:systemDark?"#323339":"#cfd1d6"
    readonly property color controlBorder:systemDark?"#484a50":"#c9cbd1"
    readonly property color accent: "#6c5ce7"
    property int selected: 0
    property var selection: [0]
    property int layerSelectionAnchor: 0
    property string tool: "select"
    property real zoom: 1
    property bool grid: true
    property bool rightOpen: true
    property int nextId: 8
    property int currentPage: 0
    property int nextPage: 3
    property real pagesPanelHeight: 76
    // Each entry is the in-memory layer document owned by the page at the same index.
    property var pageDocuments: []
    property bool marqueeActive: false
    property real marqueeStartX: 0
    property real marqueeStartY: 0
    property real marqueeX: 0
    property real marqueeY: 0
    property real marqueeWidth: 0
    property real marqueeHeight: 0
    property var pageUndoStacks: []
    property var pageRedoStacks: []
    property bool restoringHistory: false
    property url currentFileUrl:""
    property bool documentModified:false
    property string documentName:currentFileUrl.toString().length?decodeURIComponent(currentFileUrl.toString().split("/").pop()):"Untitled design"
    property bool drawingShape: false
    property real drawStartX: 0
    property real drawStartY: 0
    property real drawX: 0
    property real drawY: 0
    property real drawWidth: 0
    property real drawHeight: 0
    readonly property string selectedType: selected>=0 && selected<layers.count ? layers.get(selected).type : ""

    function value(role, fallback) {
        if (selected < 0 || selected >= layers.count) return fallback
        var v = layers.get(selected)[role]
        return v === undefined ? fallback : v
    }
    function setValue(role, v) {
        if (selected < 0 || selected >= layers.count || layers.get(selected)[role] === v) return
        recordHistory()
        layers.setProperty(selected, role, v)
    }
    function setAllCorners(v) {
        if(selected<0 || selected>=layers.count) return
        recordHistory()
        layers.setProperty(selected,"corner",v)
        layers.setProperty(selected,"cornerTL",v);layers.setProperty(selected,"cornerTR",v)
        layers.setProperty(selected,"cornerBL",v);layers.setProperty(selected,"cornerBR",v)
    }
    function selectOnly(index) {
        selected=index
        selection=index>=0?[index]:[]
        if(index>=0)layerSelectionAnchor=index
    }
    function isSelected(index) { return selection.indexOf(index)>=0 }
    function selectLayerFromList(index, modifiers) {
        var useControl=(modifiers&Qt.ControlModifier)!==0
        var useShift=(modifiers&Qt.ShiftModifier)!==0
        if(useShift&&layerSelectionAnchor>=0) {
            var first=Math.min(layerSelectionAnchor,index)
            var last=Math.max(layerSelectionAnchor,index)
            var picked=useControl?selection.slice():[]
            for(var i=first;i<=last;i++)if(picked.indexOf(i)<0)picked.push(i)
            picked.sort(function(a,b){return a-b})
            selection=picked;selected=index
            return
        }
        if(useControl) {
            var toggled=selection.slice()
            var position=toggled.indexOf(index)
            if(position>=0)toggled.splice(position,1)
            else toggled.push(index)
            selection=toggled;selected=toggled.length?(position>=0?toggled[toggled.length-1]:index):-1
            layerSelectionAnchor=index
            return
        }
        selectOnly(index)
    }
    function beginMarquee(x, y) {
        marqueeStartX=x;marqueeStartY=y;marqueeX=x;marqueeY=y
        marqueeWidth=0;marqueeHeight=0;marqueeActive=true
        selectOnly(-1)
    }
    function updateMarquee(x, y) {
        marqueeX=Math.min(marqueeStartX,x);marqueeY=Math.min(marqueeStartY,y)
        marqueeWidth=Math.abs(x-marqueeStartX);marqueeHeight=Math.abs(y-marqueeStartY)
        var picked=[]
        for(var i=0;i<layers.count;i++) {
            var s=layers.get(i)
            if(!s.shown || s.locked) continue
            var left=artboard.x+s.px*zoom, top=artboard.y+s.py*zoom
            var right=left+s.sw*zoom, bottom=top+s.sh*zoom
            if(right>=marqueeX && left<=marqueeX+marqueeWidth && bottom>=marqueeY && top<=marqueeY+marqueeHeight)
                picked.push(i)
        }
        selection=picked
        selected=picked.length?picked[picked.length-1]:-1
    }
    function finishMarquee() { marqueeActive=false }
    function isShapeTool(kind) { return kind==="rect" || kind==="ellipse" || kind==="text" || kind==="frame" }
    function syncWorkspaceCursor() {
        if(!workspaceHover.hovered || isShapeTool(tool)) cursorController.leaveArtboard()
        else cursorController.enterArtboard()
    }
    onToolChanged:syncWorkspaceCursor()
    function appendShape(kind, x, y, width, height) {
        recordHistory()
        var n = nextId++
        var o = {shapeId:n, type:kind, name:"Rectangle", px:x, py:y,
            sw:width, sh:height, fillColor:"#6c5ce7", strokeColor:"#ffffff", strokeSize:0,
            corner:16, cornerTL:16, cornerTR:16, cornerBL:16, cornerBR:16,
            fontSize:16, fontFamily:"Arial", fontWeight:Font.Normal, letterSpacing:0, lineHeight:20, textAlign:Text.AlignLeft,
            alpha:1, shown:true, locked:false, copy:""}
        if (kind === "ellipse") { o.name="Ellipse"; o.fillColor="#ff6b9d"; o.corner=Math.min(width,height)/2;o.cornerTL=o.corner;o.cornerTR=o.corner;o.cornerBL=o.corner;o.cornerBR=o.corner }
        else if (kind === "text") { o.name="Heading"; o.fillColor="#18171d"; o.copy="New headline"; o.corner=0;o.cornerTL=0;o.cornerTR=0;o.cornerBL=0;o.cornerBR=0 }
        else if (kind === "frame") { o.name="Frame "+n; o.fillColor="#ffffff"; o.corner=12;o.cornerTL=12;o.cornerTR=12;o.cornerBL=12;o.cornerBR=12 }
        layers.append(o); selectOnly(layers.count-1)
    }
    function beginDrawing(x, y) {
        drawStartX=(x-artboard.x)/zoom;drawStartY=(y-artboard.y)/zoom;drawX=drawStartX;drawY=drawStartY
        drawWidth=0;drawHeight=0;drawingShape=true;selectOnly(-1)
    }
    function updateDrawing(x, y, modifiers) {
        var logicalX=(x-artboard.x)/zoom
        var logicalY=(y-artboard.y)/zoom
        var deltaX=logicalX-drawStartX
        var deltaY=logicalY-drawStartY
        var constrainProportions=(tool==="rect" || tool==="ellipse") && (modifiers & Qt.ControlModifier)
        if(constrainProportions) {
            var size=Math.max(Math.abs(deltaX),Math.abs(deltaY))
            drawX=deltaX<0?drawStartX-size:drawStartX
            drawY=deltaY<0?drawStartY-size:drawStartY
            drawWidth=size;drawHeight=size
        } else {
            drawX=Math.min(drawStartX,logicalX);drawY=Math.min(drawStartY,logicalY)
            drawWidth=Math.abs(deltaX);drawHeight=Math.abs(deltaY)
        }
    }
    function finishDrawing() {
        if(!drawingShape) return
        drawingShape=false
        if(drawWidth*zoom<3 || drawHeight*zoom<3) return
        appendShape(tool,drawX,drawY,drawWidth,drawHeight)
    }
    function duplicate() {
        if (selected<0) return
        recordHistory()
        var s=layers.get(selected)
        layers.append({shapeId:nextId++,type:s.type,name:s.name+" copy",px:s.px+18,py:s.py+18,sw:s.sw,sh:s.sh,
            fillColor:s.fillColor,strokeColor:s.strokeColor,strokeSize:s.strokeSize,corner:s.corner,cornerTL:s.cornerTL,cornerTR:s.cornerTR,cornerBL:s.cornerBL,cornerBR:s.cornerBR,
            fontSize:s.fontSize,fontFamily:s.fontFamily,fontWeight:s.fontWeight,letterSpacing:s.letterSpacing,lineHeight:s.lineHeight,textAlign:s.textAlign,
            alpha:s.alpha,shown:s.shown,locked:false,copy:s.copy})
        selectOnly(layers.count-1)
    }
    function remove() {
        if(!selection.length) return
        recordHistory()
        var targets=selection.slice().sort(function(a,b){return b-a})
        for(var i=0;i<targets.length;i++) if(targets[i]>=0&&targets[i]<layers.count) layers.remove(targets[i])
        selectOnly(Math.min(targets[targets.length-1],layers.count-1))
    }
    function layerData(s) {
        return {shapeId:s.shapeId,type:s.type,name:s.name,px:s.px,py:s.py,sw:s.sw,sh:s.sh,
            fillColor:s.fillColor,strokeColor:s.strokeColor,strokeSize:s.strokeSize,corner:s.corner,
            cornerTL:s.cornerTL===undefined?s.corner:s.cornerTL,cornerTR:s.cornerTR===undefined?s.corner:s.cornerTR,
            cornerBL:s.cornerBL===undefined?s.corner:s.cornerBL,cornerBR:s.cornerBR===undefined?s.corner:s.cornerBR,
            fontSize:s.fontSize===undefined?16:s.fontSize,fontFamily:s.fontFamily===undefined?"Arial":s.fontFamily,
            fontWeight:s.fontWeight===undefined?Font.Normal:s.fontWeight,letterSpacing:s.letterSpacing===undefined?0:s.letterSpacing,
            lineHeight:s.lineHeight===undefined?20:s.lineHeight,textAlign:s.textAlign===undefined?Text.AlignLeft:s.textAlign,
            alpha:s.alpha,shown:s.shown,locked:s.locked,copy:s.copy}
    }
    function snapshotLayers() {
        var result=[]
        for(var i=0;i<layers.count;i++) result.push(layerData(layers.get(i)))
        return result
    }
    function snapshotState() {
        return {document:snapshotLayers(),selected:selected,selection:selection.slice()}
    }
    function pushUndoState(state) {
        if(restoringHistory) return
        var stacks=pageUndoStacks.slice()
        var history=(stacks[currentPage] || []).slice()
        history.push(state)
        if(history.length>100) history.shift()
        stacks[currentPage]=history
        pageUndoStacks=stacks
        var redoStacks=pageRedoStacks.slice()
        redoStacks[currentPage]=[]
        pageRedoStacks=redoStacks
        documentModified=true
    }
    function recordHistory() { pushUndoState(snapshotState()) }
    function restoreState(state) {
        restoringHistory=true
        layers.clear()
        for(var i=0;i<state.document.length;i++) layers.append(state.document[i])
        selection=state.selection.slice()
        selected=state.selected
        pageDocuments[currentPage]=snapshotLayers()
        restoringHistory=false
    }
    function undo() {
        var history=(pageUndoStacks[currentPage] || []).slice()
        if(!history.length) return
        var current=snapshotState()
        var previous=history.pop()
        var undoStacks=pageUndoStacks.slice();undoStacks[currentPage]=history;pageUndoStacks=undoStacks
        var redoStacks=pageRedoStacks.slice()
        var future=(redoStacks[currentPage] || []).slice();future.push(current)
        redoStacks[currentPage]=future;pageRedoStacks=redoStacks
        restoreState(previous)
    }
    function redo() {
        var redoStacks=pageRedoStacks.slice()
        var future=(redoStacks[currentPage] || []).slice()
        if(!future.length) return
        var current=snapshotState()
        var next=future.pop()
        redoStacks[currentPage]=future;pageRedoStacks=redoStacks
        var undoStacks=pageUndoStacks.slice()
        var history=(undoStacks[currentPage] || []).slice();history.push(current)
        undoStacks[currentPage]=history;pageUndoStacks=undoStacks
        restoreState(next)
    }
    function setLayerShown(index, shown) {
        if(index<0 || index>=layers.count || layers.get(index).shown===shown) return
        recordHistory();layers.setProperty(index,"shown",shown)
    }
    function saveCurrentPage() {
        if(currentPage>=0 && currentPage<pages.count) pageDocuments[currentPage]=snapshotLayers()
    }
    function switchPage(index) {
        if(index===currentPage || index<0 || index>=pages.count) return
        saveCurrentPage()
        currentPage=index
        layers.clear()
        var document=pageDocuments[index] || []
        for(var i=0;i<document.length;i++) layers.append(document[i])
        selectOnly(layers.count>0?0:-1)
    }
    function addPage() {
        saveCurrentPage()
        pages.append({pageName:"Page "+nextPage++})
        pageDocuments.push([])
        var undoStacks=pageUndoStacks.slice();undoStacks.push([]);pageUndoStacks=undoStacks
        var redoStacks=pageRedoStacks.slice();redoStacks.push([]);pageRedoStacks=redoStacks
        currentPage=pages.count-1
        layers.clear()
        selectOnly(-1)
        documentModified=true
    }
    function documentData() {
        saveCurrentPage()
        var pageList=[]
        for(var i=0;i<pages.count;i++)pageList.push({name:pages.get(i).pageName,layers:pageDocuments[i]||[]})
        return {format:"Linea",version:1,currentPage:currentPage,nextId:nextId,nextPage:nextPage,pages:pageList}
    }
    function newDocument() {
        restoringHistory=true
        layers.clear();pages.clear();pages.append({pageName:"Page 1"})
        pageDocuments=[[]];pageUndoStacks=[[]];pageRedoStacks=[[]]
        currentPage=0;nextId=1;nextPage=2;selectOnly(-1);currentFileUrl="";documentModified=false
        restoringHistory=false
    }
    function loadDocument(data, url) {
        if(!data || data.format!=="Linea" || !data.pages || !data.pages.length){showFileError("This is not a valid Linea document.");return}
        restoringHistory=true
        layers.clear();pages.clear();pageDocuments=[]
        for(var i=0;i<data.pages.length;i++){
            var page=data.pages[i]
            pages.append({pageName:page.name||("Page "+(i+1))})
            var document=[]
            var source=page.layers||[]
            for(var j=0;j<source.length;j++)document.push(layerData(source[j]))
            pageDocuments.push(document)
        }
        currentPage=Math.max(0,Math.min(Number(data.currentPage)||0,pages.count-1))
        var activeDocument=pageDocuments[currentPage]
        for(var k=0;k<activeDocument.length;k++)layers.append(activeDocument[k])
        nextId=Math.max(1,Number(data.nextId)||1);nextPage=Math.max(pages.count+1,Number(data.nextPage)||pages.count+1)
        pageUndoStacks=[];pageRedoStacks=[]
        for(var p=0;p<pages.count;p++){pageUndoStacks.push([]);pageRedoStacks.push([])}
        selectOnly(-1);currentFileUrl=url;documentModified=false;restoringHistory=false
    }
    function saveDocument(url) {
        if(!url || !url.toString().length){saveFileDialog.open();return}
        if(documentFileController.save(url,documentData())){currentFileUrl=url;documentModified=false}
        else showFileError(documentFileController.errorString)
    }
    function openDocument(url) {
        var data=documentFileController.load(url)
        if(documentFileController.errorString.length)showFileError(documentFileController.errorString)
        else loadDocument(data,url)
    }
    function showFileError(message){fileErrorDialog.errorMessage=message;fileErrorDialog.open()}

    Component.onCompleted: {
        pageDocuments=[snapshotLayers(),[
            {shapeId:nextId++,type:"rect",name:"Button component",px:230,py:190,sw:220,sh:56,fillColor:"#6c5ce7",strokeColor:"#ffffff",strokeSize:0,corner:14,cornerTL:14,cornerTR:14,cornerBL:14,cornerBR:14,fontSize:16,fontFamily:"Arial",fontWeight:400,letterSpacing:0,lineHeight:20,textAlign:1,alpha:1,shown:true,locked:false,copy:""},
            {shapeId:nextId++,type:"text",name:"Button label",px:278,py:203,sw:130,sh:30,fillColor:"#ffffff",strokeColor:"#000000",strokeSize:0,corner:0,cornerTL:0,cornerTR:0,cornerBL:0,cornerBR:0,fontSize:14,fontFamily:"Arial",fontWeight:600,letterSpacing:0,lineHeight:18,textAlign:1,alpha:1,shown:true,locked:false,copy:"Primary button"}
        ]]
        pageUndoStacks=[[],[]]
        pageRedoStacks=[[],[]]
    }

    FileDialog{id:openFileDialog;title:"Open Linea document";fileMode:FileDialog.OpenFile;nameFilters:["Linea documents (*.linea *.json)","All files (*)"];onAccepted:openDocument(selectedFile)}
    FileDialog{id:saveFileDialog;title:"Save Linea document";fileMode:FileDialog.SaveFile;defaultSuffix:"linea";nameFilters:["Linea documents (*.linea)"];onAccepted:saveDocument(selectedFile)}
    Dialog{id:fileErrorDialog;property string errorMessage:"";title:"File error";modal:true;anchors.centerIn:parent;standardButtons:Dialog.Ok
        contentItem:Text{text:fileErrorDialog.errorMessage;color:win.ink;wrapMode:Text.Wrap;width:360}
    }
    Shortcut { sequence:"Delete"; onActivated: win.remove() }
    Shortcut { sequence:"Backspace"; onActivated: win.remove() }
    Shortcut { sequence:"Ctrl+D"; onActivated: win.duplicate() }
    Shortcut { sequence:StandardKey.Undo; onActivated: win.undo() }
    Shortcut { sequence:StandardKey.Redo; onActivated: win.redo() }
    Shortcut { sequence:"V"; onActivated: tool="select" }
    Shortcut { sequence:"R"; onActivated: tool="rect" }
    Shortcut { sequence:"O"; onActivated: tool="ellipse" }
    Shortcut { sequence:"T"; onActivated: tool="text" }
    Shortcut { sequence:"F"; onActivated: tool="frame" }
    Shortcut { sequence:"Escape"; onActivated:{drawingShape=false;tool="select"} }
    Shortcut { sequence:"Ctrl+-"; onActivated: zoom=Math.max(.25,zoom-.1) }
    Shortcut { sequence:"Ctrl++"; onActivated: zoom=Math.min(2,zoom+.1) }

    ListModel {
        id: layers
        ListElement { shapeId:1; type:"rect"; name:"Primary card"; px:126; py:108; sw:370; sh:250; fillColor:"#ffffff"; strokeColor:"#e9e8ef"; strokeSize:1; corner:24; cornerTL:24; cornerTR:24; cornerBL:24; cornerBR:24; fontSize:16; fontFamily:"Arial"; fontWeight:400; letterSpacing:0; lineHeight:20; textAlign:1; alpha:1; shown:true; locked:false; copy:"" }
        ListElement { shapeId:2; type:"text"; name:"Design freely"; px:164; py:146; sw:290; sh:56; fillColor:"#18171d"; strokeColor:"#000000"; strokeSize:0; corner:0; cornerTL:0; cornerTR:0; cornerBL:0; cornerBR:0; fontSize:36; fontFamily:"Arial"; fontWeight:700; letterSpacing:0; lineHeight:44; textAlign:1; alpha:1; shown:true; locked:false; copy:"Design freely" }
        ListElement { shapeId:3; type:"text"; name:"Subtitle"; px:165; py:214; sw:280; sh:46; fillColor:"#777681"; strokeColor:"#000000"; strokeSize:0; corner:0; cornerTL:0; cornerTR:0; cornerBL:0; cornerBR:0; fontSize:16; fontFamily:"Arial"; fontWeight:400; letterSpacing:0; lineHeight:22; textAlign:1; alpha:1; shown:true; locked:false; copy:"Create interfaces that feel alive." }
        ListElement { shapeId:4; type:"rect"; name:"Action button"; px:165; py:286; sw:142; sh:44; fillColor:"#6c5ce7"; strokeColor:"#000000"; strokeSize:0; corner:12; cornerTL:12; cornerTR:12; cornerBL:12; cornerBR:12; fontSize:16; fontFamily:"Arial"; fontWeight:400; letterSpacing:0; lineHeight:20; textAlign:1; alpha:1; shown:true; locked:false; copy:"" }
        ListElement { shapeId:5; type:"text"; name:"Button label"; px:186; py:297; sw:108; sh:25; fillColor:"#ffffff"; strokeColor:"#000000"; strokeSize:0; corner:0; cornerTL:0; cornerTR:0; cornerBL:0; cornerBR:0; fontSize:14; fontFamily:"Arial"; fontWeight:600; letterSpacing:0; lineHeight:18; textAlign:1; alpha:1; shown:true; locked:false; copy:"Get started  →" }
        ListElement { shapeId:6; type:"ellipse"; name:"Orb"; px:560; py:140; sw:224; sh:224; fillColor:"#fd79a8"; strokeColor:"#ffffff"; strokeSize:0; corner:112; cornerTL:112; cornerTR:112; cornerBL:112; cornerBR:112; fontSize:16; fontFamily:"Arial"; fontWeight:400; letterSpacing:0; lineHeight:20; textAlign:1; alpha:.92; shown:true; locked:false; copy:"" }
        ListElement { shapeId:7; type:"ellipse"; name:"Orb highlight"; px:612; py:178; sw:78; sh:78; fillColor:"#ffd6e6"; strokeColor:"#ffffff"; strokeSize:0; corner:39; cornerTL:39; cornerTR:39; cornerBL:39; cornerBR:39; fontSize:16; fontFamily:"Arial"; fontWeight:400; letterSpacing:0; lineHeight:20; textAlign:1; alpha:.78; shown:true; locked:false; copy:"" }
    }
    ListModel {
        id: pages
        ListElement { pageName:"Landing page" }
        ListElement { pageName:"Components" }
    }

    component TinyButton: AbstractButton {
        id:b; property string glyph:""; implicitWidth:30; implicitHeight:30; hoverEnabled:true
        contentItem:Text{text:b.glyph;color:b.hovered?"white":win.muted;font.pixelSize:14;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter}
        background:Rectangle{color:b.hovered?win.hoverSurface:"transparent";radius:7}
    }
    component ToolButton: AbstractButton {
        id:b; property string glyph:""; property string key:""; implicitWidth:36; implicitHeight:36; hoverEnabled:true
        contentItem:Text{text:b.glyph;color:win.tool===b.key?"white":win.subtleInk;font.pixelSize:16;font.weight:Font.Medium;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter}
        background:Rectangle{color:win.tool===b.key?win.accent:(b.hovered?win.hoverSurface:"transparent");radius:8}
        ToolTip.visible:hovered; ToolTip.text:key
        onClicked:win.tool=key
    }
    component Divider: Rectangle { color:win.line; implicitHeight:1; implicitWidth:1 }
    component NumBox: Rectangle {
        id:box; property string label:"X"; property real number:0; signal edited(real number)
        Layout.fillWidth:true; implicitWidth:112; implicitHeight:32; color:win.surface; border.color:field.activeFocus?win.accent:win.controlBorder; radius:7
        RowLayout{anchors.fill:parent;anchors.leftMargin:9;anchors.rightMargin:6;spacing:5
            Text{text:box.label;color:win.muted;font.pixelSize:11;Layout.preferredWidth:label.length?13:0}
            TextInput{id:field;Layout.fillWidth:true;color:win.ink;font.pixelSize:11;text:Math.round(box.number*10)/10;selectByMouse:true;validator:DoubleValidator{bottom:-9999;top:9999} onEditingFinished:box.edited(parseFloat(text)||0)}
        }
    }
    component Section: ColumnLayout {
        property string heading:"Section"; Layout.fillWidth:true; Layout.leftMargin:16;Layout.rightMargin:16;Layout.topMargin:14;Layout.bottomMargin:14;spacing:10
        Text{text:parent.heading;color:win.ink;font.pixelSize:11;font.weight:Font.DemiBold}
    }

    Action{id:newDocumentAction;text:"New";shortcut:"Ctrl+N";onTriggered:newDocument()}
    Action{id:openDocumentAction;text:"Open…";shortcut:"Ctrl+O";onTriggered:openFileDialog.open()}
    Action{id:saveDocumentAction;text:"Save";shortcut:"Ctrl+S";onTriggered:saveDocument(currentFileUrl)}
    Action{id:saveAsDocumentAction;text:"Save As…";shortcut:"Ctrl+Shift+S";onTriggered:saveFileDialog.open()}

    menuBar:MenuBar{
        Menu{title:"File"
            MenuItem{action:newDocumentAction}
            MenuItem{action:openDocumentAction}
            MenuSeparator{}
            MenuItem{action:saveDocumentAction}
            MenuItem{action:saveAsDocumentAction}
        }
        Menu{title:"Edit"
            MenuItem{text:"Undo";enabled:(pageUndoStacks[currentPage]||[]).length>0;onTriggered:undo()}
            MenuItem{text:"Redo";enabled:(pageRedoStacks[currentPage]||[]).length>0;onTriggered:redo()}
            MenuSeparator{}
            MenuItem{text:"Duplicate";enabled:selected>=0;onTriggered:duplicate()}
            MenuItem{text:"Delete";enabled:selection.length>0;onTriggered:remove()}
        }
        Menu{title:"View"
            MenuItem{text:grid?"Hide Grid":"Show Grid";onTriggered:grid=!grid}
            MenuSeparator{}
            MenuItem{text:"Zoom In";onTriggered:zoom=Math.min(2,zoom+.1)}
            MenuItem{text:"Zoom Out";onTriggered:zoom=Math.max(.25,zoom-.1)}
            MenuItem{text:"Actual Size";onTriggered:zoom=1}
        }
    }

    header:Rectangle{
        height:52;color:win.panel;border.color:win.line
        RowLayout{anchors.left:parent.left;anchors.leftMargin:14;anchors.verticalCenter:parent.verticalCenter;spacing:10
                Rectangle{width:30;height:30;radius:9;color:win.accent;Text{anchors.centerIn:parent;text:"L";color:"white";font.pixelSize:18;font.bold:true;font.italic:true}}
                ColumnLayout{spacing:-1;Text{text:"Linea";color:win.ink;font.pixelSize:14;font.weight:Font.DemiBold}Text{text:win.documentName+(win.documentModified?" *":"");color:win.muted;font.pixelSize:10;elide:Text.ElideMiddle;Layout.preferredWidth:150}}
        }
        Divider{x:251;anchors.top:parent.top;anchors.bottom:parent.bottom;anchors.topMargin:8;anchors.bottomMargin:8}
        RowLayout{anchors.centerIn:parent;spacing:4
                ToolButton{glyph:"↖";key:"select"} ToolButton{glyph:"F";key:"frame"} ToolButton{glyph:"□";key:"rect"}
                ToolButton{glyph:"○";key:"ellipse"} ToolButton{glyph:"T";key:"text"} ToolButton{glyph:"✎";key:"pen"}
        }
        RowLayout{anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;spacing:6
                TinyButton{glyph:"↶"} TinyButton{glyph:"↷"} Divider{height:22}
                AbstractButton{id:zoomBtn;implicitWidth:68;implicitHeight:30;hoverEnabled:true;contentItem:Text{text:Math.round(win.zoom*100)+"%";color:win.subtleInk;font.pixelSize:12;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter} background:Rectangle{color:zoomBtn.hovered?win.hoverSurface:"transparent";radius:7} onClicked:zoom=zoom===1?.75:1}
                Button{text:"Share";implicitWidth:72;implicitHeight:32;contentItem:Text{text:parent.text;color:"white";font.pixelSize:12;font.weight:Font.DemiBold;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter} background:Rectangle{color:parent.hovered?"#7b6fea":win.accent;radius:8}}
                Rectangle{width:30;height:30;radius:15;color:"#f2b84b";Text{anchors.centerIn:parent;text:"H";color:"#3b2b09";font.pixelSize:12;font.bold:true}}
        }
    }

    RowLayout{anchors.fill:parent;spacing:0
        Rectangle{
            Layout.preferredWidth:252;Layout.fillHeight:true;color:win.panel;border.color:win.line
            ColumnLayout{anchors.fill:parent;spacing:0
                RowLayout{Layout.fillWidth:true;Layout.preferredHeight:46;Layout.leftMargin:14;Layout.rightMargin:10
                    Text{text:"Pages";color:win.ink;font.pixelSize:12;font.weight:Font.DemiBold}Item{Layout.fillWidth:true}TinyButton{glyph:"+";onClicked:addPage()}}
                ScrollView{
                    Layout.fillWidth:true;Layout.preferredHeight:pagesPanelHeight;clip:true
                    contentWidth:availableWidth
                    Column{
                        width:parent.width;leftPadding:8;rightPadding:8;bottomPadding:8
                        Repeater{model:pages;delegate:Rectangle{
                            required property int index;required property string pageName
                            width:parent.width-16;height:34;radius:6;color:index===currentPage?win.selectedSurface:(pageHover.containsMouse?win.hoverSurface:"transparent")
                            RowLayout{anchors.fill:parent;anchors.leftMargin:10;anchors.rightMargin:8;spacing:8
                                Text{text:"◇";color:index===currentPage?win.accent:win.muted;font.pixelSize:11}
                                Text{text:pageName;color:index===currentPage?win.ink:win.subtleInk;font.pixelSize:12;Layout.fillWidth:true;elide:Text.ElideRight}
                                Text{visible:index===currentPage;text:"•";color:win.accent;font.pixelSize:14}
                            }
                            MouseArea{id:pageHover;anchors.fill:parent;hoverEnabled:true;onClicked:switchPage(index)}
                        }}
                    }
                }
                Rectangle{
                    id:pageSplitter;Layout.fillWidth:true;Layout.preferredHeight:7;color:splitterMouse.containsMouse||splitterMouse.pressed?win.hoverSurface:"transparent"
                    Rectangle{anchors.centerIn:parent;width:32;height:3;radius:2;color:splitterMouse.containsMouse||splitterMouse.pressed?win.accent:win.line}
                    MouseArea{
                        id:splitterMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.SplitVCursor
                        property real pressY:0;property real pressHeight:0
                        onPressed:function(mouse){pressY=mapToItem(win.contentItem,mouse.x,mouse.y).y;pressHeight=pagesPanelHeight}
                        onPositionChanged:function(mouse){if(pressed){var yNow=mapToItem(win.contentItem,mouse.x,mouse.y).y;pagesPanelHeight=Math.max(34,Math.min(280,pressHeight+yNow-pressY))}}
                    }
                }
                Divider{Layout.fillWidth:true}
                RowLayout{Layout.fillWidth:true;Layout.preferredHeight:42;Layout.leftMargin:14;Layout.rightMargin:10
                    Text{text:"Layers";color:win.ink;font.pixelSize:12;font.weight:Font.DemiBold}Item{Layout.fillWidth:true}TinyButton{glyph:"+";onClicked:tool="rect"}}
                Divider{Layout.fillWidth:true}
                ScrollView{id:layersScroll;Layout.fillWidth:true;Layout.fillHeight:true;clip:true
                    Item{width:layersScroll.availableWidth;height:Math.max(layersColumn.implicitHeight,layersScroll.availableHeight)
                        MouseArea{anchors.fill:parent;onClicked:win.selectOnly(-1)}
                        Column{id:layersColumn;width:parent.width;topPadding:8
                            Repeater{model:layers;delegate:Rectangle{
                                required property int index;required property string name;required property string type;required property bool shown;required property bool locked
                                width:parent.width;height:38;radius:6;color:win.isSelected(index)?win.selectedSurface:(hover.containsMouse?win.hoverSurface:"transparent")
                                Rectangle{visible:win.isSelected(index);width:2;height:22;radius:1;color:win.accent;anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter}
                                RowLayout{anchors.fill:parent;anchors.leftMargin:10;anchors.rightMargin:8;spacing:8
                                    Text{text:type==="text"?"T":(type==="ellipse"?"○":type==="frame"?"#":"□");color:win.isSelected(index)?win.accent:win.muted;font.pixelSize:12;Layout.preferredWidth:18;horizontalAlignment:Text.AlignHCenter}
                                    Text{text:name;color:win.isSelected(index)?win.ink:win.subtleInk;font.pixelSize:12;elide:Text.ElideRight;Layout.fillWidth:true}
                                    Text{visible:locked;text:"⌑";color:win.muted;font.pixelSize:11}
                                    Text{text:shown?"●":"○";color:shown?win.muted:win.line;font.pixelSize:8;MouseArea{anchors.fill:parent;anchors.margins:-7;onClicked:function(m){m.accepted=true;win.setLayerShown(index,!shown)}}}
                                }
                                MouseArea{id:hover;anchors.fill:parent;hoverEnabled:true;z:-1;onClicked:function(mouse){win.selectLayerFromList(index,mouse.modifiers)}}
                            }}
                        }
                    }
                }
                Divider{Layout.fillWidth:true}
                RowLayout{Layout.fillWidth:true;Layout.preferredHeight:44;Layout.leftMargin:10;Layout.rightMargin:10
                    TinyButton{glyph:"+";onClicked:tool="rect"}TinyButton{glyph:"◇";onClicked:duplicate()}Item{Layout.fillWidth:true}TinyButton{glyph:"⌫";onClicked:remove()}}
            }
        }

        Rectangle{
            id:workspace;Layout.fillWidth:true;Layout.fillHeight:true;color:win.workspaceBackground;clip:true
            HoverHandler{id:workspaceHover;blocking:false;onHoveredChanged:syncWorkspaceCursor()}
            Canvas{id:gridCanvas;anchors.fill:parent;opacity:grid?1:0
                onPaint:{var c=getContext("2d");c.reset();c.strokeStyle=win.gridLine;c.lineWidth=1;var s=24*zoom;for(var x=0;x<width;x+=s){c.beginPath();c.moveTo(x,0);c.lineTo(x,height);c.stroke()}for(var y=0;y<height;y+=s){c.beginPath();c.moveTo(0,y);c.lineTo(width,y);c.stroke()}}
                Connections{target:win;function onZoomChanged(){gridCanvas.requestPaint()}function onSystemDarkChanged(){gridCanvas.requestPaint()}}
            }
            MouseArea{
                anchors.fill:parent;enabled:tool==="select";cursorShape:Qt.ArrowCursor
                onPressed:function(mouse){beginMarquee(mouse.x,mouse.y)}
                onPositionChanged:function(mouse){if(pressed)updateMarquee(mouse.x,mouse.y)}
                onReleased:finishMarquee()
            }
            Rectangle{
                id:artboard;width:920*zoom;height:580*zoom;anchors.centerIn:parent;color:"#f6f5f8";border.color:"#babac2"
                MouseArea{
                    anchors.fill:parent;enabled:tool==="select";cursorShape:Qt.ArrowCursor
                    onPressed:function(mouse){var p=mapToItem(workspace,mouse.x,mouse.y);beginMarquee(p.x,p.y)}
                    onPositionChanged:function(mouse){if(pressed){var p=mapToItem(workspace,mouse.x,mouse.y);updateMarquee(p.x,p.y)}}
                    onReleased:finishMarquee()
                }
                Text{text:pages.get(currentPage).pageName;color:win.muted;font.pixelSize:11;x:2;y:-24}
                Repeater{model:layers;delegate:Item{
                    id:item;required property int index;required property string type;required property string fillColor;required property string strokeColor;required property real strokeSize;required property real corner;required property real cornerTL;required property real cornerTR;required property real cornerBL;required property real cornerBR;required property real fontSize;required property string fontFamily;required property int fontWeight;required property real letterSpacing;required property real lineHeight;required property int textAlign;required property real alpha;required property bool shown;required property bool locked;required property string copy;required property real px;required property real py;required property real sw;required property real sh
                    property bool inlineEditing:false
                    property var inlineHistoryState:null
                    property string inlineOriginalText:""
                    function beginInlineEditing(){
                        if(type!=="text" || locked)return
                        if(!isSelected(index))selectOnly(index)
                        inlineHistoryState=snapshotState();inlineOriginalText=copy;inlineEditing=true
                        inlineEditor.text=copy;inlineEditor.forceActiveFocus();inlineEditor.selectAll()
                    }
                    function finishInlineEditing(cancel){
                        if(!inlineEditing)return
                        if(cancel)layers.setProperty(index,"copy",inlineOriginalText)
                        else if(inlineEditor.text!==inlineOriginalText&&inlineHistoryState)pushUndoState(inlineHistoryState)
                        inlineHistoryState=null;inlineEditor.focus=false;inlineEditing=false
                    }
                    Connections{target:win;function onSelectionChanged(){if(item.inlineEditing&&!win.isSelected(item.index))item.finishInlineEditing(false)}}
                    x:px*zoom;y:py*zoom;width:sw*zoom;height:sh*zoom;visible:shown;opacity:alpha;z:index
                    Rectangle{anchors.fill:parent;color:item.type==="text"?"transparent":item.fillColor;border.color:item.strokeSize>0?item.strokeColor:"transparent";border.width:item.strokeSize*zoom;radius:item.type==="ellipse"?Math.min(width,height)/2:(item.type==="frame"?item.corner*zoom:0);topLeftRadius:item.type==="rect"?item.cornerTL*zoom:radius;topRightRadius:item.type==="rect"?item.cornerTR*zoom:radius;bottomLeftRadius:item.type==="rect"?item.cornerBL*zoom:radius;bottomRightRadius:item.type==="rect"?item.cornerBR*zoom:radius}
                    Text{visible:item.type==="text"&&!item.inlineEditing;anchors.fill:parent;text:item.copy;color:item.fillColor;font.family:item.fontFamily;font.pixelSize:item.fontSize*zoom;font.weight:item.fontWeight;font.letterSpacing:item.letterSpacing*zoom;lineHeight:item.lineHeight*zoom;lineHeightMode:Text.FixedHeight;horizontalAlignment:item.textAlign;verticalAlignment:Text.AlignVCenter;wrapMode:Text.Wrap;style:item.strokeSize>0?Text.Outline:Text.Normal;styleColor:item.strokeColor}
                    MouseArea{
                        anchors.fill:parent;enabled:!item.locked&&!item.inlineEditing;hoverEnabled:true
                        cursorShape:tool==="select"?Qt.ArrowCursor:Qt.CrossCursor
                        property real dragStartX:0
                        property real dragStartY:0
                        property var dragOrigins:[]
                        property var dragHistoryState:null
                        property bool dragChanged:false
                        onPressed:function(mouse){
                            if(tool!=="select") return
                            if(!isSelected(item.index)) selectOnly(item.index)
                            var p=mapToItem(workspace,mouse.x,mouse.y)
                            dragStartX=p.x;dragStartY=p.y
                            dragHistoryState=snapshotState();dragChanged=false
                            var origins=[]
                            for(var i=0;i<selection.length;i++){
                                var layerIndex=selection[i]
                                if(layerIndex>=0&&layerIndex<layers.count){
                                    var layer=layers.get(layerIndex)
                                    origins.push({index:layerIndex,x:layer.px,y:layer.py})
                                }
                            }
                            dragOrigins=origins
                        }
                        onPositionChanged:function(mouse){
                            if(!pressed||tool!=="select") return
                            var p=mapToItem(workspace,mouse.x,mouse.y)
                            var dx=(p.x-dragStartX)/zoom
                            var dy=(p.y-dragStartY)/zoom
                            if(Math.abs(dx)>0.01 || Math.abs(dy)>0.01) dragChanged=true
                            for(var i=0;i<dragOrigins.length;i++){
                                var origin=dragOrigins[i]
                                layers.setProperty(origin.index,"px",origin.x+dx)
                                layers.setProperty(origin.index,"py",origin.y+dy)
                            }
                        }
                        onReleased:{if(dragChanged&&dragHistoryState)pushUndoState(dragHistoryState);dragOrigins=[];dragHistoryState=null;dragChanged=false}
                        onDoubleClicked:function(mouse){if(tool==="select"&&item.type==="text"){mouse.accepted=true;item.beginInlineEditing()}}
                    }
                    TextEdit{
                        id:inlineEditor;visible:item.inlineEditing;anchors.fill:parent;z:25;clip:true
                        color:item.fillColor;selectionColor:win.accent;selectedTextColor:"white"
                        font.family:item.fontFamily;font.pixelSize:item.fontSize*zoom;font.weight:item.fontWeight;font.letterSpacing:item.letterSpacing*zoom
                        horizontalAlignment:item.textAlign;verticalAlignment:Text.AlignVCenter;wrapMode:TextEdit.Wrap
                        onTextChanged:{if(item.inlineEditing&&item.index>=0&&item.index<layers.count)layers.setProperty(item.index,"copy",text)}
                        onActiveFocusChanged:{if(item.inlineEditing&&!activeFocus)item.finishInlineEditing(false)}
                        Keys.onEscapePressed:function(event){item.finishInlineEditing(true);event.accepted=true}
                        Keys.onPressed:function(event){if((event.modifiers&Qt.ControlModifier)&&(event.key===Qt.Key_Return||event.key===Qt.Key_Enter)){item.finishInlineEditing(false);event.accepted=true}}
                    }
                    Rectangle{visible:isSelected(item.index);anchors.fill:parent;color:"transparent";border.color:"#6657e8";border.width:1;z:20
                        Repeater{model:[{xx:-3,yy:-3},{xx:item.width-3,yy:-3},{xx:-3,yy:item.height-3},{xx:item.width-3,yy:item.height-3}];delegate:Rectangle{required property var modelData;x:modelData.xx;y:modelData.yy;width:7;height:7;radius:2;color:"white";border.color:"#6657e8"}}
                        Rectangle{width:14;height:14;anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:-7;color:"transparent";z:30
                            MouseArea{anchors.fill:parent;anchors.margins:-4;cursorShape:Qt.SizeFDiagCursor;property real sx;property real sy;property real ow;property real oh;property var resizeHistoryState:null;property bool resizeChanged:false
                                onPressed:function(m){sx=m.x;sy=m.y;ow=item.sw;oh=item.sh;resizeHistoryState=snapshotState();resizeChanged=false}
                                onPositionChanged:function(m){if(pressed){var nw=Math.round(Math.max(16,ow+(m.x-sx)/zoom));var nh=Math.round(Math.max(16,oh+(m.y-sy)/zoom));if(nw!==item.sw||nh!==item.sh)resizeChanged=true;layers.setProperty(index,"sw",nw);layers.setProperty(index,"sh",nh)}}
                                onReleased:{if(resizeChanged&&resizeHistoryState)pushUndoState(resizeHistoryState);resizeHistoryState=null;resizeChanged=false}
                            }
                        }
                        Repeater{
                            model:item.type==="rect"?[{hx:-1,hy:-1,role:"cornerTL"},{hx:1,hy:-1,role:"cornerTR"},{hx:-1,hy:1,role:"cornerBL"},{hx:1,hy:1,role:"cornerBR"}]:[]
                            delegate:Rectangle{
                                required property var modelData
                                property real cornerValue:layers.get(index)[modelData.role]
                                property real inset:Math.max(13,Math.min(cornerValue*zoom,Math.min(item.width,item.height)/2-5))
                                x:modelData.hx<0?inset-width/2:item.width-inset-width/2
                                y:modelData.hy<0?inset-height/2:item.height-inset-height/2
                                width:8;height:8;radius:4;color:"white";border.color:win.accent;border.width:1.5;z:40
                                MouseArea{
                                    anchors.fill:parent;anchors.margins:-6;cursorShape:Qt.SizeFDiagCursor
                                    property var cornerHistoryState:null
                                    property bool cornerChanged:false
                                    onPressed:{cornerHistoryState=snapshotState();cornerChanged=false}
                                    onPositionChanged:function(mouse){
                                        if(!pressed)return
                                        var p=mapToItem(item,mouse.x,mouse.y)
                                        var dx=modelData.hx<0?p.x:item.width-p.x
                                        var dy=modelData.hy<0?p.y:item.height-p.y
                                        var radiusValue=Math.max(0,Math.min(Math.min(item.sw,item.sh)/2,(dx+dy)/(2*zoom)))
                                        if(Math.abs(radiusValue-cornerValue)>0.01)cornerChanged=true
                                        layers.setProperty(index,modelData.role,radiusValue)
                                    }
                                    onReleased:{if(cornerChanged&&cornerHistoryState)pushUndoState(cornerHistoryState);cornerHistoryState=null;cornerChanged=false}
                                }
                            }
                        }
                    }
                }}
            }
            MouseArea{
                anchors.fill:parent;z:500;enabled:isShapeTool(tool);cursorShape:Qt.CrossCursor
                onPressed:function(mouse){beginDrawing(mouse.x,mouse.y)}
                onPositionChanged:function(mouse){if(pressed)updateDrawing(mouse.x,mouse.y,mouse.modifiers)}
                onReleased:function(mouse){updateDrawing(mouse.x,mouse.y,mouse.modifiers);finishDrawing()}
                onCanceled:{drawingShape=false}
            }
            Rectangle{
                visible:drawingShape;x:artboard.x+drawX*zoom;y:artboard.y+drawY*zoom;width:drawWidth*zoom;height:drawHeight*zoom;z:501
                color:"#336c5ce7";border.color:win.accent;border.width:1
                radius:tool==="ellipse"?Math.min(width,height)/2:(tool==="frame"?12*zoom:Math.min(6,Math.min(width,height)/2))
            }
            Rectangle{
                visible:marqueeActive;width:marqueeWidth;height:marqueeHeight;x:marqueeX;y:marqueeY
                color:"#334a90e2";border.color:"#4a90e2";border.width:1;z:1000
            }
            Row{anchors.bottom:parent.bottom;anchors.horizontalCenter:parent.horizontalCenter;anchors.bottomMargin:18;spacing:2;padding:4;z:600
                Rectangle{anchors.fill:parent;anchors.margins:-4;color:win.panel;opacity:.94;radius:10;border.color:win.line;z:-1}
                TinyButton{glyph:"−";onClicked:zoom=Math.max(.25,zoom-.1)}Text{width:54;height:30;text:Math.round(zoom*100)+"%";color:win.ink;font.pixelSize:11;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter}TinyButton{glyph:"+";onClicked:zoom=Math.min(2,zoom+.1)}Divider{height:18;anchors.verticalCenter:parent.verticalCenter}TinyButton{glyph:"#";onClicked:grid=!grid}
            }
        }

        Rectangle{
            visible:rightOpen;Layout.preferredWidth:286;Layout.fillHeight:true;color:win.panel;border.color:win.line
            ScrollView{anchors.fill:parent;clip:true
                ColumnLayout{width:284;spacing:0
                    RowLayout{Layout.fillWidth:true;Layout.preferredHeight:46;Layout.leftMargin:16;Layout.rightMargin:10
                        Text{text:"Design";color:win.ink;font.pixelSize:12;font.weight:Font.DemiBold}Text{text:"Prototype";color:win.muted;font.pixelSize:12;Layout.leftMargin:16}Item{Layout.fillWidth:true}TinyButton{glyph:"›";onClicked:rightOpen=false}}
                    Divider{Layout.fillWidth:true}
                    Text{visible:selected<0;text:"Select a layer to edit its properties";color:win.muted;font.pixelSize:11;wrapMode:Text.Wrap;Layout.fillWidth:true;Layout.margins:16}
                    Section{heading:"Position";visible:selected>=0
                        GridLayout{columns:2;columnSpacing:8;rowSpacing:8;Layout.fillWidth:true
                            NumBox{label:"X";number:value("px",0);onEdited:function(v){setValue("px",v)}}NumBox{label:"Y";number:value("py",0);onEdited:function(v){setValue("py",v)}}
                            NumBox{label:"W";number:value("sw",0);onEdited:function(v){setValue("sw",Math.max(1,v))}}NumBox{label:"H";number:value("sh",0);onEdited:function(v){setValue("sh",Math.max(1,v))}}
                        }
                    }
                    Divider{Layout.fillWidth:true;visible:selected>=0}
                    Section{heading:"Text";visible:selectedType==="text"
                        TextField{
                            property var editHistoryState:null
                            property string originalText:""
                            Layout.fillWidth:true;implicitHeight:34;text:value("copy","");placeholderText:"Text";color:win.ink;font.pixelSize:11;selectByMouse:true
                            background:Rectangle{color:win.surface;border.color:parent.activeFocus?win.accent:win.controlBorder;radius:7}
                            onActiveFocusChanged:{
                                if(activeFocus){editHistoryState=snapshotState();originalText=text}
                                else if(editHistoryState){
                                    if(text!==originalText)pushUndoState(editHistoryState)
                                    editHistoryState=null
                                }
                            }
                            onTextEdited:{if(selected>=0&&selected<layers.count)layers.setProperty(selected,"copy",text)}
                            onAccepted:focus=false
                        }
                        RowLayout{Layout.fillWidth:true;spacing:8
                            TextField{Layout.fillWidth:true;implicitHeight:32;text:value("fontFamily","Arial");placeholderText:"Font family";color:win.ink;font.pixelSize:11;selectByMouse:true;background:Rectangle{color:win.surface;border.color:parent.activeFocus?win.accent:win.controlBorder;radius:7}onEditingFinished:setValue("fontFamily",text)}
                            NumBox{label:"S";number:value("fontSize",16);Layout.preferredWidth:76;onEdited:function(v){setValue("fontSize",Math.max(1,v))}}
                        }
                        RowLayout{Layout.fillWidth:true;spacing:8
                            ComboBox{id:weightBox;Layout.fillWidth:true;implicitHeight:32;model:["Regular","Medium","Semibold","Bold"];currentIndex:{var w=win.value("fontWeight",400);return w>=700?3:(w>=600?2:(w>=500?1:0))}onActivated:function(i){setValue("fontWeight",[400,500,600,700][i])}}
                            NumBox{label:"↔";number:value("letterSpacing",0);Layout.preferredWidth:76;onEdited:function(v){setValue("letterSpacing",v)}}
                            NumBox{label:"↕";number:value("lineHeight",20);Layout.preferredWidth:76;onEdited:function(v){setValue("lineHeight",Math.max(1,v))}}
                        }
                        RowLayout{Layout.fillWidth:true;spacing:3
                            Text{text:"Align";color:win.muted;font.pixelSize:11;Layout.fillWidth:true}
                            TinyButton{glyph:"≡";onClicked:setValue("textAlign",Text.AlignLeft)}
                            TinyButton{glyph:"≣";onClicked:setValue("textAlign",Text.AlignHCenter)}
                            TinyButton{glyph:"☰";onClicked:setValue("textAlign",Text.AlignRight)}
                        }
                    }
                    Divider{Layout.fillWidth:true;visible:selectedType==="text"}
                    Section{heading:selectedType==="text"?"Text color":"Fill";visible:selected>=0
                        RowLayout{Layout.fillWidth:true;spacing:8
                            Rectangle{width:28;height:28;radius:7;color:value("fillColor","#fff");border.color:win.controlBorder}
                            TextField{Layout.fillWidth:true;implicitHeight:32;text:value("fillColor","#fff");color:win.ink;font.pixelSize:11;selectByMouse:true;background:Rectangle{color:win.surface;border.color:parent.activeFocus?win.accent:win.controlBorder;radius:7} onEditingFinished:setValue("fillColor",text)}
                            Text{text:Math.round(value("alpha",1)*100)+"%";color:win.muted;font.pixelSize:11}
                        }
                        Slider{Layout.fillWidth:true;from:0;to:1;value:win.value("alpha",1);onMoved:setValue("alpha",value)
                            background:Rectangle{x:parent.leftPadding;y:parent.topPadding+parent.availableHeight/2-2;width:parent.availableWidth;height:3;radius:2;color:win.line;Rectangle{width:parent.width*parent.parent.visualPosition;height:parent.height;radius:2;color:win.accent}}
                            handle:Rectangle{x:parent.leftPadding+parent.visualPosition*(parent.availableWidth-width);y:parent.topPadding+parent.availableHeight/2-height/2;width:13;height:13;radius:7;color:"white";border.color:win.accent}
                        }
                    }
                    Divider{Layout.fillWidth:true;visible:selected>=0}
                    Section{heading:"Corners";visible:selectedType==="rect" || selectedType==="frame"
                        GridLayout{columns:2;columnSpacing:8;rowSpacing:8;Layout.fillWidth:true
                            NumBox{label:"⌜";number:value("cornerTL",0);onEdited:function(v){setValue("cornerTL",Math.max(0,v))}}
                            NumBox{label:"⌝";number:value("cornerTR",0);onEdited:function(v){setValue("cornerTR",Math.max(0,v))}}
                            NumBox{label:"⌞";number:value("cornerBL",0);onEdited:function(v){setValue("cornerBL",Math.max(0,v))}}
                            NumBox{label:"⌟";number:value("cornerBR",0);onEdited:function(v){setValue("cornerBR",Math.max(0,v))}}
                        }
                        Button{text:"Set all corners";Layout.fillWidth:true;implicitHeight:30;onClicked:setAllCorners(value("cornerTL",0))}
                    }
                    Divider{Layout.fillWidth:true;visible:selectedType==="rect" || selectedType==="frame"}
                    Section{heading:selectedType==="text"?"Text border":"Border";visible:selected>=0
                        RowLayout{Layout.fillWidth:true;spacing:8
                            Rectangle{width:28;height:28;radius:7;color:value("strokeColor","#fff");border.color:win.controlBorder}
                            TextField{Layout.fillWidth:true;implicitHeight:32;text:value("strokeColor","#fff");color:win.ink;font.pixelSize:11;selectByMouse:true;background:Rectangle{color:win.surface;border.color:parent.activeFocus?win.accent:win.controlBorder;radius:7}onEditingFinished:setValue("strokeColor",text)}
                            NumBox{label:"W";number:value("strokeSize",0);Layout.preferredWidth:70;onEdited:function(v){setValue("strokeSize",Math.max(0,v))}}
                        }
                    }
                    Divider{Layout.fillWidth:true;visible:selected>=0}
                    Section{heading:"Layer";visible:selected>=0
                        RowLayout{Layout.fillWidth:true
                            CheckBox{text:"Locked";checked:value("locked",false);onToggled:setValue("locked",checked);contentItem:Text{leftPadding:parent.indicator.width+parent.spacing;text:parent.text;color:win.muted;font.pixelSize:11;verticalAlignment:Text.AlignVCenter}}
                            Item{Layout.fillWidth:true}TinyButton{glyph:"◇";onClicked:duplicate()}TinyButton{glyph:"⌫";onClicked:remove()}
                        }
                    }
                }
            }
        }
        Rectangle{visible:!rightOpen;Layout.preferredWidth:42;Layout.fillHeight:true;color:win.panel;border.color:win.line;TinyButton{anchors.top:parent.top;anchors.horizontalCenter:parent.horizontalCenter;anchors.topMargin:9;glyph:"‹";onClicked:rightOpen=true}}
    }
}
