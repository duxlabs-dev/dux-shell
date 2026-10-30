pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import "../Common/WallpaperFormats.js" as WallpaperFormats

// matugen, thumbnails and every blurred or lock surface need a still image,
// so each video wallpaper gets one cached frame, extracted once per file change.
Singleton {
    id: root

    readonly property var log: Log.scoped("VideoWallpaperService")
    readonly property string posterDir: Paths.strip(Paths.cache) + "/video-wallpaper"

    // video path -> frame path, holds only frames that exist on disk
    property var posters: ({})
    property bool ffmpegMissing: false
    property var _queue: []
    property var _queued: ({})
    property var _failed: ({})
    property bool _busy: false

    function isVideo(path) {
        return WallpaperFormats.isVideo(path);
    }

    function posterPath(video) {
        return `${posterDir}/${Qt.md5(video)}.jpg`;
    }

    // Image consumers bind to this: the path itself, or a video's frame once it exists.
    function imageFor(path) {
        if (!path || !WallpaperFormats.isVideo(path))
            return path || "";
        const poster = posters[path];
        if (poster)
            return poster;
        request(path);
        return "";
    }

    // True while a frame for this video may still arrive.
    function framePending(path) {
        return WallpaperFormats.isVideo(path) && !posters[path] && !ffmpegMissing && !_failed[path];
    }

    function request(video) {
        if (ffmpegMissing || _queued[video] || _failed[video] || posters[video])
            return;
        _queued[video] = true;
        _queue.push(video);
        Qt.callLater(_next);
    }

    function _next() {
        if (_busy || _queue.length === 0)
            return;
        _busy = true;
        const video = _queue.shift();
        const poster = posterPath(video);
        // -nt keeps a frame that is newer than its video; the thumbnail filter skips black intro frames.
        const script = 'command -v ffmpeg >/dev/null || exit 127; [ "$1" -nt "$2" ] && exit 0; mkdir -p "${1%/*}" && ffmpeg -nostdin -v error -i "$2" -vf "thumbnail=60,scale=\'min(3840,iw)\':-2" -frames:v 1 -q:v 2 -y "$1.part.jpg" 2>&1 && mv -f "$1.part.jpg" "$1"';
        Proc.runCommand("videoWallpaperPoster", ["sh", "-c", script, "sh", poster, video], (output, exitCode) => {
            delete _queued[video];
            _busy = false;
            if (exitCode === 127) {
                ffmpegMissing = true;
                _queue = [];
                _queued = {};
                log.warn("ffmpeg not found, video wallpapers play without a theme or thumbnail frame");
                return;
            }
            if (exitCode !== 0) {
                _failed[video] = true;
                log.warn("could not extract a frame from", video + ":", output.trim());
            } else {
                posters = Object.assign({}, posters, {
                    [video]: poster
                });
            }
            _next();
        }, 0, 60000);
    }
}
