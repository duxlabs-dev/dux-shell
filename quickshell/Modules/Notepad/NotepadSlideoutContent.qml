import qs.Services

Notepad {
    onHideRequested: slideout.hide()
    onPopoutRequested: {
        slideout.hide();
        PopoutService.openNotepadPopout();
    }
}
