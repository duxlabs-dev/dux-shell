.pragma library

var IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "bmp", "gif", "webp", "jxl", "avif", "heif", "exr", "svg"];
var VIDEO_EXTENSIONS = ["mp4", "webm", "mkv", "mov", "m4v", "avi"];

function extension(path) {
    const clean = (path || "").split(/[?#]/)[0];
    const dot = clean.lastIndexOf(".");
    if (dot <= clean.lastIndexOf("/"))
        return "";
    return clean.substring(dot + 1).toLowerCase();
}

function isVideo(path) {
    return VIDEO_EXTENSIONS.indexOf(extension(path)) >= 0;
}

function extensions(withVideo) {
    return withVideo ? IMAGE_EXTENSIONS.concat(VIDEO_EXTENSIONS) : IMAGE_EXTENSIONS;
}

function nameFilters(withVideo) {
    return extensions(withVideo).map(ext => "*." + ext);
}

function findPredicate(withVideo) {
    return "\\( " + extensions(withVideo).map(ext => `-iname "*.${ext}"`).join(" -o ") + " \\)";
}
