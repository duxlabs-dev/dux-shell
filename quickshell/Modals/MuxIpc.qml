import Quickshell
import Quickshell.Io

Scope {
    id: root

    required property LazyLoader loader

    function modal() {
        loader.active = true;
        return loader.item;
    }

    IpcHandler {
        function open(): string {
            root.modal().show();
            return "MUX_OPEN_SUCCESS";
        }

        function close(): string {
            root.loader.item?.hide();
            return "MUX_CLOSE_SUCCESS";
        }

        function toggle(): string {
            root.modal().toggle();
            return "MUX_TOGGLE_SUCCESS";
        }

        target: "mux"
    }

    // Backwards compatibility
    IpcHandler {
        function open(): string {
            root.modal().show();
            return "TMUX_OPEN_SUCCESS";
        }

        function close(): string {
            root.loader.item?.hide();
            return "TMUX_CLOSE_SUCCESS";
        }

        function toggle(): string {
            root.modal().toggle();
            return "TMUX_TOGGLE_SUCCESS";
        }

        target: "tmux"
    }
}
