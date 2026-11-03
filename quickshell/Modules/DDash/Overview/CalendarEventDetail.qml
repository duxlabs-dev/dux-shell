import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../../Common/Format.js" as Format

Column {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var eventData: null
    property bool canEdit: false

    signal editRequested
    signal deleteRequested
    signal closeRequested

    readonly property bool _descriptionIsHtml: /<[a-z][^>]*>/i.test((eventData && eventData.description) || "")
    readonly property string timeText: _timeText()
    readonly property string locationUrl: _locationUrl()

    spacing: Theme.spacingS

    function _locationUrl() {
        const loc = ((eventData && eventData.location) || "").trim();
        if (loc === "")
            return "";
        if (/^https?:\/\/\S+$/i.test(loc))
            return loc;
        if (/^www\.\S+$/i.test(loc))
            return "https://" + loc;
        if (eventData && eventData.meetingUrl)
            return eventData.meetingUrl;
        return "geo:0,0?q=" + encodeURIComponent(loc);
    }

    function _styleAnchors(html) {
        return html.replace(/<a\s([^>]*)>/gi, (m, attrs) => {
            const cleaned = attrs.replace(/style="[^"]*"/gi, "");
            return "<a style=\"text-decoration:none; color:" + Theme.primary + ";\" " + cleaned + ">";
        });
    }

    function _inlineMarkdown(line) {
        let out = Format.escapeHtml(line);
        out = out.replace(/\\([\\`*_{}[\]()#+\-.!~>])/g, "$1");
        out = out.replace(/(?:https?:\/\/|www\.)[^\s<>)\]]*[^\s<>)\].,;:!?"']/g, (m, offset, s) => {
            const prev = offset > 0 ? s[offset - 1] : "";
            if (prev === "(" || prev === "[" || prev === "\"" || prev === "'")
                return m;
            const href = m.startsWith("www.") ? "https://" + m : m;
            return "<a href=\"" + href + "\">" + m + "</a>";
        });
        out = out.replace(/\[([^\]]+)\]\(([^()\s]+)\)/g, "<a href=\"$2\">$1</a>");
        out = out.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
        out = out.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>");
        return out;
    }

    function _descriptionRichText() {
        const raw = ((eventData && eventData.description) || "").trim();
        if (raw === "")
            return "";
        if (_descriptionIsHtml)
            return _styleAnchors(raw);

        const parts = [];
        let list = "";
        const closeList = () => {
            if (list === "")
                return;
            parts.push("</" + list + ">");
            list = "";
        };

        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const ul = lines[i].match(/^\s*[-*+]\s+(.+)$/);
            const ol = lines[i].match(/^\s*\d+[.)]\s+(.+)$/);
            if (ul || ol) {
                const tag = ul ? "ul" : "ol";
                if (list !== tag) {
                    closeList();
                    parts.push("<" + tag + ">");
                    list = tag;
                }
                parts.push("<li>" + _inlineMarkdown((ul || ol)[1]) + "</li>");
                continue;
            }
            closeList();
            parts.push(_inlineMarkdown(lines[i]) + "<br/>");
        }
        closeList();
        return _styleAnchors(parts.join("").replace(/<br\/>$/, ""));
    }

    function _timeText() {
        if (!eventData)
            return "";
        const dateStr = Qt.formatDate(eventData.start, "ddd, MMM d");
        if (eventData.allDay)
            return I18n.tr("All day") + " · " + dateStr;
        const fmt = SettingsData.use24HourClock ? "HH:mm" : "h:mm AP";
        const startStr = Qt.formatTime(eventData.start, fmt);
        if (eventData.start.getTime() === eventData.end.getTime())
            return dateStr + " · " + startStr;
        return dateStr + " · " + startStr + " – " + Qt.formatTime(eventData.end, fmt);
    }

    function openLocation() {
        const url = root.locationUrl;
        if (url.startsWith("geo:") && CalendarDankBackend.connected) {
            CalendarDankBackend.sendRequest("system.openUri", {
                "uri": url
            }, response => {
                if (response && response.error)
                    Qt.openUrlExternally(url);
            });
            return;
        }
        Qt.openUrlExternally(url);
    }

    DetailRow {
        iconName: "calendar_month"
        text: {
            if (!root.eventData)
                return "";
            const acc = root.eventData.account || "";
            return root.eventData.calendar + (acc ? " · " + acc : "");
        }
        visible: !!(root.eventData && root.eventData.calendar)
    }

    DetailRow {
        iconName: "place"
        text: root.eventData ? root.eventData.location : ""
        visible: !!(root.eventData && root.eventData.location)
        link: root.locationUrl !== ""
        onActivated: root.openLocation()
    }

    DetailRow {
        iconName: "videocam"
        text: I18n.tr("Join video call")
        visible: !!(root.eventData && root.eventData.meetingUrl)
        link: true
        onActivated: Qt.openUrlExternally(root.eventData.meetingUrl)
    }

    DetailRow {
        iconName: "link"
        text: root.eventData ? root.eventData.url : ""
        visible: !!(root.eventData && root.eventData.url)
        link: true
        wrapMode: Text.WrapAnywhere
        onActivated: Qt.openUrlExternally(root.eventData.url)
    }

    StyledText {
        id: descriptionText
        width: parent.width
        text: root._descriptionRichText()
        visible: !!(root.eventData && root.eventData.description)
        textFormat: Text.RichText
        linkColor: Theme.primary
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        horizontalAlignment: Text.AlignLeft
        wrapMode: Text.Wrap
        onLinkActivated: link => Qt.openUrlExternally(link)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: descriptionText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS
        layoutDirection: Qt.RightToLeft

        DButton {
            text: I18n.tr("Close")
            buttonHeight: Theme.buttonHeightS
            onClicked: root.closeRequested()
        }

        DButton {
            text: I18n.tr("Delete")
            iconName: "delete"
            buttonHeight: Theme.buttonHeightS
            backgroundColor: Theme.errorHover
            textColor: Theme.error
            visible: root.canEdit
            onClicked: root.deleteRequested()
        }

        DButton {
            text: I18n.tr("Edit")
            iconName: "edit"
            buttonHeight: Theme.buttonHeightS
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            visible: root.canEdit
            onClicked: root.editRequested()
        }
    }

    component DetailRow: Rectangle {
        id: detailRow

        property string iconName: ""
        property string text: ""
        property bool link: false
        property int wrapMode: Text.Wrap

        signal activated

        width: parent.width
        height: detailContent.implicitHeight + Theme.spacingXS * 2
        radius: Theme.cornerRadiusS
        color: "transparent"
        activeFocusOnTab: link
        Accessible.role: link ? Accessible.Link : Accessible.StaticText
        Accessible.name: text

        Keys.onPressed: event => {
            if (!detailRow.link)
                return;
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                detailRow.activated();
                event.accepted = true;
                break;
            }
        }

        FocusRing {}

        StateLayer {
            visible: detailRow.link
            disabled: !detailRow.link
            stateColor: Theme.primary
            cornerRadius: detailRow.radius
            onClicked: detailRow.activated()
        }

        Row {
            id: detailContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingXS
            anchors.rightMargin: Theme.spacingXS
            spacing: Theme.spacingXS

            DIcon {
                name: detailRow.iconName
                size: Theme.iconSizeSmall
                color: detailRow.link ? Theme.primary : Theme.onSurfaceVariant
                anchors.top: parent.top
                anchors.topMargin: Theme.spacingXXS
            }

            StyledText {
                width: parent.width - Theme.iconSizeSmall - parent.spacing
                text: detailRow.text
                font.pixelSize: Theme.fontSizeSmall
                color: detailRow.link ? Theme.primary : Theme.onSurfaceVariant
                wrapMode: detailRow.wrapMode
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
