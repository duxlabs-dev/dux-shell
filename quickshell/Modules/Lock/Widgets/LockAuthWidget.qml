pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.Session
import "../../../Common/KeyUtils.js" as KeyUtils

Item {
    id: root

    readonly property var log: Log.scoped("LockAuthWidget")

    property var instanceData: null
    property var lockHost: null
    readonly property var cfg: instanceData?.config ?? ({})
    readonly property string profileVisibility: cfg.profileVisibility ?? (cfg.showProfileImage === false ? "never" : "always")
    readonly property string passwordVisibility: cfg.passwordVisibility ?? (cfg.showPasswordField === false ? "typing" : "always")
    readonly property bool inputRevealed: lockHost?.inputRevealed ?? false
    readonly property bool authVisible: demoMode || inputRevealed || passwordBuffer.length > 0 || authenticating || unlocking || failed || (pam?.u2fPending ?? false) || currentAuthFeedbackText() !== ""
    readonly property bool showProfileImage: profileVisibility === "always" || (profileVisibility === "typing" && authVisible)
    readonly property bool showPasswordField: passwordVisibility === "always" || authVisible
    readonly property string style: cfg.style ?? "expressive"
    readonly property bool contained: style === "pill" || style === "expressive"
    readonly property bool dots: style === "dots"
    readonly property bool ring: style === "ring"
    readonly property bool morph: style === "expressive"
    readonly property bool minimal: style === "minimal"
    readonly property bool authenticating: (pam?.authBusy ?? false) && !unlocking
    readonly property bool failed: pamState !== ""
    readonly property var morphShapes: ["cookie4", "clover4", "sunny", "cookie9", "softBurst", "pentagon", "oval", "cookie6"]
    readonly property string morphShape: morphShapes[passwordBuffer.length % morphShapes.length]
    readonly property real ringSize: LockMetrics.fieldHeight * 2.5
    readonly property real ringStroke: Theme.spacingS
    property int typedCount: 0
    property real keyAngle: 0

    onPasswordBufferChanged: {
        const grew = passwordBuffer.length > typedCount;
        typedCount = passwordBuffer.length;
        if (!grew || demoMode)
            return;
        lockHost.setInputRevealed(true);
        keyAngle = (passwordBuffer.length * 137.5) % 360;
        if (ring)
            keyPulse.restart();
        if (morph)
            morphPulse.restart();
    }
    readonly property color accentColor: Theme.primary
    readonly property color plainColor: Theme.lockScreenContentColor
    readonly property bool resizable: true
    readonly property real minWidth: ring ? ringSize : LockMetrics.fieldWidth / 2
    readonly property real minHeight: implicitHeight
    property alias showPassword: passwordBox.showPassword

    readonly property var pam: lockHost?.pam ?? null
    readonly property bool demoMode: lockHost?.demoMode ?? true
    readonly property bool unlocking: lockHost?.unlocking ?? false
    readonly property string pamState: lockHost?.pamState ?? ""
    readonly property string passwordBuffer: lockHost?.passwordBuffer ?? ""

    implicitWidth: ring ? ringSize : Math.min(LockMetrics.passwordRowWidth, (lockHost?.width ?? LockMetrics.passwordRowWidth) - Theme.spacingXL * 2)
    implicitHeight: passwordLayout.implicitHeight
    // Feedback and the caps lock warning hang below the box so centring the box centres the field.
    readonly property real bottomOverflow: Theme.spacingS + Math.max(capsLockRow.implicitHeight, authFeedbackText.height)

    function encodeFileUrl(path) {
        if (!path)
            return "";
        return "file://" + path.split('/').map(s => encodeURIComponent(s)).join('/');
    }

    function focusPasswordField() {
        if (demoMode)
            return;
        passwordField.forceActiveFocus();
    }

    function currentAuthFeedbackText() {
        if (!pam)
            return "";
        const promptInFeedback = dots || ring;
        if (pam.u2fState === "insert" && (!pam.u2fPending || promptInFeedback))
            return I18n.tr("Insert your security key...");
        if (pam.u2fState === "waiting" && (!pam.u2fPending || promptInFeedback))
            return I18n.tr("Touch your security key...");
        if (pam.lockMessage && pam.lockMessage.length > 0)
            return pam.lockMessage;
        if (pamState === "error")
            return I18n.tr("Authentication error - try again");
        if (pamState === "max")
            return I18n.tr("Too many attempts - locked out");
        if (pamState === "fail")
            return I18n.tr("Incorrect password - try again");
        if (pam.fprint.status === "disabled")
            return "";
        if (pam.fprintState === "error")
            return I18n.tr("Fingerprint error");
        if (pam.fprintState === "max")
            return I18n.tr("Maximum fingerprint attempts reached. Please use password.");
        if (pam.fprintState === "fail")
            return I18n.tr("Fingerprint not recognized (%1/%2). Please try again or use password.", "lock screen message, %1 is attempts used, %2 is max attempts").arg(pam.fprint.tries).arg(SettingsData.maxFprintTries);
        return "";
    }

    function authFeedbackIsHint() {
        return pam && (pam.u2fState === "waiting" || pam.u2fState === "insert") && (!pam.u2fPending || dots || ring);
    }

    function canStartSecurityKeyUnlock() {
        return !demoMode && pam && pam.u2f && pam.u2f.available && SettingsData.enableU2f && SettingsData.u2fMode === "or" && !pam.authBusy && !pam.u2f.active && !pam.u2fPending && !unlocking;
    }

    function triggerSecurityKeyUnlock() {
        if (!canStartSecurityKeyUnlock())
            return;
        passwordField.clear();
        pam.u2f.startForAlternativeAuth();
    }

    function securityKeyShortcutMatches(event) {
        return SettingsData.lockScreenSecurityKeyShortcutEnabled && KeyUtils.eventMatchesCombo(event, SettingsData.lockScreenSecurityKeyShortcut);
    }

    onLockHostChanged: {
        if (!lockHost)
            return;
        lockHost.authWidget = root;
        focusPasswordField();
    }

    Component.onDestruction: {
        if (lockHost && lockHost.authWidget === root)
            lockHost.authWidget = null;
    }

    Connections {
        target: root.lockHost
        enabled: root.lockHost !== null

        function onAuthFailed() {
            errorShake.restart();
            passwordBox.showPassword = false;
            passwordField.clear();
        }
    }

    Connections {
        target: root.pam
        enabled: root.pam !== null

        function onU2fPendingChanged() {
            if (!root.pam.u2fPending)
                return;
            passwordField.clear();
            if (keyboardController.isKeyboardActive)
                keyboardController.hide();
        }

        // onStateChanged only fires when the conversation ends, too late between prompts
        function onAwaitingUserInputChanged() {
            if (root.pam.awaitingUserInput)
                passwordField.clear();
        }
    }

    ColumnLayout {
        id: passwordLayout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Item {
            id: ringIndicator

            readonly property color toneColor: root.failed ? Theme.error : root.accentColor
            readonly property real radius: root.ringSize / 2 - root.ringStroke / 2

            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.ringSize
            Layout.preferredHeight: root.ringSize
            visible: root.ring
            opacity: root.showPasswordField || root.showProfileImage ? 1 : 0
            transform: Translate {
                x: Math.max(-LockMetrics.shakeDistance, Math.min(LockMetrics.shakeDistance, passwordBox.errorOffset))
            }

            Shape {
                anchors.fill: parent
                opacity: root.showPasswordField ? 1 : 0
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: {
                        if (root.failed)
                            return Theme.withAlpha(Theme.error, Theme.pendingOpacity);
                        if (root.authenticating || root.passwordBuffer.length === 0)
                            return Theme.withAlpha(root.plainColor, Theme.stateLayerDrag);
                        return Theme.withAlpha(root.accentColor, Theme.pendingOpacity);
                    }
                    strokeWidth: root.ringStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: root.ringSize / 2
                        centerY: root.ringSize / 2
                        radiusX: ringIndicator.radius
                        radiusY: ringIndicator.radius
                        startAngle: 0
                        sweepAngle: 360
                    }

                    Behavior on strokeColor {
                        ColorAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }
            }

            Shape {
                id: keySegment
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: 0

                ShapePath {
                    strokeColor: root.accentColor
                    strokeWidth: root.ringStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: root.ringSize / 2
                        centerY: root.ringSize / 2
                        radiusX: ringIndicator.radius
                        radiusY: ringIndicator.radius
                        startAngle: root.keyAngle - 90
                        sweepAngle: 30
                    }
                }

                SequentialAnimation {
                    id: keyPulse
                    PropertyAction {
                        target: keySegment
                        property: "opacity"
                        value: 1
                    }
                    NumberAnimation {
                        target: keySegment
                        property: "opacity"
                        to: 0
                        duration: Theme.expressiveDurations.expressiveSlowEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }
            }

            Shape {
                id: verifyArc
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: root.ring && root.authenticating

                ShapePath {
                    strokeColor: root.accentColor
                    strokeWidth: root.ringStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: root.ringSize / 2
                        centerY: root.ringSize / 2
                        radiusX: ringIndicator.radius
                        radiusY: ringIndicator.radius
                        startAngle: -90
                        sweepAngle: 90
                    }
                }

                RotationAnimator on rotation {
                    running: verifyArc.visible
                    loops: Animation.Infinite
                    duration: Anims.durLong
                    from: 0
                    to: 360
                }
            }

            DCircularImage {
                anchors.centerIn: parent
                width: root.ringSize - root.ringStroke * 4
                height: width
                visible: root.showProfileImage
                imageSource: {
                    if (PortalService.profileImage === "")
                        return "";
                    if (PortalService.profileImage.startsWith("/"))
                        return root.encodeFileUrl(PortalService.profileImage);
                    return PortalService.profileImage;
                }
                fallbackIcon: "material:person"
            }

            DIcon {
                anchors.centerIn: parent
                visible: !root.showProfileImage
                name: root.unlocking ? "lock_open" : "lock"
                size: Theme.iconSizeLarge
                color: ringIndicator.toneColor
            }

            MouseArea {
                anchors.fill: parent
                enabled: !root.demoMode
                onClicked: passwordField.forceActiveFocus()
            }
        }

        RowLayout {
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true
            spacing: Theme.spacingM
            Layout.fillWidth: true

            DCircularImage {
                Layout.preferredWidth: LockMetrics.avatarSize
                ringWidth: Theme.avatarRingWidth
                ringColor: Theme.avatarRingColor
                Layout.preferredHeight: LockMetrics.fieldHeight
                imageSource: {
                    if (PortalService.profileImage === "")
                        return "";
                    if (PortalService.profileImage.startsWith("/"))
                        return root.encodeFileUrl(PortalService.profileImage);
                    return PortalService.profileImage;
                }
                fallbackIcon: "material:person"
                visible: root.showProfileImage && !root.ring
            }

            Rectangle {
                id: passwordBox

                property bool showPassword: false
                property real errorOffset: 0
                readonly property bool focusRingShown: passwordField.activeFocus && Theme.focusRingWidth > 0
                transform: Translate {
                    x: Math.max(-LockMetrics.shakeDistance, Math.min(LockMetrics.shakeDistance, passwordBox.errorOffset))
                }

                Layout.fillWidth: true
                Layout.preferredHeight: root.ring ? 0 : LockMetrics.fieldHeight
                radius: root.style === "expressive" ? Theme.cornerRadiusXL : Theme.fullRadius(width, height)
                color: {
                    if (!root.contained)
                        return "transparent";
                    return root.style === "expressive" ? Theme.surfaceContainerHigh : Theme.cardSurface;
                }
                border.width: {
                    if (!root.contained)
                        return 0;
                    return focusRingShown ? Math.max(Theme.outlineWidth, Theme.focusRingWidth) : Theme.layerOutlineWidth;
                }
                border.color: focusRingShown ? Theme.focusRingColor : Theme.outlineMedium
                Accessible.name: I18n.tr("Password")
                opacity: root.showPasswordField ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: LockMetrics.effectsDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }

                Rectangle {
                    id: underline
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: root.style === "minimal"
                    height: passwordField.activeFocus ? Theme.outlineWidthFocused : Theme.dividerWidth
                    color: {
                        if (root.pamState !== "")
                            return Theme.error;
                        return passwordField.activeFocus ? root.accentColor : Theme.withAlpha(root.plainColor, Theme.pendingOpacity);
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                Item {
                    id: dotViewport
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: passwordViewport.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    clip: true
                    visible: root.dots && !passwordBox.showPassword

                    Row {
                        id: dotRow
                        x: Math.min(0, dotViewport.width - width)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.demoMode ? 6 : Math.max(1, root.passwordBuffer.length)

                            Rectangle {
                                required property int index
                                readonly property bool filled: root.demoMode || index < root.passwordBuffer.length
                                readonly property color tone: root.pamState !== "" ? Theme.error : root.accentColor

                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.iconSizeSmall
                                height: width
                                radius: Theme.fullRadius(width, height)
                                color: filled ? tone : "transparent"
                                border.width: Theme.outlineWidthFocused
                                border.color: filled ? tone : Theme.withAlpha(root.plainColor, Theme.pendingOpacity)
                                scale: filled ? 1 : 0.8

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: LockMetrics.shakeDuration
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: lockIconContainer
                    anchors.left: parent.left
                    anchors.leftMargin: root.morph ? Theme.spacingS : Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.dots && !root.ring && !root.minimal
                    width: !visible ? 0 : (root.morph ? LockMetrics.fieldHeight - Theme.spacingS * 2 : Theme.iconSizeSmall)
                    height: root.morph ? width : Theme.iconSizeSmall

                    DMaterialShape {
                        id: morphContainer
                        anchors.fill: parent
                        visible: root.morph
                        shape: root.morphShape
                        color: root.failed ? Theme.errorContainer : Theme.primaryContainer

                        SequentialAnimation {
                            id: morphPulse
                            NumberAnimation {
                                target: morphContainer
                                property: "scale"
                                to: 1.15
                                duration: LockMetrics.shakeDuration / 2
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                            }
                            NumberAnimation {
                                target: morphContainer
                                property: "scale"
                                to: 1
                                duration: LockMetrics.shakeDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: LockMetrics.effectsDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }

                    DLoadingIndicator {
                        anchors.centerIn: parent
                        size: parent.width
                        contained: true
                        visible: root.morph && root.authenticating
                        running: visible
                    }

                    DIcon {
                        id: lockIcon

                        anchors.centerIn: parent
                        visible: !(root.morph && root.authenticating)
                        name: {
                            if (!root.pam)
                                return "lock";
                            if (root.pam.u2fPending)
                                return "passkey";
                            switch (root.pam.fprint.status) {
                            case "max":
                            case "stopped":
                                return "fingerprint_off";
                            case "active":
                                return "fingerprint";
                            case "retrying":
                                return "hourglass_empty";
                            }
                            if (root.pam.u2f.active)
                                return "passkey";
                            return "lock";
                        }
                        size: Theme.iconSizeSmall
                        color: {
                            if (root.morph)
                                return root.failed ? Theme.onErrorContainer : Theme.onPrimaryContainer;
                            if (root.pam && root.pam.fprint.tries >= SettingsData.maxFprintTries)
                                return Theme.error;
                            if (root.pam && root.pam.u2fState !== "")
                                return Theme.tertiary;
                            if (passwordField.activeFocus)
                                return root.accentColor;
                            return root.contained ? Theme.surfaceVariantText : Theme.withAlpha(root.plainColor, Theme.pendingOpacity);
                        }
                        opacity: root.pam?.authBusy && !root.morph ? 0 : 1

                        Behavior on opacity {
                            NumberAnimation {
                                duration: LockMetrics.effectsDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }
                }

                FocusScope {
                    id: passwordField

                    KeyNavigation.tab: virtualKeyboardButton.visible ? virtualKeyboardButton : passwordField
                    KeyNavigation.backtab: virtualKeyboardButton.visible ? virtualKeyboardButton : passwordField
                    Accessible.role: Accessible.EditableText
                    Accessible.name: I18n.tr("Password")

                    readonly property string text: root.passwordBuffer
                    property int cursorPosition: text.length

                    signal accepted

                    function clampCursorPosition() {
                        cursorPosition = Math.max(0, Math.min(cursorPosition, text.length));
                    }

                    function clear() {
                        root.lockHost?.passwordEdited("");
                        cursorPosition = 0;
                    }

                    function insertText(value) {
                        if (value.length === 0)
                            return;
                        clampCursorPosition();
                        const pos = cursorPosition;
                        root.lockHost.passwordEdited(text.slice(0, pos) + value + text.slice(pos));
                        cursorPosition = pos + value.length;
                    }

                    function backspace() {
                        clampCursorPosition();
                        if (cursorPosition === 0)
                            return;
                        const pos = cursorPosition;
                        root.lockHost.passwordEdited(text.slice(0, pos - 1) + text.slice(pos));
                        cursorPosition = pos - 1;
                    }

                    function deleteForward() {
                        clampCursorPosition();
                        if (cursorPosition === text.length)
                            return;
                        const pos = cursorPosition;
                        root.lockHost.passwordEdited(text.slice(0, pos) + text.slice(pos + 1));
                        cursorPosition = pos;
                    }

                    function deleteToLineStart() {
                        clampCursorPosition();
                        if (cursorPosition === 0)
                            return;
                        root.lockHost.passwordEdited(text.slice(cursorPosition));
                        cursorPosition = 0;
                    }

                    function deleteToLineEnd() {
                        clampCursorPosition();
                        if (cursorPosition === text.length)
                            return;
                        root.lockHost.passwordEdited(text.slice(0, cursorPosition));
                    }

                    function deleteWordBackward() {
                        clampCursorPosition();
                        if (cursorPosition === 0)
                            return;
                        let pos = cursorPosition;
                        while (pos > 0 && text.charAt(pos - 1) === " ")
                            pos--;
                        while (pos > 0 && text.charAt(pos - 1) !== " ")
                            pos--;
                        root.lockHost.passwordEdited(text.slice(0, pos) + text.slice(cursorPosition));
                        cursorPosition = pos;
                    }

                    function isPrintableText(value) {
                        if (value.length === 0)
                            return false;
                        const code = value.charCodeAt(0);
                        return code >= 0x20 && code !== 0x7f;
                    }

                    anchors.fill: parent
                    anchors.leftMargin: lockIconContainer.width + Theme.spacingM * 2
                    anchors.rightMargin: {
                        let margin = Theme.spacingM;
                        if (loadingSpinner.visible)
                            margin += loadingSpinner.width;
                        if (enterButton.visible)
                            margin += enterButton.width + Theme.spacingXXS;
                        if (securityKeyButton.visible)
                            margin += securityKeyButton.width;
                        if (virtualKeyboardButton.visible)
                            margin += virtualKeyboardButton.width;
                        if (revealButton.visible)
                            margin += revealButton.width;
                        return margin;
                    }
                    opacity: 0
                    focus: true
                    enabled: !root.demoMode
                    activeFocusOnTab: !root.demoMode
                    onTextChanged: cursorPosition = text.length
                    onAccepted: {
                        if (!root.demoMode && !root.unlocking && !root.pam.authBusy && !root.pam.u2fPending)
                            root.pam.submitPassword();
                    }
                    Keys.onPressed: event => handleKey(event)

                    function handleKey(event) {
                        if (root.demoMode)
                            return;

                        root.pam.retryFprintOnActivity();

                        if (root.unlocking) {
                            event.accepted = true;
                            return;
                        }

                        if (event.key === Qt.Key_Escape) {
                            if (keyboardController.isKeyboardActive) {
                                keyboardController.hide();
                                event.accepted = true;
                                return;
                            }
                            if (root.pam.u2fPending) {
                                root.pam.cancelU2fPending();
                                event.accepted = true;
                                return;
                            }
                            clear();
                            root.lockHost.setInputRevealed(false);
                            passwordBox.showPassword = false;
                            event.accepted = true;
                            return;
                        }

                        if (root.pam.authBusy) {
                            root.log.debug("PAM is active, ignoring input");
                            event.accepted = true;
                            return;
                        }

                        if ((event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))) {
                            if (root.securityKeyShortcutMatches(event) && root.canStartSecurityKeyUnlock()) {
                                root.triggerSecurityKeyUnlock();
                                event.accepted = true;
                                return;
                            }

                            switch (event.key) {
                            case Qt.Key_A:
                                cursorPosition = 0;
                                event.accepted = true;
                                return;
                            case Qt.Key_E:
                                cursorPosition = text.length;
                                event.accepted = true;
                                return;
                            case Qt.Key_B:
                                clampCursorPosition();
                                cursorPosition = Math.max(0, cursorPosition - 1);
                                event.accepted = true;
                                return;
                            case Qt.Key_F:
                                clampCursorPosition();
                                cursorPosition = Math.min(text.length, cursorPosition + 1);
                                event.accepted = true;
                                return;
                            case Qt.Key_U:
                                deleteToLineStart();
                                event.accepted = true;
                                return;
                            case Qt.Key_K:
                                deleteToLineEnd();
                                event.accepted = true;
                                return;
                            case Qt.Key_W:
                            case Qt.Key_Backspace:
                                deleteWordBackward();
                                event.accepted = true;
                                return;
                            case Qt.Key_H:
                                backspace();
                                event.accepted = true;
                                return;
                            case Qt.Key_D:
                                deleteForward();
                                event.accepted = true;
                                return;
                            }
                        }

                        switch (event.key) {
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            accepted();
                            event.accepted = true;
                            return;
                        case Qt.Key_Backspace:
                            backspace();
                            event.accepted = true;
                            return;
                        case Qt.Key_Delete:
                            deleteForward();
                            event.accepted = true;
                            return;
                        case Qt.Key_Left:
                            clampCursorPosition();
                            cursorPosition = Math.max(0, cursorPosition - 1);
                            event.accepted = true;
                            return;
                        case Qt.Key_Right:
                            clampCursorPosition();
                            cursorPosition = Math.min(text.length, cursorPosition + 1);
                            event.accepted = true;
                            return;
                        case Qt.Key_Home:
                            cursorPosition = 0;
                            event.accepted = true;
                            return;
                        case Qt.Key_End:
                            cursorPosition = text.length;
                            event.accepted = true;
                            return;
                        }

                        if (isPrintableText(event.text)) {
                            insertText(event.text);
                            event.accepted = true;
                        }
                    }

                    // IME commits use a hidden password input: https://github.com/duxlabs-dev/dux-shell/issues/2950
                    // An in-process module like fcitx5-qt draws its popup as an xdg_popup, which the lock surface cannot parent: https://github.com/duxlabs-dev/dux-shell/issues/3669
                    Loader {
                        focus: true
                        active: KeyUtils.compositorTextInputSelected(Quickshell.env("QT_IM_MODULES"), Quickshell.env("QT_IM_MODULE"))
                        sourceComponent: TextInput {
                            id: imeCommitSink

                            focus: true
                            width: Theme.dividerWidth
                            height: 1
                            opacity: 0
                            cursorDelegate: Item {}
                            // Password echo strips ImhHiddenText (QTBUG-88367); NoEcho keeps it so the input method sees a password field
                            echoMode: TextInput.NoEcho
                            inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            KeyNavigation.tab: passwordField.KeyNavigation.tab
                            KeyNavigation.backtab: passwordField.KeyNavigation.backtab
                            Keys.onPressed: event => {
                                passwordField.handleKey(event);
                                if (!event.accepted && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
                                    event.accepted = true;
                            }
                            onTextChanged: {
                                if (text.length === 0)
                                    return;
                                const committed = text;
                                text = "";
                                if (root.demoMode || root.unlocking || root.pam.authBusy)
                                    return;
                                passwordField.insertText(committed);
                            }
                        }
                    }

                    onVisibleChanged: {
                        if (visible)
                            root.focusPasswordField();
                    }
                }

                KeyboardController {
                    id: keyboardController
                    target: passwordField
                    rootObject: root.lockHost
                    expressive: true
                }

                StyledText {
                    id: placeholder

                    anchors.left: lockIconContainer.right
                    anchors.leftMargin: root.minimal ? 0 : Theme.spacingM
                    anchors.right: (revealButton.visible ? revealButton.left : (virtualKeyboardButton.visible ? virtualKeyboardButton.left : (securityKeyButton.visible ? securityKeyButton.left : (enterButton.visible ? enterButton.left : (loadingSpinner.visible ? loadingSpinner.left : parent.right)))))
                    anchors.rightMargin: Theme.spacingXXS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.dots && !root.ring
                    text: {
                        if (root.demoMode || !root.pam)
                            return "";
                        if (root.unlocking)
                            return I18n.tr("Unlocking...", "lock screen status text while unlocking");
                        if (root.pam.u2fPending) {
                            if (root.pam.u2fState === "insert")
                                return I18n.tr("Insert your security key...");
                            return I18n.tr("Touch your security key...");
                        }
                        if (root.pam.authBusy)
                            return I18n.tr("Authenticating...", "lock screen status text while the password is checked");
                        if (root.passwordVisibility !== "always")
                            return "";
                        if (root.pam.authPromptText !== "")
                            return root.pam.authPromptText;
                        return I18n.tr("Password", "lock screen password field placeholder") + "…";
                    }
                    color: {
                        if (root.unlocking || (root.pam?.authBusy ?? false))
                            return root.accentColor;
                        return root.contained ? Theme.outline : Theme.withAlpha(root.plainColor, Theme.pendingOpacity);
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    opacity: (root.demoMode || root.passwordBuffer.length === 0) ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                Item {
                    id: passwordViewport

                    property real scrollX: 0
                    property real scrollY: 0

                    function followCursor() {
                        const rect = passwordDisplay.cursorRectangle;
                        const contentWidth = passwordDisplay.contentWidth + passwordCursor.width;
                        const contentHeight = passwordDisplay.contentHeight;
                        scrollX = followAxis(scrollX, rect.x, rect.x + passwordCursor.width, contentWidth, width);
                        scrollY = contentHeight < height ? (height - contentHeight) / 2 : followAxis(scrollY, rect.y, rect.y + rect.height, contentHeight, height);
                    }

                    function followAxis(offset, start, end, contentSize, viewSize) {
                        if (contentSize <= viewSize)
                            return 0;
                        if (start + offset < 0)
                            return -start;
                        if (end + offset > viewSize)
                            return viewSize - end;
                        return Math.max(viewSize - contentSize, Math.min(0, offset));
                    }

                    anchors.left: lockIconContainer.right
                    anchors.leftMargin: root.minimal ? 0 : Theme.spacingM
                    anchors.right: (revealButton.visible ? revealButton.left : (virtualKeyboardButton.visible ? virtualKeyboardButton.left : (securityKeyButton.visible ? securityKeyButton.left : (enterButton.visible ? enterButton.left : (loadingSpinner.visible ? loadingSpinner.left : parent.right)))))
                    anchors.rightMargin: Theme.spacingXXS
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: Theme.spacingXS
                    anchors.bottomMargin: Theme.spacingXS
                    clip: true
                    visible: (!root.dots || passwordBox.showPassword) && !root.ring

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.demoMode
                        onClicked: passwordField.forceActiveFocus()
                    }

                    onWidthChanged: followCursor()
                    onHeightChanged: followCursor()

                    TextEdit {
                        id: passwordDisplay
                        LayoutMirroring.enabled: false

                        x: passwordViewport.scrollX
                        y: passwordViewport.scrollY
                        width: implicitWidth
                        readOnly: true
                        activeFocusOnPress: false
                        selectByMouse: false
                        wrapMode: TextEdit.NoWrap
                        text: {
                            if (root.demoMode)
                                return "••••••••";
                            if (passwordBox.showPassword)
                                return root.passwordBuffer;
                            return "•".repeat(root.passwordBuffer.length);
                        }
                        color: root.contained ? Theme.surfaceText : root.plainColor
                        font.family: Theme.fontFamily
                        font.weight: Theme.fontWeight
                        font.pixelSize: passwordBox.showPassword ? Theme.fontSizeMedium : (root.contained ? Theme.fontSizeLarge : Theme.fontSizeXLarge)
                        opacity: (root.demoMode || root.passwordBuffer.length > 0) ? 1 : 0

                        onTextChanged: cursorPosition = passwordField.cursorPosition
                        onCursorRectangleChanged: passwordViewport.followCursor()
                        onContentWidthChanged: passwordViewport.followCursor()
                        onContentHeightChanged: passwordViewport.followCursor()

                        Behavior on opacity {
                            NumberAnimation {
                                duration: LockMetrics.effectsDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }

                    DTextCursor {
                        id: passwordCursor

                        x: passwordDisplay.x + passwordDisplay.cursorRectangle.x
                        y: passwordDisplay.y + passwordDisplay.cursorRectangle.y
                        height: passwordDisplay.cursorRectangle.height
                        shown: !root.demoMode && root.showPasswordField && !root.ring && passwordField.activeFocus && !(root.pam?.authBusy ?? false) && !(root.pam?.u2fPending ?? false) && !root.unlocking

                        readonly property int fieldCursorPosition: passwordField.cursorPosition
                        readonly property string fieldText: passwordField.text

                        onFieldCursorPositionChanged: {
                            passwordDisplay.cursorPosition = fieldCursorPosition;
                            resetBlink();
                        }

                        onFieldTextChanged: resetBlink()
                    }
                }

                LockActionButton {
                    id: revealButton

                    activeFocusOnTab: false
                    Accessible.name: parent.showPassword ? I18n.tr("Hide password") : I18n.tr("Show password")

                    anchors.right: virtualKeyboardButton.visible ? virtualKeyboardButton.left : (securityKeyButton.visible ? securityKeyButton.left : (enterButton.visible ? enterButton.left : (loadingSpinner.visible ? loadingSpinner.left : parent.right)))
                    anchors.rightMargin: 0
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: parent.showPassword ? "visibility_off" : "visibility"
                    buttonSize: Theme.buttonHeightXS
                    visible: !root.demoMode && !root.ring && !root.minimal && root.passwordBuffer.length > 0 && !(root.pam?.authBusy ?? false) && !root.unlocking
                    enabled: visible
                    onClicked: parent.showPassword = !parent.showPassword
                }

                LockActionButton {
                    id: securityKeyButton

                    activeFocusOnTab: false

                    anchors.right: enterButton.visible ? enterButton.left : (loadingSpinner.visible ? loadingSpinner.left : parent.right)
                    anchors.rightMargin: 0
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "passkey"
                    buttonSize: Theme.buttonHeightXS
                    visible: root.canStartSecurityKeyUnlock() && !root.ring
                    enabled: visible && root.showPasswordField
                    tooltipText: SettingsData.lockScreenSecurityKeyShortcutEnabled ? I18n.tr("Security key (%1)", "lock screen security key button tooltip with shortcut").arg(SettingsData.lockScreenSecurityKeyShortcut) : I18n.tr("Security key", "lock screen security key button tooltip")
                    onClicked: root.triggerSecurityKeyUnlock()
                }

                LockActionButton {
                    id: virtualKeyboardButton
                    Keys.onEscapePressed: {
                        keyboardController.hide();
                        passwordField.forceActiveFocus();
                    }

                    KeyNavigation.tab: passwordField
                    KeyNavigation.backtab: passwordField
                    Accessible.name: I18n.tr("On-screen keyboard")

                    anchors.right: securityKeyButton.visible ? securityKeyButton.left : (enterButton.visible ? enterButton.left : (loadingSpinner.visible ? loadingSpinner.left : parent.right))
                    anchors.rightMargin: securityKeyButton.visible || enterButton.visible ? 0 : Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "keyboard"
                    buttonSize: Theme.buttonHeightXS
                    visible: !root.demoMode && !root.ring && !root.minimal && !(root.pam?.authBusy ?? false) && !root.unlocking && !(root.pam?.u2fPending ?? false)
                    enabled: visible && root.showPasswordField
                    onClicked: {
                        if (keyboardController.isKeyboardActive)
                            keyboardController.hide();
                        else
                            keyboardController.show();
                    }
                }

                Item {
                    id: loadingSpinner

                    anchors.right: enterButton.visible ? enterButton.left : parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconSize
                    height: Theme.iconSize
                    visible: !root.demoMode && !root.ring && !root.morph && ((root.pam?.authBusy ?? false) || root.unlocking)

                    DIcon {
                        anchors.centerIn: parent
                        name: "check_circle"
                        size: Theme.iconSizeSmall
                        color: root.accentColor
                        visible: root.unlocking

                        opacity: root.unlocking ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: LockMetrics.effectsDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }

                    DLoadingIndicator {
                        anchors.centerIn: parent
                        size: Theme.iconSize
                        contained: root.style === "expressive"
                        color: root.style === "expressive" ? Theme.onPrimaryContainer : root.accentColor
                        visible: (root.pam?.authBusy ?? false) && !root.unlocking
                        running: visible
                    }
                }

                LockActionButton {
                    id: enterButton

                    activeFocusOnTab: false
                    Accessible.name: I18n.tr("Unlock", "verb, lock screen submit button")

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXXS
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "keyboard_return"
                    buttonSize: Theme.buttonHeightXS
                    visible: !root.ring && !root.minimal && (root.demoMode || (!(root.pam?.authBusy ?? false) && !root.unlocking && !(root.pam?.u2fPending ?? false)))
                    enabled: !root.demoMode && root.showPasswordField
                    onClicked: {
                        if (!root.demoMode && !root.unlocking && !root.pam.u2fPending)
                            root.pam.submitPassword();
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: LockMetrics.effectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: LockMetrics.effectsDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }
            }
        }
    }

    Column {
        id: belowField
        anchors.top: passwordLayout.bottom
        anchors.topMargin: Theme.spacingS
        width: Math.max(parent.width, LockMetrics.passwordRowWidth)
        x: (parent.width - width) / 2
        spacing: Theme.spacingXS

        StyledText {
            id: authFeedbackText

            width: parent.width
            height: text.length > 0 ? Math.min(implicitHeight, Math.ceil(Theme.fontSizeSmall * 4.5)) : 0
            text: root.currentAuthFeedbackText()
            color: root.authFeedbackIsHint() ? Theme.outline : Theme.error
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            opacity: text.length > 0 ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: LockMetrics.effectsDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }
        }

        Row {
            id: capsLockRow
            x: (parent.width - width) / 2
            spacing: Theme.spacingXS
            opacity: DMSService.capsLockState ? 1 : 0

            DIcon {
                name: "shift_lock"
                size: Theme.iconSizeSmall
                color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: I18n.tr("Caps Lock is on")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: LockMetrics.effectsDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: !root.demoMode && !root.showPasswordField
        onClicked: {
            root.lockHost.setInputRevealed(true);
            root.focusPasswordField();
        }
    }

    SequentialAnimation {
        id: errorShake
        NumberAnimation {
            target: passwordBox
            property: "errorOffset"
            to: LockMetrics.shakeDistance
            duration: LockMetrics.shakeDuration / 3
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: passwordBox
            property: "errorOffset"
            to: -LockMetrics.shakeDistance
            duration: LockMetrics.shakeDuration / 3
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: passwordBox
            property: "errorOffset"
            to: 0
            duration: LockMetrics.shakeDuration / 3
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }
}
