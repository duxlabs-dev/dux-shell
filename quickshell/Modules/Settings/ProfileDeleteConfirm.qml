import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services

ConfirmModal {
    function request(profile, onDeleted) {
        if (profile.id === ConfigProfileService.activeProfileId) {
            ToastService.showWarning(I18n.tr("Cannot delete the active profile", "config profile: shown instead of the delete confirmation"));
            return;
        }
        showWithOptions({
            title: I18n.tr("Delete profile"),
            message: I18n.tr("Delete \"%1\"?", "delete confirmation, %1 is a config profile name").arg(profile.name),
            confirmText: I18n.tr("Delete"),
            confirmColor: Theme.error,
            onConfirm: onDeleted
        });
    }
}
