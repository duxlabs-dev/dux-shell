# ActionsExample Plugin

Shows how a plugin offers its own actions to the launcher and to semantic search.

The daemon registers two actions through `pluginService.registerActions()`:

- **Start timer** takes a required `duration` parameter. "15 minutes", "1 saat 30 dk", "15m" and "yarım saat" all work; the shell extracts the number, the plugin only receives `values.duration` in minutes.
- **Cancel timer** is only available while a countdown runs, so it neither shows up in search nor gets embedded otherwise.

The English `text` is what the search model reads; `title` is translated with `I18n.trFor`.

See [Launcher Actions](../README.md#launcher-actions) for the full contract.
