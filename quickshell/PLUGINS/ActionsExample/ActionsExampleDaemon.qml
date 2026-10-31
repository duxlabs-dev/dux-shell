import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    property real endsAt: 0

    // One timer for the whole plugin; it only runs while a countdown is active.
    Timer {
        id: countdown
        repeat: false
        onTriggered: {
            root.endsAt = 0;
            ToastService.showInfo(I18n.trFor("actionsExample", "Time is up"));
        }
    }

    function start(values) {
        countdown.interval = Math.round(values.duration * 60 * 1000);
        endsAt = Date.now() + countdown.interval;
        countdown.restart();
        ToastService.showInfo(I18n.trFor("actionsExample", "Timer set for %1 minutes").arg(values.duration));
    }

    function cancel() {
        countdown.stop();
        endsAt = 0;
    }

    function remainingText() {
        const minutes = Math.ceil((endsAt - Date.now()) / 60000);
        return I18n.trFor("actionsExample", "%1 min left").arg(minutes);
    }

    function registerActions() {
        pluginService.registerActions(pluginId, [
            {
                id: "timer.start",
                title: I18n.trFor("actionsExample", "Start timer"),
                text: "Countdown timer. Start a timer for a number of minutes and get a notification when it ends; remind me, alarm, kitchen timer, pomodoro, time my work.",
                keywords: ["timer", "countdown", "alarm", "remind", "zamanlayıcı", "sayaç", "hatırlat"],
                icon: "timer",
                params: [
                    {
                        name: "duration",
                        type: "duration",
                        unit: "minutes",
                        min: 1,
                        max: 1440,
                        required: true,
                        example: "15m"
                    }
                ],
                state: () => root.endsAt > 0 ? root.remainingText() : "",
                run: values => root.start(values)
            },
            {
                id: "timer.cancel",
                title: I18n.trFor("actionsExample", "Cancel timer"),
                text: "Cancel timer. Stop the running countdown timer so it does not ring; never mind, turn off the alarm, clear the timer.",
                keywords: ["cancel timer", "stop timer", "zamanlayıcıyı iptal et", "sayacı durdur"],
                icon: "timer_off",
                available: () => root.endsAt > 0,
                run: () => root.cancel()
            }
        ]);
    }

    // The shell drops these actions when the plugin unloads; registering again
    // on every load keeps them in step with a reload.
    Component.onCompleted: registerActions()
}
